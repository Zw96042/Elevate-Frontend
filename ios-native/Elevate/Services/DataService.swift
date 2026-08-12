import Foundation

/// Authentication: login with stored credentials and keep session codes fresh.
enum AuthService {
    static func authenticate() async throws -> SkywardSessionCodes {
        guard let credentials = CredentialStore.load() else {
            throw SkywardError.missingSession
        }
        let codes = try await AuthenticationCoordinator.shared.authenticate(credentials: credentials)
        try SessionStore.save(codes)
        return codes
    }

    /// Validates replacement credentials without changing the saved account.
    static func verify(credentials: SkywardCredentials) async throws -> SkywardSessionCodes {
        try await AuthenticationCoordinator.shared.authenticate(credentials: credentials)
    }

    /// Returns a valid session, logging in if needed.
    static func currentSession() async throws -> (codes: SkywardSessionCodes, baseUrl: String) {
        if let codes = SessionStore.load() {
            return (codes, CredentialStore.baseURL)
        }
        let codes = try await authenticate()
        return (codes, CredentialStore.baseURL)
    }

    static func logout() {
        try? SessionStore.clear()
    }
}

/// Coalesces simultaneous first-load and session-refresh login requests.
private actor AuthenticationCoordinator {
    static let shared = AuthenticationCoordinator()
    private var inFlight: Task<SkywardSessionCodes, Error>?
    private var inFlightCredentials: SkywardCredentials?

    func authenticate(credentials: SkywardCredentials) async throws -> SkywardSessionCodes {
        if let inFlight, inFlightCredentials == credentials {
            return try await inFlight.value
        }
        if let inFlight {
            _ = try? await inFlight.value
        }
        let task = Task<SkywardSessionCodes, Error> {
            try await SkywardAuthAPI.authenticate(credentials: credentials)
        }
        inFlight = task
        inFlightCredentials = credentials
        do {
            let codes = try await task.value
            if inFlightCredentials == credentials {
                inFlight = nil
                inFlightCredentials = nil
            }
            return codes
        } catch {
            if inFlightCredentials == credentials {
                inFlight = nil
                inFlightCredentials = nil
            }
            throw error
        }
    }
}

/// Unified data fetching with caching and automatic re-auth, mirroring the
/// RN DataService + UnifiedGPAManager pipeline.
actor DataService {
    static let shared = DataService()

    private static let coursesCacheKey = "unifiedCourseData"
    private static let coursesCacheMaxAge: TimeInterval = 30 * 60      // 30 min
    private static let gradeInfoCacheMaxAge: TimeInterval = 5 * 60     // 5 min

    private var inFlightCourses: Task<[UnifiedCourseData], Error>?
    private var inFlightGradeInfo: [String: Task<GradeInfoResult, Error>] = [:]
    private var cacheGeneration = 0

    // MARK: - Combined course data

    func combinedCourses(forceRefresh: Bool = false) async throws -> [UnifiedCourseData] {
        if !forceRefresh,
           let cached = JSONCache.load([UnifiedCourseData].self, key: Self.coursesCacheKey, maxAge: Self.coursesCacheMaxAge) {
            return cached
        }
        if let task = inFlightCourses {
            return try await task.value
        }
        let generation = cacheGeneration
        let task = Task<[UnifiedCourseData], Error> {
            try await Self.withSessionRetry { codes, baseUrl in
                let history = try await SkywardHistoryAPI.fetchCombinedAcademicData(baseUrl: baseUrl, sessionCodes: codes)
                return Self.transform(history: history)
            }
        }
        inFlightCourses = task
        defer {
            if generation == cacheGeneration { inFlightCourses = nil }
        }
        let courses = try await task.value
        guard generation == cacheGeneration else { throw CancellationError() }
        JSONCache.save(courses, key: Self.coursesCacheKey)
        return courses
    }

    // MARK: - Per-class grade info

    func gradeInfo(params: GradeInfoParams, forceRefresh: Bool = false) async throws -> GradeInfoResult {
        #if DEBUG
        if let sample = SampleData.gradeInfo(for: params) { return sample }
        #endif
        let cacheKey = [
            "gradeInfo", params.stuId, params.corNumId, params.gbId, params.section, params.bucket,
        ].joined(separator: "_")
        if !forceRefresh,
           let cached = JSONCache.load(GradeInfoResult.self, key: cacheKey, maxAge: Self.gradeInfoCacheMaxAge) {
            return cached
        }
        if let task = inFlightGradeInfo[cacheKey] {
            return try await task.value
        }
        let generation = cacheGeneration
        let task = Task<GradeInfoResult, Error> {
            try await Self.withSessionRetry { codes, baseUrl in
                try await SkywardGradesAPI.fetchGradeInfo(params: params, baseUrl: baseUrl, sessionCodes: codes)
            }
        }
        inFlightGradeInfo[cacheKey] = task
        defer {
            if generation == cacheGeneration { inFlightGradeInfo[cacheKey] = nil }
        }
        let result = try await task.value
        guard generation == cacheGeneration else { throw CancellationError() }
        JSONCache.save(result, key: cacheKey)
        return result
    }

    // MARK: - Messages

    func loadMessages() async throws -> [SkywardMessage] {
        try await Self.withSessionRetry { codes, baseUrl in
            let messages = try await SkywardMessagesAPI.fetchMessages(sessionCodes: codes, baseUrl: baseUrl)
            return messages  // already in feed order (newest first)
        }
    }

    func loadMoreMessages(after lastMessageRowId: String, limit: Int = 10) async throws -> [SkywardMessage] {
        try await Self.withSessionRetry { codes, baseUrl in
            try await SkywardMessagesAPI.fetchMoreMessages(
                sessionCodes: codes, baseUrl: baseUrl,
                lastMessageId: lastMessageRowId, limit: limit
            )
        }
    }

    // MARK: - Cache management

    func clearCaches() {
        cacheGeneration += 1
        inFlightCourses?.cancel()
        inFlightCourses = nil
        for task in inFlightGradeInfo.values { task.cancel() }
        inFlightGradeInfo.removeAll()
        JSONCache.clear(prefix: Self.coursesCacheKey)
        JSONCache.clear(prefix: "gradeInfo_")
    }

    // MARK: - Helpers

    /// Runs `operation` with a valid session, re-authenticating once on expiry.
    private static func withSessionRetry<T>(
        _ operation: (SkywardSessionCodes, String) async throws -> T
    ) async throws -> T {
        let (codes, baseUrl) = try await AuthService.currentSession()
        do {
            return try await operation(codes, baseUrl)
        } catch SkywardError.sessionExpired {
            try? SessionStore.clear()
            let freshCodes = try await AuthService.authenticate()
            return try await operation(freshCodes, baseUrl)
        }
    }

    /// Flattens academic history years into the unified course list.
    static func transform(history: AcademicHistory) -> [UnifiedCourseData] {
        var courses: [UnifiedCourseData] = []
        for (_, yearData) in history {
            for (storageKey, c) in yearData.courses {
                let courseName = c.courseName ?? storageKey
                let scores: [BucketScore] = [
                    ("Q1", c.rc1), ("Q2", c.rc2), ("S1", c.sm1), ("EX1", c.ex1),
                    ("Q3", c.rc3), ("Q4", c.rc4), ("S2", c.sm2), ("EX2", c.ex2),
                ].compactMap { bucket, value in
                    guard let value, let score = Double(value) else { return nil }
                    return BucketScore(bucket: bucket, score: score)
                }

                courses.append(UnifiedCourseData(
                    courseId: c.courseId,
                    corNumId: c.corNumId ?? "",
                    stuId: c.stuId ?? "",
                    section: c.section ?? "",
                    gbId: c.gbId ?? "",
                    courseName: courseName,
                    instructor: c.instructor,
                    period: c.period,
                    time: c.time,
                    semester: inferSemester(c.terms),
                    termLength: c.terms,
                    gradeYear: yearData.grade,
                    currentScores: scores,
                    historicalGrades: HistoricalGrades(
                        pr1: c.pr1, pr2: c.pr2, pr3: c.pr3, pr4: c.pr4,
                        pr5: c.pr5, pr6: c.pr6, pr7: c.pr7, pr8: c.pr8,
                        rc1: c.rc1, rc2: c.rc2, rc3: c.rc3, rc4: c.rc4,
                        ex1: c.ex1, ex2: c.ex2,
                        sm1: c.sm1, sm2: c.sm2, finalGrade: c.finalGrade
                    )
                ))
            }
        }
        // Stable ordering: by grade year, then period, then name.
        return courses.sorted {
            if $0.gradeYear != $1.gradeYear { return ($0.gradeYear ?? 0) < ($1.gradeYear ?? 0) }
            if $0.period != $1.period { return ($0.period ?? 99) < ($1.period ?? 99) }
            return $0.courseName < $1.courseName
        }
    }

    static func inferSemester(_ terms: String) -> Semester {
        let t = terms.replacingOccurrences(of: " ", with: "")
        switch t {
        case "1-4": return .both
        case "1-2": return .fall
        case "3-4": return .spring
        default: return .unknown
        }
    }
}

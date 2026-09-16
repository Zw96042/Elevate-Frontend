import Foundation

/// Unified data fetching with caching and automatic re-auth, mirroring the
/// RN DataService + UnifiedGPAManager pipeline.
actor DataService {
    static let shared = DataService()

    private static let coursesCacheKey = "unifiedCourseData"
    private static let messagesCacheKey = "skywardMessages"
    private static let attendanceCacheKey = "skywardAttendance"
    private static let feesCacheKey = "skywardFees"
    private static let studentInfoCacheKey = "skywardStudentInfo"
    private static let documentsCacheKey = "skywardDocuments"
    private static let documentsCacheMaxAge: TimeInterval = 30 * 60
    private static let feesCacheMaxAge: TimeInterval = 30 * 60
    private static let studentInfoCacheMaxAge: TimeInterval = 30 * 60
    private static let attendanceCacheMaxAge: TimeInterval = 30 * 60
    private static let coursesCacheMaxAge: TimeInterval = 30 * 60      // 30 min
    private static let messagesCacheMaxAge: TimeInterval = 30 * 60     // 30 min
    private static let gradeInfoCacheMaxAge: TimeInterval = 5 * 60     // 5 min

    private var inFlightCourses: Task<[UnifiedCourseData], Error>?
    private var inFlightAttendance: Task<AttendanceData, Error>?
    private var inFlightFees: Task<FeesData, Error>?
    private var inFlightStudentInfo: Task<StudentInfoData, Error>?
    private var inFlightDocuments: Task<DocumentsData, Error>?
    private var inFlightGradeInfo: [String: Task<GradeInfoResult, Error>] = [:]
    private var cacheGeneration = 0

    func cancelAuthentication() async {
        await AuthService.cancelAuthentication()
    }

    /// Background expiration must cancel the owned transport, not just its waiter.
    func cancelCourseRefresh(accountScope: String) {
        guard CredentialStore.currentAccountIdentifier == accountScope else { return }
        inFlightCourses?.cancel()
    }

    /// Last-known-good disk values remain available after expiry so AppStore
    /// can retain them only when a real refresh fails, with an honest timestamp.
    nonisolated func cachedCourses() -> JSONCacheRecord<[UnifiedCourseData]>? {
        guard let cacheKey = Self.cacheKey(base: Self.coursesCacheKey) else { return nil }
        let record = JSONCache.record(
            [UnifiedCourseData].self,
            key: cacheKey,
            maxAge: Self.coursesCacheMaxAge
        )
        if let record {
            _ = LegacyAsyncStorageMigration.bindPendingCourseData(to: record.value)
        }
        return record
    }

    nonisolated func cachedMessages() -> JSONCacheRecord<[SkywardMessage]>? {
        guard let cacheKey = Self.cacheKey(base: Self.messagesCacheKey) else { return nil }
        return JSONCache.record(
            [SkywardMessage].self,
            key: cacheKey,
            maxAge: Self.messagesCacheMaxAge
        )
    }

    // MARK: - Combined course data

    nonisolated func cachedAttendance() -> JSONCacheRecord<AttendanceData>? {
        guard let cacheKey = Self.cacheKey(base: Self.attendanceCacheKey) else { return nil }
        return JSONCache.record(AttendanceData.self, key: cacheKey, maxAge: Self.attendanceCacheMaxAge)
    }

    func loadAttendance(forceRefresh: Bool = false) async throws -> AttendanceData {
        guard let account = CredentialStore.currentAccountIdentifier,
              let cacheKey = Self.cacheKey(base: Self.attendanceCacheKey) else {
            throw SkywardError.missingSession
        }
        if !forceRefresh,
           let saved = JSONCache.load(AttendanceData.self, key: cacheKey, maxAge: Self.attendanceCacheMaxAge) {
            return saved
        }
        if let task = inFlightAttendance { return try await task.value }
        let generation = cacheGeneration
        let task = Task<AttendanceData, Error> {
            try await Self.withSessionRetry { codes, baseUrl in
                try Task.checkCancellation()
                guard CredentialStore.currentAccountIdentifier == account else { throw CancellationError() }
                return try await SkywardAttendanceAPI.fetch(baseUrl: baseUrl, sessionCodes: codes)
            }
        }
        inFlightAttendance = task
        defer { if generation == cacheGeneration { inFlightAttendance = nil } }
        let attendance = try await task.value
        try Task.checkCancellation()
        guard generation == cacheGeneration, CredentialStore.currentAccountIdentifier == account else {
            throw CancellationError()
        }
        JSONCache.save(attendance, key: cacheKey)
        return attendance
    }

    nonisolated func cachedFees() -> JSONCacheRecord<FeesData>? {
        guard let cacheKey = Self.cacheKey(base: Self.feesCacheKey) else { return nil }
        return JSONCache.record(FeesData.self, key: cacheKey, maxAge: Self.feesCacheMaxAge)
    }

    func loadFees(forceRefresh: Bool = false) async throws -> FeesData {
        guard let account = CredentialStore.currentAccountIdentifier,
              let cacheKey = AccountCacheNamespace.key(base: Self.feesCacheKey, accountIdentifier: account) else {
            throw SkywardError.missingSession
        }
        if !forceRefresh,
           let saved = JSONCache.load(FeesData.self, key: cacheKey, maxAge: Self.feesCacheMaxAge) {
            return saved
        }
        let generation = cacheGeneration
        if let task = inFlightFees {
            let result = try await task.value
            try Task.checkCancellation()
            guard generation == cacheGeneration, CredentialStore.currentAccountIdentifier == account else {
                throw CancellationError()
            }
            return result
        }
        let task = Task<FeesData, Error> {
            try await Self.withSessionRetry { codes, baseUrl in
                try Task.checkCancellation()
                guard CredentialStore.currentAccountIdentifier == account else { throw CancellationError() }
                return try await SkywardFeesAPI.fetch(baseUrl: baseUrl, sessionCodes: codes)
            }
        }
        inFlightFees = task
        defer { if generation == cacheGeneration { inFlightFees = nil } }
        let result = try await task.value
        try Task.checkCancellation()
        guard generation == cacheGeneration, CredentialStore.currentAccountIdentifier == account else {
            throw CancellationError()
        }
        JSONCache.save(result, key: cacheKey)
        return result
    }

    nonisolated func cachedStudentInfo() -> JSONCacheRecord<StudentInfoData>? {
        guard let cacheKey = Self.cacheKey(base: Self.studentInfoCacheKey) else { return nil }
        return JSONCache.record(StudentInfoData.self, key: cacheKey, maxAge: Self.studentInfoCacheMaxAge)
    }

    func loadStudentInfo(forceRefresh: Bool = false) async throws -> StudentInfoData {
        guard let account = CredentialStore.currentAccountIdentifier,
              let cacheKey = AccountCacheNamespace.key(base: Self.studentInfoCacheKey, accountIdentifier: account) else {
            throw SkywardError.missingSession
        }
        if !forceRefresh,
           let saved = JSONCache.load(StudentInfoData.self, key: cacheKey, maxAge: Self.studentInfoCacheMaxAge) {
            return saved
        }
        let generation = cacheGeneration
        if let task = inFlightStudentInfo {
            let result = try await task.value
            try Task.checkCancellation()
            guard generation == cacheGeneration, CredentialStore.currentAccountIdentifier == account else {
                throw CancellationError()
            }
            return result
        }
        let task = Task<StudentInfoData, Error> {
            try await Self.withSessionRetry { codes, baseUrl in
                try Task.checkCancellation()
                guard CredentialStore.currentAccountIdentifier == account else { throw CancellationError() }
                return try await SkywardStudentInfoAPI.fetch(baseUrl: baseUrl, sessionCodes: codes)
            }
        }
        inFlightStudentInfo = task
        defer { if generation == cacheGeneration { inFlightStudentInfo = nil } }
        let result = try await task.value
        try Task.checkCancellation()
        guard generation == cacheGeneration, CredentialStore.currentAccountIdentifier == account else {
            throw CancellationError()
        }
        JSONCache.save(result, key: cacheKey)
        return result
    }

    nonisolated func cachedDocuments() -> JSONCacheRecord<DocumentsData>? {
        guard let cacheKey = Self.cacheKey(base: Self.documentsCacheKey) else { return nil }
        return JSONCache.record(DocumentsData.self, key: cacheKey, maxAge: Self.documentsCacheMaxAge)
    }

    func loadDocuments(forceRefresh: Bool = false) async throws -> DocumentsData {
        guard let account = CredentialStore.currentAccountIdentifier,
              let cacheKey = AccountCacheNamespace.key(base: Self.documentsCacheKey, accountIdentifier: account) else {
            throw SkywardError.missingSession
        }
        if !forceRefresh,
           let saved = JSONCache.load(DocumentsData.self, key: cacheKey, maxAge: Self.documentsCacheMaxAge) {
            return saved
        }
        let generation = cacheGeneration
        if let task = inFlightDocuments {
            let result = try await task.value
            try Task.checkCancellation()
            guard generation == cacheGeneration, CredentialStore.currentAccountIdentifier == account else {
                throw CancellationError()
            }
            return result
        }
        let task = Task<DocumentsData, Error> {
            try await Self.withSessionRetry { codes, baseUrl in
                try Task.checkCancellation()
                guard CredentialStore.currentAccountIdentifier == account else { throw CancellationError() }
                return try await SkywardDocumentsAPI.fetch(baseUrl: baseUrl, sessionCodes: codes)
            }
        }
        inFlightDocuments = task
        defer { if generation == cacheGeneration { inFlightDocuments = nil } }
        let result = try await task.value
        try Task.checkCancellation()
        guard generation == cacheGeneration, CredentialStore.currentAccountIdentifier == account else {
            throw CancellationError()
        }
        JSONCache.save(result, key: cacheKey)
        return result
    }

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
        JSONCache.save(courses, key: cacheKey)
        _ = LegacyAsyncStorageMigration.bindPendingCourseData(to: courses)
        return courses
    }

    // MARK: - Per-class grade info

    func gradeInfo(params: GradeInfoParams, forceRefresh: Bool = false) async throws -> GradeInfoResult {
        #if DEBUG
        if let sample = SampleData.gradeInfo(for: params) { return sample }
        #endif
        let cacheBase = [
            "gradeInfo", params.stuId, params.corNumId, params.gbId, params.section, params.bucket,
        ].joined(separator: "_")
        guard let cacheKey = Self.cacheKey(base: cacheBase) else {
            throw SkywardError.missingSession
        }
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
        guard let cacheKey = Self.cacheKey(base: Self.messagesCacheKey) else {
            throw SkywardError.missingSession
        }
        let generation = cacheGeneration
        let messages = try await Self.withSessionRetry { codes, baseUrl in
            let messages = try await SkywardMessagesAPI.fetchMessages(sessionCodes: codes, baseUrl: baseUrl)
            return messages  // already in feed order (newest first)
        }
        guard generation == cacheGeneration, !Task.isCancelled else {
            throw CancellationError()
        }
        JSONCache.save(messages, key: cacheKey)
        return messages
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
        JSONCache.clear(prefix: Self.messagesCacheKey)
        JSONCache.clear(prefix: "gradeInfo_")
    }

    // MARK: - Helpers

    private nonisolated static func cacheKey(base: String) -> String? {
        AccountCacheNamespace.key(
            base: base,
            accountIdentifier: CredentialStore.currentAccountIdentifier
        )
    }

    /// Runs `operation` with a valid session, re-authenticating once on expiry.
    private static func withSessionRetry<T>(
        _ operation: (SkywardSessionCodes, String) async throws -> T
    ) async throws -> T {
        let (codes, baseUrl) = try await AuthService.currentSession()
        do {
            return try await operation(codes, baseUrl)
        } catch SkywardError.sessionExpired {
            if let accountIdentifier = CredentialStore.currentAccountIdentifier {
                try? SessionStore.clear(accountIdentifier: accountIdentifier)
            } else {
                SessionStore.invalidateUnboundLegacySessions()
            }
            let freshCodes = try await AuthService.authenticate()
            return try await operation(freshCodes, baseUrl)
        }
    }

    /// Flattens academic history years into the unified course list.
    static func transform(history: AcademicHistory) -> [UnifiedCourseData] {
        UnifiedCourseTransformer.transform(history: history)
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

import Foundation

/// Authentication: login with stored credentials and keep session codes fresh.
enum AuthService {
    static func authenticate() async throws -> SkywardSessionCodes {
        guard let credentials = CredentialStore.load() else {
            throw SkywardError.missingSession
        }
        return try await AuthenticationCoordinator.shared.authenticate(
            credentials: credentials,
            persistSession: true
        )
    }

    /// Validates replacement credentials without changing the saved account.
    static func verify(credentials: SkywardCredentials) async throws -> SkywardSessionCodes {
        try await AuthenticationCoordinator.shared.authenticate(
            credentials: credentials,
            persistSession: false
        )
    }

    /// Returns a valid session, logging in if needed.
    static func currentSession() async throws -> (codes: SkywardSessionCodes, baseUrl: String) {
        if let accountIdentifier = CredentialStore.currentAccountIdentifier,
           let codes = SessionStore.load(accountIdentifier: accountIdentifier) {
            return (codes, CredentialStore.baseURL)
        }
        let codes = try await authenticate()
        return (codes, CredentialStore.baseURL)
    }

    static func logout() async {
        await AuthenticationCoordinator.shared.cancel()
        try? SessionStore.clear()
    }

    static func cancelAuthentication() async {
        await AuthenticationCoordinator.shared.cancel()
    }
}

/// Coalesces simultaneous first-load and session-refresh login requests.
private actor AuthenticationCoordinator {
    static let shared = AuthenticationCoordinator()
    private var inFlight: Task<SkywardSessionCodes, Error>?
    private var inFlightCredentials: SkywardCredentials?
    private var generation = 0

    func authenticate(
        credentials: SkywardCredentials,
        persistSession: Bool
    ) async throws -> SkywardSessionCodes {
        let requestGeneration = generation
        if let inFlight, inFlightCredentials == credentials {
            let codes = try await inFlight.value
            return try finish(
                codes: codes, credentials: credentials,
                persistSession: persistSession, requestGeneration: requestGeneration
            )
        }
        if let inFlight {
            _ = try? await inFlight.value
            guard generation == requestGeneration, !Task.isCancelled else {
                throw CancellationError()
            }
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
            return try finish(
                codes: codes, credentials: credentials,
                persistSession: persistSession, requestGeneration: requestGeneration
            )
        } catch {
            if inFlightCredentials == credentials {
                inFlight = nil
                inFlightCredentials = nil
            }
            throw error
        }
    }

    func cancel() {
        generation &+= 1
        inFlight?.cancel()
        inFlight = nil
        inFlightCredentials = nil
    }

    private func finish(
        codes: SkywardSessionCodes,
        credentials: SkywardCredentials,
        persistSession: Bool,
        requestGeneration: Int
    ) throws -> SkywardSessionCodes {
        guard AuthenticationRequestPolicy.permitsCompletion(
            isCancelled: Task.isCancelled,
            requestGeneration: requestGeneration,
            currentGeneration: generation
        ) else {
            throw CancellationError()
        }
        if persistSession {
            guard SessionPersistencePolicy.permitsSave(
                requestedCredentials: credentials,
                currentCredentials: CredentialStore.load(),
                isCancelled: false,
                requestGeneration: requestGeneration,
                currentGeneration: generation
            ) else {
                throw CancellationError()
            }
            try SessionStore.save(
                codes,
                accountIdentifier: CredentialStore.accountIdentifier(for: credentials.username)
            )
        }
        return codes
    }
}

/// Unified data fetching with caching and automatic re-auth, mirroring the
/// RN DataService + UnifiedGPAManager pipeline.
actor DataService {
    static let shared = DataService()

    private static let coursesCacheKey = "unifiedCourseData"
    private static let messagesCacheKey = "skywardMessages"
    private static let coursesCacheMaxAge: TimeInterval = 30 * 60      // 30 min
    private static let messagesCacheMaxAge: TimeInterval = 30 * 60     // 30 min
    private static let gradeInfoCacheMaxAge: TimeInterval = 5 * 60     // 5 min

    private var inFlightCourses: Task<[UnifiedCourseData], Error>?
    private var inFlightGradeInfo: [String: Task<GradeInfoResult, Error>] = [:]
    private var cacheGeneration = 0

    func cancelAuthentication() async {
        await AuthService.cancelAuthentication()
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

    func combinedCourses(forceRefresh: Bool = false) async throws -> [UnifiedCourseData] {
        guard let cacheKey = Self.cacheKey(base: Self.coursesCacheKey) else {
            throw SkywardError.missingSession
        }
        if !forceRefresh,
           let cached = JSONCache.load([UnifiedCourseData].self, key: cacheKey, maxAge: Self.coursesCacheMaxAge) {
            _ = LegacyAsyncStorageMigration.bindPendingCourseData(to: cached)
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

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
actor AuthenticationCoordinator {
    static let shared = AuthenticationCoordinator()
    private var inFlight: Task<SkywardSessionCodes, Error>?
    private var inFlightCredentials: SkywardCredentials?
    private var generation = 0
    private var inFlightID: UUID?
    private var latestAuthenticationID: UUID?
    private let loadCredentials: @Sendable () -> SkywardCredentials?
    private let loadSession: @Sendable (String) -> SkywardSessionCodes?
    private let clearSession: @Sendable (String) throws -> Void
    private let saveSession: @Sendable (SkywardSessionCodes, String) throws -> Void
    private let login: @Sendable (SkywardCredentials) async throws -> SkywardSessionCodes

    init(
        loadCredentials: @escaping @Sendable () -> SkywardCredentials? = { CredentialStore.load() },
        loadSession: @escaping @Sendable (String) -> SkywardSessionCodes? = { SessionStore.load(accountIdentifier: $0) },
        clearSession: @escaping @Sendable (String) throws -> Void = { try SessionStore.clear(accountIdentifier: $0) },
        saveSession: @escaping @Sendable (SkywardSessionCodes, String) throws -> Void = { try SessionStore.save($0, accountIdentifier: $1) },
        login: @escaping @Sendable (SkywardCredentials) async throws -> SkywardSessionCodes = { try await SkywardAuthAPI.authenticate(credentials: $0) }
    ) {
        self.loadCredentials = loadCredentials
        self.loadSession = loadSession
        self.clearSession = clearSession
        self.saveSession = saveSession
        self.login = login
    }

    /// Compare and invalidate on the same actor that saves refreshed sessions.
    /// A late failure from old tokens must reuse a newer session, not erase it.
    func recoverSession(rejecting rejected: SkywardSessionCodes, accountIdentifier: String) async throws -> SkywardSessionCodes {
        try Task.checkCancellation()
        guard let credentials = loadCredentials(),
              CredentialStore.accountIdentifier(for: credentials.username) == accountIdentifier else {
            throw CancellationError()
        }
        if let current = loadSession(accountIdentifier) {
            if current != rejected { return current }
            try clearSession(accountIdentifier)
        }
        return try await authenticate(credentials: credentials, persistSession: true)
    }

    /// Retry only an explicit expiry, once. Valid empty payloads pass through;
    /// maintenance/schema errors preserve the caller's last-known-good cache.
    func withSessionRetry<T: Sendable>(
        _ operation: @Sendable (SkywardSessionCodes, String) async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        guard let credentials = loadCredentials() else { throw SkywardError.missingSession }
        let account = CredentialStore.accountIdentifier(for: credentials.username)
        let requestGeneration = generation
        let codes: SkywardSessionCodes
        if let saved = loadSession(account) { codes = saved }
        else { codes = try await authenticate(credentials: credentials, persistSession: true) }
        try validateRequest(credentials: credentials, generation: requestGeneration)
        let result: T
        do {
            result = try await operation(codes, credentials.baseURL)
        } catch SkywardError.sessionExpired {
            try validateRequest(credentials: credentials, generation: requestGeneration)
            let refreshed = try await recoverSession(rejecting: codes, accountIdentifier: account)
            try validateRequest(credentials: credentials, generation: requestGeneration)
            result = try await operation(refreshed, credentials.baseURL)
        }
        try validateRequest(credentials: credentials, generation: requestGeneration)
        return result
    }

    private func validateRequest(credentials: SkywardCredentials, generation requestGeneration: Int) throws {
        try Task.checkCancellation()
        guard requestGeneration == generation, loadCredentials() == credentials else {
            throw CancellationError()
        }
    }

    func authenticate(
        credentials: SkywardCredentials,
        persistSession: Bool
    ) async throws -> SkywardSessionCodes {
        try Task.checkCancellation()
        let requestGeneration = generation
        while let active = inFlight {
            let activeID = inFlightID
            if inFlightCredentials == credentials, let activeID {
                let codes = try await active.value
                return try finish(
                    codes: codes, credentials: credentials,
                    persistSession: persistSession, requestGeneration: requestGeneration,
                    authenticationID: activeID
                )
            }
            _ = try? await active.value
            guard generation == requestGeneration, !Task.isCancelled else {
                throw CancellationError()
            }
            if inFlightID == activeID {
                inFlight = nil
                inFlightID = nil
                inFlightCredentials = nil
            }
            // Another credential verification may have acquired the slot while
            // this caller waited. Recheck before starting a competing login.
        }
        let requestID = UUID()
        let login = self.login
        let task = Task<SkywardSessionCodes, Error> {
            try await login(credentials)
        }
        inFlightID = requestID
        latestAuthenticationID = requestID
        inFlight = task
        inFlightCredentials = credentials
        do {
            let codes = try await task.value
            if inFlightID == requestID {
                inFlight = nil
                inFlightID = nil
                inFlightCredentials = nil
            }
            return try finish(
                codes: codes, credentials: credentials,
                persistSession: persistSession, requestGeneration: requestGeneration,
                authenticationID: requestID
            )
        } catch {
            if inFlightID == requestID {
                inFlight = nil
                inFlightID = nil
                inFlightCredentials = nil
            }
            throw error
        }
    }

    func cancel() {
        generation &+= 1
        inFlight?.cancel()
        latestAuthenticationID = nil
        inFlight = nil
        inFlightID = nil
        inFlightCredentials = nil
    }

    private func finish(
        codes: SkywardSessionCodes,
        credentials: SkywardCredentials,
        persistSession: Bool,
        requestGeneration: Int,
        authenticationID: UUID
    ) throws -> SkywardSessionCodes {
        guard AuthenticationRequestPolicy.permitsCompletion(
            isCancelled: Task.isCancelled,
            requestGeneration: requestGeneration,
            currentGeneration: generation
        ), latestAuthenticationID == authenticationID else {
            throw CancellationError()
        }
        if persistSession {
            guard SessionPersistencePolicy.permitsSave(
                requestedCredentials: credentials,
                currentCredentials: loadCredentials(),
                isCancelled: false,
                requestGeneration: requestGeneration,
                currentGeneration: generation
            ) else {
                throw CancellationError()
            }
            try saveSession(codes, CredentialStore.accountIdentifier(for: credentials.username))
        }
        return codes
    }
}


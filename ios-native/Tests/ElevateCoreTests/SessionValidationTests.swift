import Foundation
import Testing
@testable import ElevateCore

@Suite("Session recovery")
struct SessionRecoveryTests {
    @Test("A late expiry reuses newer saved codes without another login or invalidation")
    func lateExpiryReusesNewSession() async throws {
        let memory = SessionMemory()
        let login = ControlledLogin()
        let coordinator = memory.coordinator(login: login)
        let first = Task { try await coordinator.recoverSession(rejecting: Self.oldCodes, accountIdentifier: memory.account) }
        await login.waitForCalls(1)
        await login.complete(0, with: Self.newCodes)
        #expect(try await first.value == Self.newCodes)
        #expect(try await coordinator.recoverSession(rejecting: Self.oldCodes, accountIdentifier: memory.account) == Self.newCodes)
        #expect(await login.callCount == 1)
        #expect(memory.clearCount == 1)
        #expect(memory.savedCodes == Self.newCodes)
    }

    @Test("Concurrent expired requests share replacement authentication")
    func concurrentExpiry() async throws {
        let memory = SessionMemory()
        let login = ControlledLogin()
        let coordinator = memory.coordinator(login: login)
        let first = Task { try await coordinator.recoverSession(rejecting: Self.oldCodes, accountIdentifier: memory.account) }
        await login.waitForCalls(1)
        let second = Task { try await coordinator.recoverSession(rejecting: Self.oldCodes, accountIdentifier: memory.account) }
        await login.complete(0, with: Self.newCodes)
        #expect(try await first.value == Self.newCodes)
        #expect(try await second.value == Self.newCodes)
        #expect(await login.callCount == 1)
        #expect(memory.savedCodes == Self.newCodes)
    }

    @Test("An account change rejects the old request before clearing the new session")
    func rejectsChangedAccount() async {
        let memory = SessionMemory()
        let login = ControlledLogin()
        let coordinator = memory.coordinator(login: login)
        memory.replaceCredentials(username: "different-synthetic-account")
        do {
            _ = try await coordinator.recoverSession(rejecting: Self.oldCodes, accountIdentifier: memory.account)
            Issue.record("Expected account cancellation")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(memory.clearCount == 0)
        #expect(await login.callCount == 0)
    }

    @Test("Account changes during login prevent saving or returning its session")
    func rejectsChangedAccountDuringLogin() async {
        let memory = SessionMemory()
        let login = ControlledLogin()
        let coordinator = memory.coordinator(login: login)
        let request = Task { try await coordinator.recoverSession(rejecting: Self.oldCodes, accountIdentifier: memory.account) }
        await login.waitForCalls(1)
        memory.replaceCredentials(username: "different-synthetic-account")
        await login.complete(0, with: Self.newCodes)
        do {
            _ = try await request.value
            Issue.record("Expected account cancellation")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(memory.savedCodes == nil)
    }

    @Test("Cancelled authentication cannot clear a replacement request for the same credentials")
    func cancelledAuthenticationCannotOwnReplacement() async throws {
        let memory = SessionMemory()
        let login = ControlledLogin()
        let coordinator = memory.coordinator(login: login)
        let first = Task { try await coordinator.recoverSession(rejecting: Self.oldCodes, accountIdentifier: memory.account) }
        await login.waitForCalls(1)
        await coordinator.cancel()
        let replacement = Task { try await coordinator.recoverSession(rejecting: Self.oldCodes, accountIdentifier: memory.account) }
        await login.waitForCalls(2)
        // Simulate a transport completing despite cancellation.
        await login.complete(0, with: Self.oldCodes)
        do {
            _ = try await first.value
            Issue.record("Expected cancelled generation")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(memory.savedCodes == nil)
        await login.complete(1, with: Self.newCodes)
        #expect(try await replacement.value == Self.newCodes)
        #expect(memory.savedCodes == Self.newCodes)
        #expect(await login.callCount == 2)
    }

    @Test("An expired endpoint retries once with new codes and returns its real data")
    func retriesExpiredRequest() async throws {
        let memory = SessionMemory()
        let login = ControlledLogin()
        let coordinator = memory.coordinator(login: login)
        let calls = RequestCalls()
        let request = Task {
            try await coordinator.withSessionRetry { codes, _ in
                await calls.record()
                if codes == Self.oldCodes { throw SkywardError.sessionExpired }
                return ["synthetic-course"]
            }
        }
        await login.waitForCalls(1)
        await login.complete(0, with: Self.newCodes)
        #expect(try await request.value == ["synthetic-course"])
        #expect(await calls.count == 2)
        #expect(await login.callCount == 1)
    }

    @Test("A second expiry propagates instead of looping or returning an empty result")
    func retryStopsAfterOneAuthentication() async {
        let memory = SessionMemory()
        let login = ControlledLogin()
        let coordinator = memory.coordinator(login: login)
        let calls = RequestCalls()
        let request = Task {
            try await coordinator.withSessionRetry { _, _ -> [String] in
                await calls.record()
                throw SkywardError.sessionExpired
            }
        }
        await login.waitForCalls(1)
        await login.complete(0, with: Self.newCodes)
        do {
            _ = try await request.value
            Issue.record("Expected second expiry")
        } catch SkywardError.sessionExpired {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(await calls.count == 2)
        #expect(await login.callCount == 1)
    }

    @Test("Schema/maintenance errors do not trigger login; a verified empty result stays empty")
    func nonAuthenticationResults() async throws {
        let memory = SessionMemory()
        let login = ControlledLogin()
        let coordinator = memory.coordinator(login: login)
        do {
            let _: [String] = try await coordinator.withSessionRetry { _, _ in
                throw SkywardError.invalidResponse("maintenance response")
            }
            Issue.record("Expected response failure")
        } catch SkywardError.invalidResponse {} catch { Issue.record("Unexpected error: \(error)") }
        let empty: [String] = try await coordinator.withSessionRetry { _, _ in [] }
        #expect(empty.isEmpty)
        #expect(await login.callCount == 0)
        #expect(memory.clearCount == 0)
    }

    @Test("Responses from a disconnected or changed account cannot reach the cache", arguments: [false, true])
    func staleRequestCannotComplete(cancelSession: Bool) async {
        let memory = SessionMemory()
        let login = ControlledLogin()
        let response = ControlledLogin()
        let coordinator = memory.coordinator(login: login)
        let request = Task {
            try await coordinator.withSessionRetry { _, _ in
                _ = await response.start()
                return ["old-account-course"]
            }
        }
        await response.waitForCalls(1)
        if cancelSession { await coordinator.cancel() }
        else { memory.replaceCredentials(username: "different-synthetic-account") }
        await response.complete(0, with: Self.newCodes)
        do {
            _ = try await request.value
            Issue.record("Expected stale response cancellation")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(await login.callCount == 0)
    }

    fileprivate static let oldCodes = SkywardSessionCodes(dwd: "old", wfaacl: "old", encses: "old", userType: "2", sessionid: "old")
    fileprivate static let newCodes = SkywardSessionCodes(dwd: "new", wfaacl: "new", encses: "new", userType: "2", sessionid: "new")
}

/// Synthetic memory only. Tests never load account credentials or Keychain sessions.
private final class SessionMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var credentials = SkywardCredentials(username: "synthetic-account", password: "synthetic-password", baseURL: "https://school.invalid/")
    private var codes: SkywardSessionCodes? = SessionRecoveryTests.oldCodes
    private var clears = 0
    let account = CredentialStore.accountIdentifier(for: "synthetic-account")
    var clearCount: Int { lock.withLock { clears } }
    var savedCodes: SkywardSessionCodes? { lock.withLock { codes } }

    func replaceCredentials(username: String) { lock.withLock { credentials.username = username } }

    func coordinator(login: ControlledLogin) -> AuthenticationCoordinator {
        AuthenticationCoordinator(
            loadCredentials: { self.lock.withLock { self.credentials } },
            loadSession: { _ in self.lock.withLock { self.codes } },
            clearSession: { _ in self.lock.withLock { self.codes = nil; self.clears += 1 } },
            saveSession: { codes, _ in self.lock.withLock { self.codes = codes } },
            login: { _ in await login.start() }
        )
    }
}

private actor ControlledLogin {
    private(set) var callCount = 0
    private var pending: [Int: CheckedContinuation<SkywardSessionCodes, Never>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func start() async -> SkywardSessionCodes {
        let index = callCount
        callCount += 1
        return await withCheckedContinuation { continuation in
            pending[index] = continuation
            let ready = waiters.filter { $0.0 <= callCount }
            waiters.removeAll { $0.0 <= callCount }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func waitForCalls(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func complete(_ index: Int, with codes: SkywardSessionCodes) {
        pending.removeValue(forKey: index)?.resume(returning: codes)
    }
}

private actor RequestCalls {
    private(set) var count = 0
    func record() { count += 1 }
}

@Suite("Session response validation")
struct SessionResponseValidationTests {
    private let emptyGradebook = "<script>$.extend((sff.getValue('sf_gridObjects') || {}), {stuGradesGrid_1_2:{tb:{r:[]}}}));</script>"

    @Test("Expired responses take precedence over a complete empty course grid")
    func expiryCannotBecomeEmptyCourses() {
        for marker in ["Your session has expired", "Your session has timed out", "Session has ended",
                       "<div>Family Access</div><form id='detailform'><input name='password'></form>"] {
            do {
                _ = try SkywardHistoryAPI.parseGradebookHTML(emptyGradebook + marker)
                Issue.record("Expected explicit session expiry")
            } catch SkywardError.sessionExpired {} catch { Issue.record("Unexpected error: \(error)") }
        }
    }

    @Test("Valid empty course grids are retained without being mistaken for expiry")
    func validEmptyCourseGrid() throws {
        #expect(try SkywardHistoryAPI.parseGradebookHTML(emptyGradebook).isEmpty)
    }

    @Test("A Family Access title alone is not evidence of an expired session")
    func maintenanceIsNotAuthenticationFailure() {
        do {
            _ = try SkywardHistoryAPI.parseGradebookHTML("<title>Family Access</title><body>Maintenance in progress</body>")
            Issue.record("Expected incompatible response")
        } catch SkywardError.invalidResponse {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test("A generic WebSpeed failure does not establish session expiry")
    func webSpeedServerFailure() throws {
        try SkywardHTTP.checkSessionExpired("<title>WebSpeed Error</title><body>Service unavailable for maintenance</body>")
        do {
            _ = try SkywardHistoryAPI.parseGradebookHTML("<title>WebSpeed Error</title><body>Service unavailable for maintenance</body>")
            Issue.record("Expected response validation failure")
        } catch SkywardError.invalidResponse {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test("An expiry outside the loader output cannot be lost during extraction")
    func loaderEnvelopeExpiry() {
        let fragment = "<div>Incomplete grade info</div>"
        do {
            _ = try SkywardGradesAPI.parseGradeInfoHTML(fragment, rawResponse: "<status>Your session has expired</status><output><![CDATA[\(fragment)]]></output>")
            Issue.record("Expected explicit session expiry")
        } catch SkywardError.sessionExpired {} catch { Issue.record("Unexpected error: \(error)") }
    }
}

@Suite("Typed Skyward loader status")
struct LoaderStatusTests {
    private func envelope(_ script: String, output: String = "") -> String {
        "<response><sff><![CDATA[<script type='text/javascript'>\(script)</script>]]></sff><output><![CDATA[\(output)]]></output></response>"
    }

    @Test("Only an explicit loader options logout status expires the session")
    func explicitLogout() {
        for script in [
            "sff.httpCalls['123'].options = {status:'logout'};",
            "sff.httpCalls['123'] = {'messages': [], 'options': {status:'logout'}};",
            "sff . httpCalls [ 123 ] . options = { status: \"logout\", message: 'Session replaced' }",
            "/* metadata */ sff.httpCalls[\"123\"].messages=[]; sff.httpCalls[\"123\"].options={ 'status': 'logout' };",
            #"sff.httpCalls['123'].options={status:'\x6cogout'};"#,
        ] {
            do {
                try SkywardHTTP.checkSessionExpired(envelope(script))
                Issue.record("Expected typed logout expiry")
            } catch SkywardError.sessionExpired {} catch { Issue.record("Unexpected error: \(error)") }
        }
    }


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


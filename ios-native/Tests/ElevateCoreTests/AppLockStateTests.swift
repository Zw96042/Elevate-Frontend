import Testing
@testable import ElevateCore

@Suite("App Lock lifecycle")
struct AppLockStateTests {
    @Test("Existing installs stay open until the user enables the lock")
    func defaultOff() {
        var state = AppLockState(isEnabled: false)
        for activity in [AppLockState.Activity.inactive, .background, .active] {
            state.move(to: activity)
            #expect(!state.isContentCovered)
            #expect(!state.needsAutomaticUnlock)
        }
    }

    @Test("An enabled cold launch is covered before activation or authentication")
    func coldLaunch() {
        var state = AppLockState(isEnabled: true)
        #expect(state.isLocked && state.isContentCovered)
        let inactiveAttempt = state.begin(.unlock)
        #expect(inactiveAttempt == nil)
        state.move(to: .active)
        #expect(state.needsAutomaticUnlock)
        #expect(state.isContentCovered)
    }

    @Test("Enabling requires a successful current device-owner proof")
    func enableProof() throws {
        var state = AppLockState(isEnabled: false)
        state.move(to: .active)
        let firstAttempt = state.begin(.enable)
        let failed = try #require(firstAttempt)
        #expect(!state.isEnabled)
        state.finish(failed, succeeded: false)
        #expect(!state.isEnabled)
        let retry = state.begin(.enable)
        let accepted = try #require(retry)
        state.finish(accepted, succeeded: true)
        #expect(state.isEnabled && !state.isLocked && !state.isContentCovered)
    }

    @Test("Only one challenge can be in flight")
    func coalescing() throws {
        var state = AppLockState(isEnabled: true)
        state.move(to: .active)
        let firstAttempt = state.begin(.unlock)
        _ = try #require(firstAttempt)
        let duplicateUnlock = state.begin(.unlock)
        #expect(duplicateUnlock == nil)
        let duplicateEnable = state.begin(.enable)
        #expect(duplicateEnable == nil)
        #expect(!state.needsAutomaticUnlock)
    }

    @Test("The system authentication dialog can deactivate the app without restarting the challenge")
    func authenticationDialog() throws {
        var state = AppLockState(isEnabled: true)
        state.move(to: .active)
        let attempt = state.begin(.unlock)
        let challenge = try #require(attempt)
        state.move(to: .inactive)
        #expect(state.isContentCovered)
        #expect(state.challenge == challenge)
        let accepted = state.finish(challenge, succeeded: true)
        #expect(accepted)
        #expect(!state.isLocked && state.isContentCovered)
        state.move(to: .active)
        #expect(!state.isContentCovered)
        #expect(!state.needsAutomaticUnlock)
    }

    @Test("Cancellation remains locked and permits explicit retry without a prompt loop")
    func cancelledAuthentication() throws {
        var state = AppLockState(isEnabled: true)
        state.move(to: .active)
        let attempt = state.begin(.unlock)
        let challenge = try #require(attempt)
        state.move(to: .inactive)
        state.finish(challenge, succeeded: false)
        state.move(to: .active)
        #expect(state.isLocked && state.isContentCovered)
        #expect(!state.needsAutomaticUnlock)
        let retry = state.begin(.unlock)
        #expect(retry != nil)
    }

    @Test("Unlocked content is covered while inactive and relocks after background")
    func privacyCover() throws {
        var state = AppLockState(isEnabled: true)
        state.move(to: .active)
        let attempt = state.begin(.unlock)
        let challenge = try #require(attempt)
        state.finish(challenge, succeeded: true)
        state.move(to: .inactive)
        #expect(!state.isLocked && state.isContentCovered)
        state.move(to: .active)
        #expect(!state.isContentCovered)
        state.move(to: .background)
        #expect(state.isLocked && state.isContentCovered)
        state.move(to: .active)
        #expect(state.needsAutomaticUnlock)
    }

    @Test("A late successful callback cannot unlock after background")
    func staleUnlock() throws {
        var state = AppLockState(isEnabled: true)
        state.move(to: .active)
        let oldAttempt = state.begin(.unlock)
        let old = try #require(oldAttempt)
        state.move(to: .background)
        state.move(to: .active)
        let currentAttempt = state.begin(.unlock)
        let current = try #require(currentAttempt)
        let acceptedOld = state.finish(old, succeeded: true)
        #expect(!acceptedOld)
        #expect(state.isLocked && state.challenge == current)
        let acceptedCurrent = state.finish(current, succeeded: true)
        #expect(acceptedCurrent)
        #expect(!state.isLocked)
    }

    @Test("A late enable proof after background cannot change the saved preference")
    func staleEnable() throws {
        var state = AppLockState(isEnabled: false)
        state.move(to: .active)
        let attempt = state.begin(.enable)
        let old = try #require(attempt)
        state.move(to: .background)
        let accepted = state.finish(old, succeeded: true)
        #expect(!accepted)
        #expect(!state.isEnabled)
    }

    @Test("Disabling cannot bypass a locked or inactive app")
    func guardedDisable() throws {
        var state = AppLockState(isEnabled: true)
        let disabledBeforeActivation = state.disable()
        #expect(!disabledBeforeActivation)
        state.move(to: .active)
        let disabledWhileLocked = state.disable()
        #expect(!disabledWhileLocked)
        let attempt = state.begin(.unlock)
        let challenge = try #require(attempt)
        state.finish(challenge, succeeded: true)
        state.move(to: .inactive)
        let disabledWhileInactive = state.disable()
        #expect(!disabledWhileInactive)
        state.move(to: .active)
        let disabledWhileUnlocked = state.disable()
        #expect(disabledWhileUnlocked)
        state.move(to: .background)
        #expect(!state.isEnabled && !state.isContentCovered)
    }

    @Test("Cancelling the enable preference rejects a late proof")
    func preferenceChange() throws {
        var state = AppLockState(isEnabled: false)
        state.move(to: .active)
        let attempt = state.begin(.enable)
        let old = try #require(attempt)
        let disabled = state.disable()
        #expect(disabled)
        let accepted = state.finish(old, succeeded: true)
        #expect(!accepted)
        #expect(!state.isEnabled)
    }
}

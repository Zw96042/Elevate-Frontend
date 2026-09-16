import Foundation
import LocalAuthentication
import Observation
import SwiftUI

@MainActor protocol AppLockCoverUpdating: AnyObject {
    func synchronize()
}

/// An optional device-local screen lock. Widgets, notification previews and
/// background refresh keep their own existing privacy and authorization rules.
@Observable @MainActor
final class AppLockStore {
    static let shared = AppLockStore()
    private static let enabledKey = "elevate.appLock.enabled.v1"

    private var state: AppLockState
    private(set) var error: String?
    private(set) var authenticationName = "Device passcode"
    private(set) var authenticationSymbol = "lock.fill"
    private(set) var isAvailable = false
    @ObservationIgnored private var context: LAContext?
    @ObservationIgnored private let defaults: UserDefaults
    #if DEBUG
    @ObservationIgnored private let isPreview: Bool
    #endif
    // UIKit calls this synchronously before the app-switcher snapshot. SwiftUI
    // observation alone may not commit its next render before suspension.
    @ObservationIgnored weak var privacyCover: (any AppLockCoverUpdating)?

    var isEnabled: Bool { state.isEnabled }
    var isLocked: Bool { state.isLocked }
    var isAuthenticating: Bool { state.challenge != nil }
    var isContentCovered: Bool { state.isContentCovered }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var enabled = defaults.bool(forKey: Self.enabledKey)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        isPreview = arguments.contains("-SampleData") && arguments.contains("-AppLockPreview")
        if isPreview { enabled = true }
        #endif
        state = AppLockState(isEnabled: enabled)
        refreshAvailability()
    }

    /// A capability check only; the system prompt follows an explicit enable
    /// choice, or the saved choice to unlock this app on its next foreground.
    func refreshAvailability() {
        let probe = LAContext()
        isAvailable = probe.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch probe.biometryType {
        case .faceID: authenticationName = "Face ID"; authenticationSymbol = "faceid"
        case .touchID: authenticationName = "Touch ID"; authenticationSymbol = "touchid"
        default: authenticationName = "Device passcode"; authenticationSymbol = "lock.fill"
        }
        probe.invalidate()
    }

    @discardableResult
    func enable() async -> Bool { await authenticate(for: .enable) }

    @discardableResult
    func unlock() async -> Bool { await authenticate(for: .unlock) }

    @discardableResult
    func disable() -> Bool {
        guard state.disable() else { return false }
        context?.invalidate()
        context = nil
        persistEnabled(false)
        error = nil
        privacyCover?.synchronize()
        return true
    }

    func clearError() { error = nil }

    func scenePhaseChanged(_ phase: ScenePhase) {
        let activity: AppLockState.Activity
        switch phase {
        case .active: activity = .active
        case .inactive: activity = .inactive
        case .background: activity = .background
        @unknown default: activity = .inactive
        }
        guard activity != state.activity else { return }
        state.move(to: activity)
        if activity == .background {
            context?.invalidate()
            context = nil
            error = nil
        } else if activity == .active {
            refreshAvailability()
        }
        privacyCover?.synchronize()
        if state.needsAutomaticUnlock {
            #if DEBUG
            // Keep synthetic layout checks on the lock screen. The Unlock
            // button still invokes the real system authentication challenge.
            if isPreview, ProcessInfo.processInfo.arguments.contains("-AppLockManualPreview") { return }
            #endif
            Task { await unlock() }
        }
    }

    private func authenticate(for purpose: AppLockState.Purpose) async -> Bool {
        guard !Task.isCancelled, let challenge = state.begin(purpose) else { return false }
        error = nil
        let context = LAContext()
        self.context = context
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Device Passcode"
        defer {
            context.invalidate()
            if self.context === context { self.context = nil }
            privacyCover?.synchronize()
        }

        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            if state.finish(challenge, succeeded: false) {
                error = Self.message(for: availabilityError)
            }
            refreshAvailability()
            return false
        }
        do {
            let succeeded = try await withTaskCancellationHandler {
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: purpose == .enable
                        ? "Protect access to your school information."
                        : "Unlock your school information."
                )
            } onCancel: {
                // The cancellation handler can run on any executor. Keep the
                // context on MainActor and cancel only this still-owned proof.
                Task { @MainActor [weak self] in
                    self?.cancelAuthentication(challenge)
                }
            }
            let accepted = state.finish(challenge, succeeded: succeeded && !Task.isCancelled)
            guard accepted, succeeded, !Task.isCancelled else { return false }
            persistEnabled(true)
            return true
        } catch {
            guard state.finish(challenge, succeeded: false) else { return false }
            self.error = Self.message(for: error)
            return false
        }
    }

    private func cancelAuthentication(_ challenge: AppLockState.Challenge) {
        guard state.finish(challenge, succeeded: false) else { return }
        context?.invalidate()
        context = nil
        privacyCover?.synchronize()
    }

    private func persistEnabled(_ enabled: Bool) {
        #if DEBUG
        // A locked synthetic UI fixture never changes the saved preference,
        // and still uses the real LocalAuthentication path to unlock.
        guard !isPreview else { return }
        #endif
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    private static func message(for error: Error?) -> String? {
        switch (error as? LAError)?.code {
        case .userCancel, .appCancel: return nil
        case .passcodeNotSet:
            return "Set a device passcode in iPhone Settings to use App Lock."
        case .biometryLockout:
            return "Unlock your iPhone with its device passcode, then try again."
        case .systemCancel, .notInteractive:
            return "Unlocking was interrupted. Try again when Elevate is active."
        default:
            return "Couldn't verify it's you. Try again with Face ID, Touch ID, or your device passcode."
        }
    }
}

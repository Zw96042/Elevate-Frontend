import Foundation

/// UI-only device-owner gate. This never authorizes Skyward requests or changes
/// credential access. A background transition invalidates every pending proof.
struct AppLockState {
    enum Activity { case active, inactive, background }
    enum Purpose: Sendable { case enable, unlock }
    struct Challenge: Equatable, Sendable {
        let id: UUID
        let purpose: Purpose
    }

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var activity: Activity = .inactive
    private(set) var challenge: Challenge?
    private var attemptedThisForeground = false

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        isLocked = isEnabled
    }

    var isContentCovered: Bool { isEnabled && (isLocked || activity != .active) }
    var needsAutomaticUnlock: Bool {
        isEnabled && isLocked && activity == .active
            && !attemptedThisForeground && challenge == nil
    }

    mutating func move(to activity: Activity) {
        self.activity = activity
        if activity == .background {
            challenge = nil
            isLocked = isEnabled
            attemptedThisForeground = false
        }
    }

    mutating func begin(_ purpose: Purpose) -> Challenge? {
        guard activity == .active, challenge == nil else { return nil }
        switch purpose {
        case .enable: guard !isEnabled else { return nil }
        case .unlock: guard isEnabled && isLocked else { return nil }
        }
        attemptedThisForeground = true
        let challenge = Challenge(id: UUID(), purpose: purpose)
        self.challenge = challenge
        return challenge
    }

    /// False means the proof belongs to an obsolete attempt, even if the
    /// underlying system callback reported success.
    @discardableResult
    mutating func finish(_ challenge: Challenge, succeeded: Bool) -> Bool {
        guard self.challenge == challenge, activity != .background else { return false }
        self.challenge = nil
        if succeeded {
            isEnabled = true
            isLocked = false
        }
        return true
    }

    /// Disabling is an explicit action available only in an already-open app.
    /// It can also cancel an enable attempt without accepting its late result.
    @discardableResult
    mutating func disable() -> Bool {
        guard !isLocked, activity == .active else { return false }
        challenge = nil
        isEnabled = false
        attemptedThisForeground = false
        return true
    }
}

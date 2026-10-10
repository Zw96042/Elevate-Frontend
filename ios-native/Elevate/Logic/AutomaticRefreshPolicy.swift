import Foundation

/// Use both successful data age and attempted request age. A failed automatic
/// request must not retry on every foreground transition or polling tick.
enum AutomaticRefreshPolicy {
    static let interval: TimeInterval = 5 * 60

    static func isDue(lastUpdated: Date?, lastAttempt: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < interval { return false }
        guard let lastUpdated else { return true }
        return now.timeIntervalSince(lastUpdated) >= interval
    }
}

/// Eligibility is an earliest start, not a guarantee that iOS will launch us.
enum BackgroundRefreshPolicy {
    static let interval: TimeInterval = 15 * 60

    static func shouldSubmit(hasPendingRequest: Bool, pendingDate: Date?, now: Date) -> Bool {
        guard hasPendingRequest else { return true }
        // nil means already eligible, so replacing it would only postpone work.
        guard let pendingDate else { return false }
        return pendingDate > now.addingTimeInterval(interval)
    }
}

/// Assignment widgets have their own coverage and age; a fresh course list
/// does not prove that its separate per-class requests ever succeeded.
enum WidgetAssignmentRefreshPolicy {
    static func isDue(
        term: TermLabel,
        previousTerm: String?,
        coursesUpdatedAt: Date?,
        previousCoursesUpdatedAt: Date?,
        assignmentsUpdatedAt: Date?,
        assignmentsAreComplete: Bool,
        now: Date
    ) -> Bool {
        previousTerm != term.shortName
            || coursesUpdatedAt != previousCoursesUpdatedAt
            || !assignmentsAreComplete
            || AutomaticRefreshPolicy.isDue(lastUpdated: assignmentsUpdatedAt, lastAttempt: nil, now: now)
    }
}

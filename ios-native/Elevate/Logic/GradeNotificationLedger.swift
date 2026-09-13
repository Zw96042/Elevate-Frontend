import Foundation

/// Only successful, complete network observations may advance notification history.
enum GradeObservationSource: Sendable {
    case freshValidated, cached, failed, staleAccount, cancelled, incomplete
}

struct GradeNotificationEvent: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case averageChanged, gradeAvailable }
    let id: String
    let courseID: String
    let term: TermLabel
    let previousScore: Double?
    let currentScore: Double
    let kind: Kind
    let discoveredAt: Date
}

/// An accepted request is not evidence that a person saw its notification.
enum GradeNotificationDelivery: Codable, Equatable, Sendable {
    case pending, retry, accepted(at: Date), consumed
}

/// One instance per account; callers serialize mutation and persist after each change.
/// Independent of the last-viewed course history and of what-if calculations.
struct GradeNotificationLedger: Codable, Sendable {
    private struct Observation: Codable, Sendable {
        var latestScore: Double?
        var alertBaseline: Double?
        var observedAt: Date
    }
    private struct Entry: Codable, Sendable {
        var event: GradeNotificationEvent
        var delivery: GradeNotificationDelivery
        var requestID: String? = nil
    }
    private struct ViewedGrade: Codable, Sendable {
        var score: Double
        var sourceDate: Date
    }
    private var observations: [String: [String: Observation]] = [:]
    private var entries: [Entry] = []
    private var viewedGrades: [String: [String: ViewedGrade]] = [:]
    let threshold: Double
    let maximumEntries: Int

    init(threshold: Double = 0.01, maximumEntries: Int = 500) {
        self.threshold = threshold.isFinite && threshold > 0 ? threshold : 0.01
        self.maximumEntries = max(1, maximumEntries)
    }

    private enum CodingKeys: String, CodingKey { case observations, entries, viewedGrades, threshold, maximumEntries }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        observations = try values.decode([String: [String: Observation]].self, forKey: .observations)
        entries = try values.decode([Entry].self, forKey: .entries)
        viewedGrades = try values.decodeIfPresent([String: [String: ViewedGrade]].self, forKey: .viewedGrades) ?? [:]
        // The old half-point cutoff was fixed policy, never a user preference.
        let savedThreshold = try values.decode(Double.self, forKey: .threshold)
        threshold = savedThreshold == 0.5 || !savedThreshold.isFinite || savedThreshold <= 0 ? 0.01 : savedThreshold
        maximumEntries = max(1, try values.decode(Int.self, forKey: .maximumEntries))
        if savedThreshold == 0.5 {
            // Start the finer policy from the latest old observation; don't
            // retroactively announce subthreshold grades from before this update.
            for (term, courses) in observations {
                for (courseID, observation) in courses where !entries.contains(where: {
                    $0.event.term.rawValue == term && $0.event.courseID == courseID && Self.isPending($0.delivery)
                }) {
                    observations[term]?[courseID]?.alertBaseline = observation.latestScore
                }
            }
        }
    }

    static func samePostedScore(_ lhs: Double, _ rhs: Double) -> Bool {
        guard lhs.isFinite, rhs.isFinite else { return false }
        let a = lhs * 100, b = rhs * 100
        return a.isFinite && b.isFinite ? a.rounded() == b.rounded() : lhs == rhs
    }

    /// Called only for an official grade actually displayed. An older cached
    /// value must not acknowledge a newer, different pending change.
    mutating func markViewed(courseID: String, term: TermLabel, score: Double, sourceDate: Date) {
        guard !courseID.isEmpty, score.isFinite else { return }
        let key = term.rawValue
        if let previous = viewedGrades[key]?[courseID], previous.sourceDate > sourceDate { return }
        viewedGrades[key, default: [:]][courseID] = ViewedGrade(score: score, sourceDate: sourceDate)
        if let latest = observations[key]?[courseID]?.latestScore, Self.samePostedScore(latest, score) {
            observations[key]?[courseID]?.alertBaseline = latest
        }
        for event in pendingEvents where event.courseID == courseID && event.term == term
            && (Self.samePostedScore(event.currentScore, score) || sourceDate >= event.discoveredAt) {
            consumeWithoutAlert(eventID: event.id)
        }
        trimObservations()
    }


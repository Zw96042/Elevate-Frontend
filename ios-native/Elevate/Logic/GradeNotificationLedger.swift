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

    func wasViewed(_ event: GradeNotificationEvent) -> Bool {
        guard let viewed = viewedGrades[event.term.rawValue]?[event.courseID] else { return false }
        return Self.samePostedScore(viewed.score, event.currentScore) || viewed.sourceDate >= event.discoveredAt
    }

    mutating func associateRequest(_ requestID: String, eventIDs: Set<String>) {
        for index in entries.indices where eventIDs.contains(entries[index].event.id) {
            entries[index].requestID = requestID
        }
    }

    func unseenEvents(forRequest requestID: String) -> [GradeNotificationEvent] {
        entries.compactMap { entry in
            guard entry.requestID == requestID, entry.delivery != .consumed,
                  !wasViewed(entry.event),
                  let latest = latestObservedScore(courseID: entry.event.courseID, term: entry.event.term),
                  Self.samePostedScore(latest, entry.event.currentScore) else { return nil }
            return entry.event
        }
    }

    /// Live gradebook membership is independent of transcript-year provenance.
    static func eligibleCourses(in courses: [UnifiedCourseData]) -> [UnifiedCourseData] {
        let live = courses.filter { $0.hasGradebookParams && $0.courseId != nil }
        let highestGrade = live.compactMap(\.gradeYear).max()
        return live.filter { highestGrade == nil || $0.gradeYear == highestGrade }
    }

    var pendingEvents: [GradeNotificationEvent] {
        entries.compactMap { entry in
            switch entry.delivery {
            case .pending, .retry: entry.event
            case .accepted, .consumed: nil
            }
        }
    }

    func delivery(for eventID: String) -> GradeNotificationDelivery? {
        entries.first { $0.event.id == eventID }?.delivery
    }

    func latestObservedScore(courseID: String, term: TermLabel) -> Double? {
        observations[term.rawValue]?[courseID]?.latestScore
    }

    @discardableResult
    mutating func observe(_ scores: [String: Double?], term: TermLabel,
                          source: GradeObservationSource = .freshValidated,
                          at date: Date = Date()) -> [GradeNotificationEvent] {
        guard source == .freshValidated else { return [] }
        let termKey = term.rawValue
        for courseID in scores.keys.sorted() {
            guard !courseID.isEmpty else { continue }
            let rawScore = scores[courseID] ?? nil
            // Nonfinite data is invalid, rather than a genuine unavailable grade.
            if let rawScore, !rawScore.isFinite { continue }
            guard var observation = observations[termKey]?[courseID] else {
                observations[termKey, default: [:]][courseID] = Observation(
                    latestScore: rawScore, alertBaseline: rawScore, observedAt: date)
                continue
            }
            guard date >= observation.observedAt else { continue }
            if let viewed = viewedGrades[termKey]?[courseID], let score = rawScore {
                // A display can precede its notification observation. Retain it
                // for that result, but never suppress a later return to an old grade.
                if Self.samePostedScore(viewed.score, score),
                   observation.latestScore.map({ Self.samePostedScore($0, score) }) == true
                    || viewed.sourceDate >= observation.observedAt {
                    observation.alertBaseline = score
                } else if date > viewed.sourceDate {
                    viewedGrades[termKey]?.removeValue(forKey: courseID)
                }
            } else if rawScore == nil {
                viewedGrades[termKey]?.removeValue(forKey: courseID)
            }
            observation.latestScore = rawScore
            observation.observedAt = date
            if rawScore == nil {
                observation.alertBaseline = nil
                // A disappeared grade invalidates a pending numeric notification.
                entries.removeAll { $0.event.courseID == courseID && $0.event.term == term && Self.isPending($0.delivery) }
            }
            observations[termKey, default: [:]][courseID] = observation
            guard let score = rawScore else { continue }
            let pendingIndex = entries.firstIndex { $0.event.courseID == courseID && $0.event.term == term && Self.isPending($0.delivery) }
            if let previous = observation.alertBaseline,
               threshold == 0.01 ? Self.samePostedScore(score, previous) : abs(score - previous) < threshold {
                if let pendingIndex { entries.remove(at: pendingIndex) }
                continue
            }
            if let pendingIndex {
                // A failed/unaccepted request must describe the latest observation,
                // rather than alerting an obsolete dip after the grade recovers.
                let previous = entries[pendingIndex].event
                entries[pendingIndex].event = GradeNotificationEvent(
                    id: previous.id, courseID: courseID, term: term,
                    previousScore: observation.alertBaseline, currentScore: score,
                    kind: observation.alertBaseline == nil ? .gradeAvailable : .averageChanged,
                    discoveredAt: date)
                continue
            }
            // Prefer removing completed entries; pending work also remains bounded.
            if entries.count >= maximumEntries {
                if let completed = entries.firstIndex(where: { !Self.isPending($0.delivery) }) {
                    entries.remove(at: completed)
                } else {
                    // Preserve existing retries. A later observation can enqueue this change.
                    continue
                }
            }
            entries.append(Entry(event: GradeNotificationEvent(
                id: UUID().uuidString, courseID: courseID, term: term,
                previousScore: observation.alertBaseline, currentScore: score,
                kind: observation.alertBaseline == nil ? .gradeAvailable : .averageChanged,
                discoveredAt: date), delivery: .pending))
        }
        // Bound history as well as event storage without evicting pending baselines.
        trimObservations()
        return pendingEvents.filter { $0.term == term && scores.keys.contains($0.courseID) }
    }


import Foundation

struct GradeJournalAssignmentValue: Codable, Equatable, Sendable {
    let score: Double?
    let pointsEarned: Double?
    let pointsPossible: Double?
    /// Teacher-provided status types; notes are not grade changes.
    let statuses: [String]
}

/// A change discovered by Elevate, not a claimed teacher-edit timestamp.
struct GradeJournalEvent: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case averageChanged, assignmentAdded, assignmentChanged }
    let id: String
    let courseID: String
    let courseName: String
    let term: TermLabel
    let kind: Kind
    let observedAt: Date
    let previousScore: Double?
    let currentScore: Double?
    let assignmentID: String?
    let assignmentName: String?
    let assignmentDate: String?
    let category: String?
    let previousAssignment: GradeJournalAssignmentValue?
    let currentAssignment: GradeJournalAssignmentValue?
}

/// Pure, bounded observation history. Separate from viewed grades and alerts.
struct GradeJournal: Codable, Sendable {
    private struct Average: Codable, Sendable {
        var score: Double?
        var observedAt: Date
    }
    private struct Assignment: Codable, Sendable {
        let name: String
        let date: String
        let category: String
        let value: GradeJournalAssignmentValue
    }
    private struct AssignmentBaseline: Codable, Sendable {
        var values: [String: Assignment]
        var observedAt: Date
        var ambiguous: Set<String>
    }
    private var averages: [String: Average] = [:]
    private var assignmentBaselines: [String: AssignmentBaseline] = [:]
    private(set) var events: [GradeJournalEvent] = []
    let maximumEvents: Int
    let maximumScopes: Int
    let retentionDays: Int
    private static let maximumAssignments = 1_000
    private static let maximumText = 2_048

    init(maximumEvents: Int = 500, maximumScopes: Int = 200, retentionDays: Int = 90) {
        self.maximumEvents = min(2_000, max(1, maximumEvents))
        self.maximumScopes = min(500, max(1, maximumScopes))
        self.retentionDays = min(365, max(1, retentionDays))
    }

    @discardableResult
    mutating func observeAverage(_ score: Double?, courseID: String, courseName: String,
                                 term: TermLabel, source: GradeObservationSource = .freshValidated,
                                 at date: Date = Date()) -> [GradeJournalEvent] {
        guard source == .freshValidated, Self.valid(date), Self.validScore(score),
              Self.validIdentity(courseID), Self.validText(courseName) else { return [] }
        let key = Self.identity([courseID, term.rawValue])
        let previous = averages[key]
        guard previous == nil || date > previous!.observedAt else { return [] }
        averages[key] = Average(score: score, observedAt: date)
        var added: [GradeJournalEvent] = []
        if let previous, previous.score != score {
            added.append(GradeJournalEvent(
                id: Self.eventID(scope: key, assignmentID: nil, at: date),
                courseID: courseID, courseName: courseName, term: term, kind: .averageChanged,
                observedAt: date, previousScore: previous.score, currentScore: score,
                assignmentID: nil, assignmentName: nil, assignmentDate: nil, category: nil,
                previousAssignment: nil, currentAssignment: nil))
        }
        append(added, at: date)
        trimBaselines()
        return added
    }

    /// Call only for a complete, validated gradebook network response. First
    /// assignment observation seeds independently of course-average observation.
    /// No removal events: an absent row does not establish teacher deletion.
    @discardableResult
    mutating func observeAssignments(_ result: GradeInfoResult, courseID: String, courseName: String,
                                     term: TermLabel, source: GradeObservationSource = .freshValidated,
                                     at date: Date = Date()) -> [GradeJournalEvent] {
        guard source == .freshValidated, Self.valid(date), Self.validIdentity(courseID),
              Self.validText(courseName), let snapshot = Self.snapshot(result) else { return [] }
        let key = Self.identity([courseID, term.rawValue])
        let previous = assignmentBaselines[key]
        guard previous == nil || date > previous!.observedAt else { return [] }
        var values = previous?.values ?? [:]
        // Skyward has no stable assignment ID here. Same name/date/category
        // duplicates are ambiguous; discard their baseline and silently reseed
        // when unique again rather than attaching a score to the wrong row.
        for id in snapshot.ambiguous { values.removeValue(forKey: id) }
        var added: [GradeJournalEvent] = []
        for id in snapshot.values.keys.sorted() {
            let current = snapshot.values[id]!
            if previous != nil, !snapshot.ambiguous.contains(id) {
                let old = values[id]
                // A duplicate that becomes unique must seed silently. Remember
                // those identities separately from genuinely new assignments.
                if old?.value != current.value, !(previous?.ambiguous.contains(id) ?? false) {
                    added.append(GradeJournalEvent(
                        id: Self.eventID(scope: key, assignmentID: id, at: date),
                        courseID: courseID, courseName: courseName, term: term,
                        kind: old == nil ? .assignmentAdded : .assignmentChanged,
                        observedAt: date, previousScore: old?.value.score, currentScore: current.value.score,
                        assignmentID: id, assignmentName: current.name, assignmentDate: current.date,
                        category: current.category, previousAssignment: old?.value, currentAssignment: current.value))
                }
            }
            values[id] = current
        }
        let ambiguous = (previous?.ambiguous ?? []).union(snapshot.ambiguous).subtracting(snapshot.values.keys)
        guard values.count + ambiguous.count <= Self.maximumAssignments else { return [] }
        assignmentBaselines[key] = AssignmentBaseline(values: values, observedAt: date, ambiguous: ambiguous)
        append(added, at: date)
        trimBaselines()
        return added
    }


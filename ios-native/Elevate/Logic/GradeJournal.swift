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

    mutating func clearHistory() {
        events = []; averages = [:]; assignmentBaselines = [:]
    }

    private struct Snapshot {
        var values: [String: Assignment]
        var ambiguous: Set<String>
    }

    private static func snapshot(_ result: GradeInfoResult) -> Snapshot? {
        guard validScore(result.score), result.gradebook.count <= maximumAssignments else { return nil }
        var values: [String: Assignment] = [:], ambiguous: Set<String> = []
        var count = 0
        for category in result.gradebook {
            guard validText(category.category) else { return nil }
            for assignment in category.assignments {
                count += 1
                guard count <= maximumAssignments, validIdentity(assignment.name), validText(assignment.date),
                      validScore(assignment.score), validScore(assignment.pointsEarned), validScore(assignment.pointsTotal),
                      assignment.meta.count <= 50, assignment.meta.allSatisfy({ validText($0.type) }) else { return nil }
                let id = identity([category.category, assignment.name, assignment.date])
                let value = GradeJournalAssignmentValue(
                    score: assignment.score, pointsEarned: assignment.pointsEarned,
                    pointsPossible: assignment.pointsTotal,
                    statuses: Array(Set(assignment.meta.map { $0.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })).sorted())
                if values[id] != nil || ambiguous.contains(id) {
                    values.removeValue(forKey: id); ambiguous.insert(id)
                } else {
                    values[id] = Assignment(name: assignment.name, date: assignment.date, category: category.category, value: value)
                }
            }
        }
        return Snapshot(values: values, ambiguous: ambiguous)
    }

    private mutating func append(_ added: [GradeJournalEvent], at date: Date) {
        events.append(contentsOf: added)
        let latestDate = max(date, events.map(\.observedAt).max() ?? date)
        let cutoff = latestDate.addingTimeInterval(-Double(retentionDays) * 86_400)
        events.removeAll { $0.observedAt < cutoff }
        events.sort { $0.observedAt == $1.observedAt ? $0.id < $1.id : $0.observedAt > $1.observedAt }
        if events.count > maximumEvents { events.removeLast(events.count - maximumEvents) }
    }

    private mutating func trimBaselines() {
        let averageKeys = averages.keys.sorted {
            averages[$0]!.observedAt == averages[$1]!.observedAt ? $0 < $1 : averages[$0]!.observedAt > averages[$1]!.observedAt
        }
        for key in averageKeys.dropFirst(maximumScopes) { averages.removeValue(forKey: key) }
        let assignmentKeys = assignmentBaselines.keys.sorted {
            assignmentBaselines[$0]!.observedAt == assignmentBaselines[$1]!.observedAt ? $0 < $1 : assignmentBaselines[$0]!.observedAt > assignmentBaselines[$1]!.observedAt
        }
        for key in assignmentKeys.dropFirst(maximumScopes) { assignmentBaselines.removeValue(forKey: key) }
    }

    private static func identity(_ parts: [String]) -> String {
        parts.map { "\($0.utf8.count):\($0)" }.joined()
    }
    private static func eventID(scope: String, assignmentID: String?, at date: Date) -> String {
        identity([scope, assignmentID ?? "average", String(date.timeIntervalSince1970.bitPattern)])
    }
    private static func valid(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite }
    private static func validText(_ text: String) -> Bool { text.utf8.count <= maximumText }
    private static func validIdentity(_ text: String) -> Bool { !text.isEmpty && validText(text) }
    private static func validScore(_ score: Double?) -> Bool {
        score.map { $0.isFinite && abs($0) <= AcademicScoreValue.magnitudeLimit } ?? true
    }

    /// Validate decoded storage before allowing it to become a comparison base.
    fileprivate var isValid: Bool {
        guard (1...2_000).contains(maximumEvents), (1...500).contains(maximumScopes),
              (1...365).contains(retentionDays), events.count <= maximumEvents,
              averages.count <= maximumScopes, assignmentBaselines.count <= maximumScopes,
              Set(events.map(\.id)).count == events.count else { return false }
        func validValue(_ value: GradeJournalAssignmentValue) -> Bool {
            Self.validScore(value.score) && Self.validScore(value.pointsEarned) && Self.validScore(value.pointsPossible)
                && value.statuses.count <= 50 && value.statuses.allSatisfy(Self.validText)
                && value.statuses == Array(Set(value.statuses)).sorted()
        }
        return averages.allSatisfy { !$0.key.isEmpty && $0.key.utf8.count <= 4_096 && Self.valid($0.value.observedAt) && Self.validScore($0.value.score) }
            && assignmentBaselines.allSatisfy { entry in
                !entry.key.isEmpty && entry.key.utf8.count <= 4_096 && Self.valid(entry.value.observedAt)
                    && entry.value.values.count + entry.value.ambiguous.count <= Self.maximumAssignments
                    && entry.value.values.allSatisfy {
                        Self.validIdentity($0.value.name) && Self.validText($0.value.date) && Self.validText($0.value.category)
                            && $0.key == Self.identity([$0.value.category, $0.value.name, $0.value.date]) && validValue($0.value.value)
                    }
            }
            && events.allSatisfy {
                Self.valid($0.observedAt) && Self.validIdentity($0.courseID) && Self.validText($0.courseName)
                    && Self.validScore($0.previousScore) && Self.validScore($0.currentScore)
                    && ($0.previousAssignment.map(validValue) ?? true) && ($0.currentAssignment.map(validValue) ?? true)
            }
    }
}


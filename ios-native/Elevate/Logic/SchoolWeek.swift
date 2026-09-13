import Foundation

/// School-local Monday–Sunday dates; assignment due days are not timestamps.
struct SchoolWeek: Equatable {
    var firstDay: String
    var lastDay: String
    var days: [String]

    static func containing(_ date: Date) -> SchoolWeek {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let today = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: today)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let days = (0..<7).map {
            formatter.string(from: calendar.date(byAdding: .day, value: $0, to: monday)!)
        }
        return SchoolWeek(firstDay: days[0], lastDay: days[6], days: days)
    }

    static func day(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "America/Chicago")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// A useful upcoming school-week window, including the rest of today.
    static func upcoming(from date: Date) -> SchoolWeek {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let today = calendar.startOfDay(for: date)
        let days = (0..<7).map { day(for: calendar.date(byAdding: .day, value: $0, to: today)!) }
        return SchoolWeek(firstDay: days[0], lastDay: days[6], days: days)
    }
}

struct SchoolWeekDay: Identifiable {
    var id: String
    var assignments: [CalendarAssignment]
    var reminders: [LocalReminder]
}

/// The week's active work, plus a separate Done list for work the student
/// checked off. Done is a local projection only: Skyward's Missing flag and
/// every reminder are unchanged by it.
struct SchoolWeekPlan {
    var week: SchoolWeek
    /// Active assignments by due day. Every reminder stays on the day it
    /// fires, whether or not its assignment is Done.
    var days: [SchoolWeekDay]
    var missing: [CalendarAssignment]
    var undated: [CalendarAssignment]
    /// Checked-off work that would otherwise be listed in Missing, a day or
    /// undated, each assignment once, by due day with undated work last.
    var done: [CalendarAssignment]
    /// This week's reminders for each Done assignment, by assignment ID.
    var doneReminders: [String: [LocalReminder]]
    /// Done assignments due on one of the week's days.
    var doneDueCount: Int
    /// Identical source rows cannot safely own independent personal marks,
    /// so they stay active even when an old mark matches.
    var ambiguousAssignmentIDs: Set<String>

    init(data: SchoolCalendarData?, reminders: [LocalReminder], completedIDs: Set<String> = [],
         now: Date = Date(),
         isLinked: (LocalReminder, CalendarAssignment) -> Bool = SchoolWeekPlan.sameAssignment) {
        week = SchoolWeek.upcoming(from: now)
        let assignments = data?.assignments ?? []
        func precedes(_ a: CalendarAssignment, _ b: CalendarAssignment) -> Bool {
            if a.course.period != b.course.period {
                return (a.course.period ?? Int.max) < (b.course.period ?? Int.max)
            }
            if a.title != b.title { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
            return a.id < b.id
        }
        func sorted(_ rows: [CalendarAssignment]) -> [CalendarAssignment] { rows.sorted(by: precedes) }

        let ambiguous = AssignmentCompletion.ambiguousIDs(in: assignments)
        ambiguousAssignmentIDs = ambiguous
        func isDone(_ row: CalendarAssignment) -> Bool {
            completedIDs.contains(row.id) && !ambiguous.contains(row.id)
        }

        let allMissing = sorted(assignments.filter { $0.meta.contains { $0.type.lowercased() == "missing" } })
        let allUndated = sorted(assignments.filter { $0.date == nil })
        let dueByDay = week.days.map { day in sorted(assignments.filter { $0.date == day }) }
        days = zip(week.days, dueByDay).map { day, due in
            SchoolWeekDay(id: day,
                assignments: due.filter { !isDone($0) },
                reminders: reminders.filter { SchoolWeek.day(for: $0.fireDate) == day }
                    .sorted { $0.fireDate < $1.fireDate })
        }
        missing = allMissing.filter { !isDone($0) }
        undated = allUndated.filter { !isDone($0) }
        let allDue = dueByDay.flatMap { $0 }
        doneDueCount = allDue.filter { isDone($0) }.count

        // Missing work due today is listed twice; Done holds it once.
        var seen = Set<String>()
        done = (allMissing + allDue + allUndated)
            .filter { isDone($0) && seen.insert($0.id).inserted }
            .sorted { a, b in
                if a.date != b.date {
                    guard let first = a.date else { return false }
                    guard let second = b.date else { return true }
                    return first < second
                }
                return precedes(a, b)
            }
        let weekReminders = days.flatMap(\.reminders)
        var linked: [String: [LocalReminder]] = [:]
        for assignment in done {
            let matches = weekReminders.filter { isLinked($0, assignment) }
            if !matches.isEmpty { linked[assignment.id] = matches }
        }
        doneReminders = linked
    }

    /// A reminder's own link. Callers with course identity pass a stricter check.
    static func sameAssignment(_ reminder: LocalReminder, _ assignment: CalendarAssignment) -> Bool {
        reminder.assignmentID == assignment.id && reminder.term == assignment.term
    }

    /// The day's reminders that aren't shown with a Done assignment.
    func shownReminders(on day: SchoolWeekDay) -> [LocalReminder] {
        let withDone = Set(doneReminders.values.joined().map(\.id))
        return day.reminders.filter { !withDone.contains($0.id) }
    }
}

/// Rules shared by every list that shows personal Done marks.
enum AssignmentCompletion {
    /// Identical source rows (same class, quarter, category, title and source
    /// date) cannot safely own independent personal marks, so none of them
    /// shows as Done even when an old mark matches.
    static func ambiguousIDs(in assignments: [CalendarAssignment]) -> Set<String> {
        let groups = Dictionary(grouping: assignments) { row in
            [row.course.id, row.term.rawValue, row.category, row.title, row.sourceDate]
                .map { "\($0.utf8.count):\($0)" }.joined()
        }
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }
}

/// Personal checkmarks never mutate assignment metadata or school grade caches.
final class AssignmentCompletionStore {
    let accountIdentifier: String
    private let defaults: UserDefaults
    private let key: String
    private(set) var completed: [String: Date]
    private(set) var storageUnavailable = false

    init(accountIdentifier: String, defaults: UserDefaults = .standard) {
        self.accountIdentifier = accountIdentifier
        self.defaults = defaults
        key = "account.\(accountIdentifier).assignmentCompletion.v1"
        completed = [:]
        if defaults.object(forKey: key) != nil {
            if let data = defaults.data(forKey: key), data.count <= 2_000_000,
               let decoded = try? JSONDecoder().decode([String: Date].self, from: data),
               decoded.count <= 4_000, decoded.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 8_192 }),
               decoded.values.allSatisfy({ $0.timeIntervalSince1970.isFinite }) {
                completed = decoded
            } else { storageUnavailable = true }
        }
    }

    func isCompleted(_ id: String) -> Bool { completed[id] != nil }

    @discardableResult
    func setCompleted(_ done: Bool, id: String, expectedAccountIdentifier: String, at: Date = Date()) -> Bool {
        guard !storageUnavailable, expectedAccountIdentifier == accountIdentifier,
              !id.isEmpty, id.utf8.count <= 8_192, at.timeIntervalSince1970.isFinite else { return false }
        var next = completed
        next[id] = done ? at : nil
        if next.count > 4_000, let oldest = next.min(by: { $0.value < $1.value })?.key { next[oldest] = nil }
        guard let data = try? JSONEncoder().encode(next), data.count <= 2_000_000 else { return false }
        defaults.set(data, forKey: key)
        completed = next
        return true
    }

    func clear() {
        defaults.removeObject(forKey: key)
        completed = [:]
        storageUnavailable = false
    }

    static func remove(accountIdentifier: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "account.\(accountIdentifier).assignmentCompletion.v1")
    }
}

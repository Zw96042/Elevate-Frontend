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


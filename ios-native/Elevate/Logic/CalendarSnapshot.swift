import Foundation

/// Everything the month grid draws, computed once per data change rather
/// than on every scroll or frame: each day's busy level and attendance mark,
/// and each week's laid-out personal events. Pure value, so it's testable.
struct CalendarSnapshot {
    /// Assignments and attendance by school day, plus undated entries.
    var index: CalendarDayIndex
    var eventsByDay: [String: [PersonalEvent]]
    private(set) var levels: [CalendarDay: Int] = [:]
    private(set) var attendanceDays: Set<CalendarDay> = []
    private(set) var weekLayouts: [String: CalendarWeekLayout] = [:]
    /// Identical source rows, which can't own independent personal marks.
    private(set) var ambiguousIDs: Set<String> = []

    static var empty: CalendarSnapshot { CalendarSnapshot(assignments: [], attendance: [], eventsByDay: [:], weeks: []) }

    init(assignments: [CalendarAssignment], attendance: [AttendanceRecord],
         eventsByDay: [String: [PersonalEvent]], weeks: [CalendarWeek]) {
        index = CalendarDayIndex(attendance: attendance, assignments: assignments)
        self.eventsByDay = eventsByDay
        ambiguousIDs = AssignmentCompletion.ambiguousIDs(in: assignments)
        for (day, list) in index.assignments {
            levels[day] = CalendarDayLoad.level(assignmentsDue: list.count)
        }
        attendanceDays = Set(index.attendance.keys)
        guard !eventsByDay.isEmpty else { return }
        for week in weeks where week.days.contains(where: { eventsByDay[$0.iso]?.isEmpty == false }) {
            weekLayouts[week.id] = CalendarWeekLayout(days: week.days, eventsByDay: eventsByDay)
        }
    }

    func level(_ day: CalendarDay) -> Int { levels[day] ?? 0 }

    func hasAttendance(_ day: CalendarDay) -> Bool { attendanceDays.contains(day) }

    func layout(for week: CalendarWeek) -> CalendarWeekLayout {
        weekLayouts[week.id] ?? CalendarWeekLayout(days: [], eventsByDay: [:])
    }

    func assignments(on day: CalendarDay) -> [CalendarAssignment] { index.assignments[day] ?? [] }

    func attendance(on day: CalendarDay) -> [AttendanceRecord] { index.attendance[day] ?? [] }

    func events(on day: CalendarDay) -> [PersonalEvent] { eventsByDay[day.iso] ?? [] }
}

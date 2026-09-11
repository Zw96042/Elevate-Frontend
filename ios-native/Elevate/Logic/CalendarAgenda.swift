import Foundation

/// Dates for the Calendar page. School dates are Gregorian calendar days
/// without a time zone; the page lays them out in the person's own calendar
/// (weeks start on their first weekday). Everything here is pure so the
/// week, month and quarter rules are testable without SwiftUI.
enum CalendarAgenda {
    /// Gregorian days in the device's zone and locale, weeks on the device's
    /// first weekday.
    /// Built once: the grid asks for it for every cell. A time-zone or
    /// locale change while the app runs takes effect on next launch.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }()

    /// Weekday initials in the calendar's week order.
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[first...] + symbols[..<first])
    }
}

/// One school date, yyyy-MM-dd.
struct CalendarDay: Hashable, Comparable, Identifiable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Only a valid source school date; anything else is undated.
    init?(iso: String?) {
        guard let iso,
              let parts = AttendanceSchoolDate.components(iso.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        self.init(year: parts.year, month: parts.month, day: parts.day)
    }

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func today(calendar: Calendar = CalendarAgenda.calendar) -> CalendarDay {
        CalendarDay(Date(), calendar: calendar)
    }

    var id: String { iso }
    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var calendarMonth: CalendarMonth { CalendarMonth(year: year, month: month) }

    /// Local noon keeps the school date in any time zone.
    func date(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    func adding(_ days: Int, calendar: Calendar) -> CalendarDay {
        guard let date = calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) else { return self }
        return CalendarDay(date, calendar: calendar)
    }

    /// "Wednesday, October 7", with the year outside the current one.
    func title(today: CalendarDay, calendar: Calendar) -> String {
        let date = date(calendar: calendar)
        if year == today.year {
            return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// "Today", "Tomorrow", "Yesterday", otherwise the weekday: "Monday", or
    /// "Mon" when abbreviated.
    func relativeName(today: CalendarDay, calendar: Calendar, abbreviated: Bool = false) -> String {
        if self == today { return "Today" }
        if self == today.adding(1, calendar: calendar) { return "Tomorrow" }
        if self == today.adding(-1, calendar: calendar) { return "Yesterday" }
        return date(calendar: calendar).formatted(.dateTime.weekday(abbreviated ? .abbreviated : .wide))
    }

    /// "October 12", with the year outside the current one.
    func monthDayTitle(today: CalendarDay, calendar: Calendar) -> String {
        let date = date(calendar: calendar)
        if year == today.year {
            return date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

struct CalendarMonth: Hashable, Comparable, Identifiable, Sendable {
    var year: Int
    /// 1 through 12.
    var month: Int

    var id: String { String(format: "%04d-%02d", year, month) }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// A page id as produced by `id`; anything else is no month.
    init?(id: String) {
        let parts = id.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
              (1...12).contains(month), (1...9999).contains(year) else { return nil }
        self.init(year: year, month: month)
    }

    func adding(_ months: Int) -> CalendarMonth {
        let index = year * 12 + (month - 1) + months
        return CalendarMonth(year: index / 12, month: index % 12 + 1)
    }

    var firstDay: CalendarDay { CalendarDay(year: year, month: month, day: 1) }
    var lastDay: CalendarDay { CalendarDay(year: year, month: month, day: dayCount) }

    var dayCount: Int {
        let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    }

    var days: [CalendarDay] { (1...dayCount).map { CalendarDay(year: year, month: month, day: $0) } }

    func title(calendar: Calendar) -> String {
        firstDay.date(calendar: calendar).formatted(.dateTime.month(.wide).year())
    }

    /// Whole weeks of day cells; nil pads the days outside this month.
    func cells(calendar: Calendar) -> [CalendarDay?] {
        let weekday = calendar.component(.weekday, from: firstDay.date(calendar: calendar))
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [CalendarDay?] = Array(repeating: nil, count: leading)
        cells.append(contentsOf: days)
        cells.append(contentsOf: Array(repeating: nil, count: (7 - cells.count % 7) % 7))
        return cells
    }

    func clamped(to range: ClosedRange<CalendarMonth>) -> CalendarMonth {
        min(max(self, range.lowerBound), range.upperBound)
    }

    /// The school year containing today, August through July, widened to
    /// every month holding a dated entry so no source entry is out of reach.
    static func browseRange(today: CalendarDay, entryMonths: Set<CalendarMonth>) -> ClosedRange<CalendarMonth> {
        let current = today.calendarMonth
        var lower = CalendarMonth(year: current.month >= 8 ? current.year : current.year - 1, month: 8)
        var upper = lower.adding(11)
        for month in entryMonths {
            lower = min(lower, month)
            upper = max(upper, month)
        }
        return lower...upper
    }

    /// Every month of the range, in order.
    static func months(in range: ClosedRange<CalendarMonth>) -> [CalendarMonth] {
        var months: [CalendarMonth] = []
        var month = range.lowerBound
        while month <= range.upperBound {
            months.append(month)
            month = month.adding(1)
        }
        return months
    }

    /// Every day of the range, in order.
    static func days(in range: ClosedRange<CalendarMonth>) -> [CalendarDay] {
        months(in: range).flatMap(\.days)
    }

    static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}


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


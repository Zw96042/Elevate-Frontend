import Foundation
import Testing
@testable import ElevateCore

@Suite("Calendar agenda days, weeks and quarters")
struct CalendarAgendaTests {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    @Test("A day maps to the quarter whose gradebook holds it, keeping the preceding quarter across breaks")
    func quarterMap() throws {
        let cases: [(String, TermLabel)] = [
            ("2026-08-01", .q1), ("2026-08-13", .q1), ("2026-10-08", .q1),
            ("2026-10-09", .q1), ("2026-10-12", .q1),
            ("2026-10-13", .q2), ("2026-12-18", .q2),
            ("2026-12-19", .q2), ("2027-01-04", .q2),
            ("2027-01-05", .q3), ("2027-03-12", .q3), ("2027-03-21", .q3),
            ("2027-03-22", .q4), ("2027-05-21", .q4),
            ("2027-05-22", .q4), ("2027-07-31", .q4),
            // Other years use the documented legacy approximation.
            ("2025-10-20", .q1), ("2025-10-26", .q2), ("2026-01-05", .q2), ("2026-01-12", .q3),
        ]
        for (iso, term) in cases {
            let day = try #require(CalendarDay(iso: iso))
            #expect(CalendarQuarterMap.quarter(for: day) == term, "\(iso)")
        }
        let straddle = (9...17).map { CalendarDay(year: 2026, month: 10, day: $0) }
        #expect(CalendarQuarterMap.quarters(for: straddle) == [.q1, .q2])
        #expect(CalendarQuarterMap.quarters(for: [CalendarDay(year: 2027, month: 4, day: 1),
                                                   CalendarDay(year: 2026, month: 9, day: 1)]) == [.q1, .q4])
        #expect(CalendarQuarterMap.quarters(for: [CalendarDay]()).isEmpty)
    }

    @Test("Busy levels count every assignment due, graded or not, in five steps")
    func dayLoad() {
        #expect(CalendarDayLoad.level(assignmentsDue: 0) == 0)
        #expect(CalendarDayLoad.level(assignmentsDue: 1) == 1)
        #expect(CalendarDayLoad.level(assignmentsDue: 2) == 2)
        #expect(CalendarDayLoad.level(assignmentsDue: 3) == 3)
        #expect(CalendarDayLoad.level(assignmentsDue: 4) == 3)
        #expect(CalendarDayLoad.level(assignmentsDue: 5) == 4)
        #expect(CalendarDayLoad.level(assignmentsDue: 40) == 4)
        #expect(CalendarDayLoad.level(assignmentsDue: -5) == 0)
        #expect(CalendarDayLoad.maximumLevel == 4)
    }

    @Test("Weeks start on the calendar's first weekday and cross month and year ends")
    func weeks() throws {
        let sunday = calendar(firstWeekday: 1)
        let monday = calendar(firstWeekday: 2)
        let friday = try #require(CalendarDay(iso: "2026-10-09"))
        #expect(CalendarWeek.containing(friday, calendar: sunday).days.map(\.iso).first == "2026-10-04")
        #expect(CalendarWeek.containing(friday, calendar: sunday).lastDay.iso == "2026-10-10")
        #expect(CalendarWeek.containing(friday, calendar: monday).firstDay.iso == "2026-10-05")
        #expect(CalendarWeek.containing(friday, calendar: monday).lastDay.iso == "2026-10-11")

        let newYear = try #require(CalendarDay(iso: "2027-01-01"))
        let week = CalendarWeek.containing(newYear, calendar: sunday)
        #expect(week.firstDay.iso == "2026-12-27" && week.lastDay.iso == "2027-01-02")
        #expect(week.contains(newYear) && !week.contains(friday))
        #expect(week.adding(1, calendar: sunday).firstDay.iso == "2027-01-03")
        #expect(week.adding(-1, calendar: sunday).firstDay.iso == "2026-12-20")
        #expect(week.id == "2026-12-27")

        let range = CalendarMonth(year: 2026, month: 10)...CalendarMonth(year: 2026, month: 11)
        let weeks = CalendarWeek.weeks(in: range, calendar: sunday)
        #expect(weeks.first?.firstDay.iso == "2026-09-27")
        #expect(weeks.last?.lastDay.iso == "2026-12-05")
        #expect(weeks.count == 10)
        #expect(Set(weeks.map(\.id)).count == weeks.count)
    }

    @Test("Months list their days and cells, and the browse range widens to saved entries")
    func months() {
        let october = CalendarMonth(year: 2026, month: 10)
        #expect(october.dayCount == 31 && october.lastDay.day == 31)
        #expect(CalendarMonth(year: 2028, month: 2).dayCount == 29)
        #expect(CalendarMonth(year: 2100, month: 2).dayCount == 28)
        #expect(october.adding(3) == CalendarMonth(year: 2027, month: 1))
        #expect(october.adding(-10) == CalendarMonth(year: 2025, month: 12))
        let cells = october.cells(calendar: calendar(firstWeekday: 1))
        #expect(cells.count == 35 && cells.prefix(4).allSatisfy { $0 == nil } && cells[4]?.day == 1)
        #expect(october.cells(calendar: calendar(firstWeekday: 2)).count == 35)
        #expect(CalendarMonth.days(in: october...october.adding(1)).count == 61)
        #expect(CalendarMonth.months(in: october...october.adding(2)).map(\.month) == [10, 11, 12])


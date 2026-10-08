import Foundation
import Testing
@testable import ElevateCore

@Suite struct PersonalCalendarTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false,
                       id: String? = nil) -> PersonalEvent {
        PersonalEvent(eventIdentifier: id ?? title, calendarID: "cal", title: title, location: nil,
                      start: start, end: end, isAllDay: allDay)
    }

    private func info(_ id: String, _ title: String, account: String, hidden: Bool = false) -> PersonalCalendarInfo {
        PersonalCalendarInfo(id: id, title: title, accountTitle: account,
                             color: .init(red: 0, green: 0, blue: 0), isHiddenByDefault: hidden)
    }

    @Test func singleDayTimedEventMarksOnlyItsDay() {
        let item = event("Robotics", date(13, 7, 15), date(13, 8))
        #expect(PersonalEventDays.days(for: item, calendar: calendar) == ["2026-10-13"])
        #expect(PersonalEventDays.span(of: item, on: "2026-10-13", calendar: calendar)
            == .timed(start: date(13, 7, 15), end: date(13, 8)))
    }

    /// EventKit ends an all-day event at the next midnight or at 23:59:59;
    /// neither reaches the following day.
    @Test func allDayEventsEndOnTheirLastDay() {
        let midnight = event("Fall break", date(9), date(13), allDay: true)
        let lateNight = event("Field trip", date(9), date(9, 23, 59).addingTimeInterval(59), allDay: true)
        #expect(PersonalEventDays.days(for: midnight, calendar: calendar)
            == ["2026-10-09", "2026-10-10", "2026-10-11", "2026-10-12"])
        #expect(PersonalEventDays.days(for: lateNight, calendar: calendar) == ["2026-10-09"])
        #expect(PersonalEventDays.span(of: midnight, on: "2026-10-11", calendar: calendar) == .allDay)
    }

    @Test func multiDayTimedEventStartsContinuesAndEnds() {
        let trip = event("Robotics regional", date(16, 15), date(18, 11))
        #expect(PersonalEventDays.days(for: trip, calendar: calendar)
            == ["2026-10-16", "2026-10-17", "2026-10-18"])
        #expect(PersonalEventDays.span(of: trip, on: "2026-10-16", calendar: calendar) == .starts(date(16, 15)))
        #expect(PersonalEventDays.span(of: trip, on: "2026-10-17", calendar: calendar) == .allDay)
        #expect(PersonalEventDays.span(of: trip, on: "2026-10-18", calendar: calendar) == .ends(date(18, 11)))
    }

    @Test func timedEventEndingAtMidnightDoesNotReachTheNextDay() {
        let evening = event("Concert", date(13, 19), date(14))
        #expect(PersonalEventDays.days(for: evening, calendar: calendar) == ["2026-10-13"])
        #expect(PersonalEventDays.span(of: evening, on: "2026-10-13", calendar: calendar)
            == .timed(start: date(13, 19), end: date(14)))
        let overnight = event("Lock-in", date(13, 20), date(15))
        #expect(PersonalEventDays.days(for: overnight, calendar: calendar) == ["2026-10-13", "2026-10-14"])
        #expect(PersonalEventDays.span(of: overnight, on: "2026-10-14", calendar: calendar) == .allDay)
    }

    @Test func zeroLengthAndInvertedEventsStayOnTheirStartDay() {
        let moment = event("Deadline", date(13, 23, 59), date(13, 23, 59))
        let inverted = event("Bad data", date(13, 9), date(12, 9))
        #expect(PersonalEventDays.days(for: moment, calendar: calendar) == ["2026-10-13"])
        #expect(PersonalEventDays.days(for: inverted, calendar: calendar) == ["2026-10-13"])
    }

    @Test func runawayEventIsBounded() {
        let endless = event("Semester", date(1), date(1, month: 12).addingTimeInterval(86_400 * 365), allDay: true)
        #expect(PersonalEventDays.days(for: endless, calendar: calendar).count == PersonalEventDays.maximumDays)
    }

    @Test func dayOrderIsAllDayThenUnderWayThenByStart() {
        let events = [
            event("Orthodontist", date(13, 16, 30), date(13, 17, 15)),
            event("Robotics build", date(13, 7, 15), date(13, 8)),
            event("Overnight ends", date(12, 20), date(13, 9)),
            event("First day of Q2", date(13), date(14), allDay: true),
            event("A same time", date(13, 7, 15), date(13, 9), id: "a"),
        ]
        let index = PersonalEventDays.index(events, calendar: calendar)
        #expect(index["2026-10-13"]?.map(\.title)
            == ["First day of Q2", "Overnight ends", "A same time", "Robotics build", "Orthodontist"])
        #expect(index["2026-10-12"]?.map(\.title) == ["Overnight ends"])
    }

    @Test func repeatingOccurrencesHaveDistinctIDs() {
        let first = event("Practice", date(13, 16), date(13, 17), id: "series")
        let second = event("Practice", date(20, 16), date(20, 17), id: "series")
        #expect(first.id != second.id)
        #expect(first.eventIdentifier == second.eventIdentifier)
    }


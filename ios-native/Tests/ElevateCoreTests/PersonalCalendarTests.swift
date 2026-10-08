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

    /// Calendars are opt-in: nothing shows until the person turns it on.
    @Test func selectionStartsWithEveryCalendarHidden() {
        var selection = PersonalCalendarSelection()
        let school = info("school", "Eanes Events", account: "Gmail")
        let birthdays = info("birthdays", "Birthdays", account: "Other", hidden: true)
        #expect(!selection.isShown(school))
        #expect(!selection.isShown(birthdays))

        selection.setShown(true, for: school)
        #expect(selection.isShown(school))
        #expect(!selection.isShown(birthdays))
        selection.setShown(false, for: school)
        #expect(!selection.isShown(school))
    }

    @Test func selectionRoundTripsAndToleratesMissingFields() throws {
        var selection = PersonalCalendarSelection()
        selection.setShown(true, for: info("a", "A", account: "iCloud"))
        selection.dismissedPrompt = true
        let data = try JSONEncoder().encode(selection)
        #expect(try JSONDecoder().decode(PersonalCalendarSelection.self, from: data) == selection)

        let empty = try JSONDecoder().decode(PersonalCalendarSelection.self, from: Data("{}".utf8))
        #expect(empty == PersonalCalendarSelection())
        // An opt-out list from the first version is ignored, not inverted.
        let legacy = try JSONDecoder().decode(PersonalCalendarSelection.self, from: Data(#"{"hiddenIDs":["a"]}"#.utf8))
        #expect(legacy.shownIDs.isEmpty)
        #expect(PersonalCalendarSelection.storageKey.hasSuffix("v2"))
    }

    @Test func oversizedStoredSelectionIsRejected() {
        let ids = (0...PersonalCalendarSelection.maximumIDs).map { "\"id\($0)\"" }.joined(separator: ",")
        let json = Data("{\"shownIDs\":[\(ids)]}".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PersonalCalendarSelection.self, from: json)
        }
    }

    @Test func groupsSortAccountsAndCalendarsByName() {
        let groups = PersonalCalendarGroup.groups([
            info("3", "Personal", account: "iCloud"),
            info("1", "Robotics", account: "Gmail"),
            info("2", "Eanes Events", account: "Gmail"),
            info("4", "Untitled", account: "  "),
        ])
        #expect(groups.map(\.title) == ["Gmail", "iCloud", "Other"])
        #expect(groups.first?.calendars.map(\.title) == ["Eanes Events", "Robotics"])
    }

    @Test func monthIntervalCoversExactlyTheMonth() throws {
        let interval = try #require(PersonalEventDays.monthInterval(year: 2026, month: 12, calendar: calendar))
        #expect(interval.start == date(1, month: 12))
        #expect(PersonalEventDays.iso(interval.end, calendar: calendar) == "2027-01-01")
    }

    @Test func detailsBoundNotesAndOpenOnlyWebLinks() {
        let item = event("Study", date(13, 16), date(13, 17))
        let long = String(repeating: "a", count: PersonalEventDetails.maximumNotes + 10)
        let details = PersonalEventDetails(event: item, notes: "  \n" + long, url: URL(string: "https://example.com/meet"))
        #expect(details.notes?.count == PersonalEventDetails.maximumNotes)
        #expect(details.url?.host() == "example.com")
        #expect(PersonalEventDetails(event: item, notes: " \n ", url: URL(string: "javascript:alert(1)")).notes == nil)
        #expect(PersonalEventDetails(event: item, url: URL(string: "javascript:alert(1)")).url == nil)
        #expect(PersonalEventDetails(event: item, url: URL(string: "file:///etc/hosts")).url == nil)
        #expect(details.calendarAppURL?.scheme == "calshow")
    }

    /// The grid keys days by Gregorian school dates; an iPhone set to
    /// another calendar system must still place events on the same days.
    @Test func dayCalendarIsGregorianRegardlessOfSystemCalendar() {
        #expect(PersonalEventDays.dayCalendar.identifier == .gregorian)
        let item = event("Robotics", date(13, 7), date(13, 8))
        #expect(PersonalEventDays.days(for: item, calendar: calendar) == ["2026-10-13"])
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = calendar.timeZone
        #expect(PersonalEventDays.iso(item.start, calendar: japanese) != "2026-10-13")
    }

    /// An event that began long before the month on screen still marks
    /// every overlapping day of that month.
    @Test func longEventMarksTheQueriedMonth() throws {
        let semester = event("Fall sports season", date(1, month: 8), date(1, month: 12), allDay: true)
        let october = try #require(PersonalEventDays.monthInterval(year: 2026, month: 10, calendar: calendar))
        let index = PersonalEventDays.index([semester], calendar: calendar, within: october)
        #expect(index.count == 31)
        #expect(index["2026-10-01"]?.first?.title == "Fall sports season")
        #expect(index["2026-10-31"] != nil)
        #expect(index["2026-09-30"] == nil && index["2026-11-01"] == nil)
        #expect(PersonalEventDays.span(of: semester, on: "2026-10-15", calendar: calendar) == .allDay)
    }

    @Test func detailsKeepAStableIDAcrossEdits() {
        let before = event("Study", date(13, 16), date(13, 17), id: "series")
        let after = event("Study moved", date(14, 9), date(14, 10), id: "series")
        #expect(PersonalEventDetails(event: before).id == PersonalEventDetails(event: after).id)
    }
}

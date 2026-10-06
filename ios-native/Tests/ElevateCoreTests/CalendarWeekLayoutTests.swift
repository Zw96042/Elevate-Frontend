import Foundation
import Testing
@testable import ElevateCore

@Suite struct CalendarWeekLayoutTests {
    private var calendar: Calendar { PersonalEventDays.dayCalendar }

    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> PersonalEvent {
        PersonalEvent(eventIdentifier: id, calendarID: "cal", title: id, location: nil,
                      start: start, end: end, isAllDay: allDay)
    }

    /// Sunday October 11 through Saturday October 17, 2026.
    private var week: [CalendarDay] { (11...17).map { CalendarDay(year: 2026, month: 10, day: $0) } }

    private func layout(_ events: [PersonalEvent]) -> CalendarWeekLayout {
        CalendarWeekLayout(days: week, eventsByDay: PersonalEventDays.index(events, calendar: calendar))
    }

    @Test func multiDayEventIsOneSpanAcrossItsColumns() throws {
        let trip = event("trip", date(13, 15), date(15, 12))
        let span = try #require(layout([trip]).spans.first)
        #expect(span.startColumn == 2 && span.endColumn == 4)
        #expect(span.isMultiDay && !span.continuesBefore && !span.continuesAfter)
        #expect(span.lane == 0)
    }

    @Test func spansCrossingTheWeekEdgesSayTheyContinue() throws {
        let breakWeek = event("break", date(9), date(13), allDay: true)
        let season = event("season", date(16), date(20), allDay: true)
        let spans = layout([breakWeek, season]).spans
        let first = try #require(spans.first { $0.event.eventIdentifier == "break" })
        let second = try #require(spans.first { $0.event.eventIdentifier == "season" })
        #expect(first.startColumn == 0 && first.endColumn == 1 && first.continuesBefore && !first.continuesAfter)
        #expect(second.startColumn == 5 && second.endColumn == 6 && second.continuesAfter)
        // They don't overlap, so they share the top lane.
        #expect(first.lane == 0 && second.lane == 0)
    }

    @Test func overlappingEventsStackInLanesWithMultiDayOnTop() {
        let trip = event("trip", date(12), date(15), allDay: true)
        let practice = event("practice", date(13, 16), date(13, 17))
        let dinner = event("dinner", date(13, 19), date(13, 20))
        let result = layout([practice, dinner, trip])
        let lanes = Dictionary(uniqueKeysWithValues: result.spans.map { ($0.event.eventIdentifier, $0.lane) })
        #expect(lanes["trip"] == 0)
        #expect(lanes["practice"] == 1)
        #expect(lanes["dinner"] == 2)
        #expect(result.laneDepth == 3)
    }

    @Test func eventsBeyondTheShownLanesAreCountedPerColumn() {
        let events = (0..<5).map { event("e\($0)", date(14, 8 + $0), date(14, 9 + $0)) }
        let result = layout(events)
        #expect(result.visibleSpans(lanes: 3).count == 3)
        #expect(result.hiddenCount(column: 3, lanes: 3) == 2)
        #expect(result.hiddenCount(column: 2, lanes: 3) == 0)
        #expect(result.dayEvents[3].count == 5)
    }

    @Test func densityStepsInOrder() {
        #expect(CalendarDensity.compact.denser == .bars)
        #expect(CalendarDensity.details.denser == nil)
        #expect(CalendarDensity.compact.sparser == nil)
        #expect(CalendarDensity.compact.laneCount == 0)
        #expect(CalendarDensity.details.laneCount > CalendarDensity.bars.laneCount)
    }

    @Test func gradedAssignmentsCountAsDoneUnlessMarkedMissing() {
        let course = UnifiedCourseData(corNumId: "c", stuId: "synthetic", section: "1", gbId: "book",
            courseName: "Synthetic course", semester: .both, termLength: "", gradeYear: 12,
            currentScores: [], historicalGrades: .init())
        let info = GradeInfoResult(course: "Synthetic", instructor: "", litName: "TERM 1", gradebook: [
            .init(category: "Daily", assignments: [
                GradeInfoAssignment(date: "10/13/26", name: "Graded", score: 95, pointsEarned: 19, pointsTotal: 20, meta: []),
                GradeInfoAssignment(date: "10/13/26", name: "Ungraded", meta: []),
                GradeInfoAssignment(date: "10/13/26", name: "Missing zero", score: 0, pointsEarned: 0, pointsTotal: 20,
                                    meta: [.init(type: "missing", note: "Missing")]),
            ]),
        ])
        let rows = CalendarAssignment.sourceAssignments(course: course, term: .q2, gradeInfo: info)
        #expect(rows.map(\.isDoneByGrade) == [true, false, false])
        #expect(rows.map(\.isGraded) == [true, false, true])
    }
}

@Suite struct CalendarSnapshotTests {
    private let course = UnifiedCourseData(corNumId: "c", stuId: "synthetic", section: "1", gbId: "book",
        courseName: "Synthetic course", semester: .both, termLength: "", gradeYear: 12,
        currentScores: [], historicalGrades: .init())

    private func assignments(_ dates: [String]) -> [CalendarAssignment] {
        let info = GradeInfoResult(course: "Synthetic", instructor: "", litName: "TERM 2", gradebook: [
            .init(category: "Daily", assignments: dates.enumerated().map { index, date in
                GradeInfoAssignment(date: date, name: "Work \(index)", score: index.isMultiple(of: 2) ? 90 : nil, meta: [])
            }),
        ])
        return CalendarAssignment.sourceAssignments(course: course, term: .q2, gradeInfo: info)
    }

    @Test func levelsCountEveryAssignmentDueGradedOrNot() throws {
        let rows = assignments(["10/13/26", "10/13/26", "10/13/26", "10/14/26", "No date"])
        let snapshot = CalendarSnapshot(assignments: rows, attendance: [], eventsByDay: [:], weeks: [])
        let tuesday = try #require(CalendarDay(iso: "2026-10-13"))
        let wednesday = try #require(CalendarDay(iso: "2026-10-14"))
        #expect(snapshot.level(tuesday) == 3)
        #expect(snapshot.level(wednesday) == 1)
        #expect(snapshot.level(try #require(CalendarDay(iso: "2026-10-15"))) == 0)
        #expect(snapshot.index.undatedAssignments.count == 1)
    }

    @Test func eventsAndAttendanceNeverChangeTheShade() throws {
        let day = try #require(CalendarDay(iso: "2026-10-13"))
        let calendar = PersonalEventDays.dayCalendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9))!
        let event = PersonalEvent(eventIdentifier: "e", calendarID: "c", title: "Practice", location: nil,
                                  start: start, end: start.addingTimeInterval(3600), isAllDay: false)
        let record = AttendanceRecord(id: "a", date: "2026-10-13", attendance: "Tardy", period: "1",
                                      courseName: nil, granularity: .period)
        let week = CalendarWeek.containing(day, calendar: calendar)
        let snapshot = CalendarSnapshot(assignments: [], attendance: [record],
                                        eventsByDay: PersonalEventDays.index([event], calendar: calendar), weeks: [week])
        #expect(snapshot.level(day) == 0)
        #expect(snapshot.hasAttendance(day))
        #expect(snapshot.layout(for: week).spans.count == 1)
        #expect(snapshot.events(on: day).count == 1)
    }
}

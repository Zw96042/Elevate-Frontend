import Foundation
import Testing
@testable import ElevateCore

@Suite struct SchoolWeekTests {
    @Test func upcomingSourcesKeepMissingUndatedAndDuplicateRowsDistinct() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-04T19:00:00Z"))
        let course = UnifiedCourseData(corNumId: "c", stuId: "synthetic", section: "1", gbId: "book",
            courseName: "Synthetic course", semester: .both, termLength: "", gradeYear: 12,
            currentScores: [], historicalGrades: .init())
        let assignments = [
            GradeInfoAssignment(date: "10/4/26", name: "Zero grade", score: 0, meta: []),
            GradeInfoAssignment(date: "10/10/26", name: "End of window", meta: []),
            GradeInfoAssignment(date: "10/11/26", name: "After window", meta: []),
            GradeInfoAssignment(date: "9/30/26", name: "Explicit missing", meta: [.init(type: "missing", note: "Missing")]),
            GradeInfoAssignment(date: "No date", name: "Undated", meta: []),
            GradeInfoAssignment(date: "10/5/26", name: "Duplicate", meta: []),
            GradeInfoAssignment(date: "10/5/26", name: "Duplicate", meta: []),
        ]
        let info = GradeInfoResult(course: "Synthetic", instructor: "", litName: "TERM 3",
            gradebook: [.init(category: "Daily", assignments: assignments)])
        let rows = CalendarAssignment.sourceAssignments(course: course, term: .q1, gradeInfo: info)
        let data = SchoolCalendarData(term: .q1, assignments: rows, updatedAt: now)
        // An absolute reminder just after midnight UTC still belongs to the preceding school day.
        let fireDate = try #require(ISO8601DateFormatter().date(from: "2026-10-05T01:00:00Z"))
        let reminder = LocalReminder(courseID: course.id, term: .q1, title: "Study", courseName: course.courseName, fireDate: fireDate)
        let plan = SchoolWeekPlan(data: data, reminders: [reminder], now: now)
        #expect(plan.days.first?.assignments.map(\.title) == ["Zero grade"])
        #expect(plan.days.first?.reminders.count == 1)
        #expect(plan.days.last?.assignments.map(\.title) == ["End of window"])
        #expect(!plan.days.flatMap(\.assignments).contains { $0.title == "After window" })
        #expect(plan.missing.map(\.title) == ["Explicit missing"])
        #expect(plan.undated.map(\.title) == ["Undated"])
        #expect(plan.ambiguousAssignmentIDs.count == 2)
        #expect(Set(plan.days.flatMap(\.assignments).map(\.id)).count == 4)
    }

    /// Synthetic rows: missing due today (also in Today), missing from last
    /// week, missing undated (also undated), due later, undated, after the
    /// window, and two identical rows.
    private func doneFixture() throws -> (data: SchoolCalendarData, now: Date, ids: [String: String]) {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-05T15:00:00Z"))
        let course = UnifiedCourseData(corNumId: "c", stuId: "synthetic", section: "1", gbId: "book",
            courseName: "Synthetic course", semester: .both, termLength: "", gradeYear: 12,
            currentScores: [], historicalGrades: .init())
        let missing: [AssignmentMeta] = [.init(type: "missing", note: "Missing")]
        let info = GradeInfoResult(course: "Synthetic", instructor: "", litName: "TERM 1",
            gradebook: [.init(category: "Daily", assignments: [
                GradeInfoAssignment(date: "10/5/26", name: "Missing today", meta: missing),
                GradeInfoAssignment(date: "9/28/26", name: "Missing earlier", meta: missing),
                GradeInfoAssignment(date: "No date", name: "Missing undated", meta: missing),
                GradeInfoAssignment(date: "10/7/26", name: "Due later", meta: []),
                GradeInfoAssignment(date: "No date", name: "Undated", meta: []),
                GradeInfoAssignment(date: "10/20/26", name: "After window", meta: []),
                GradeInfoAssignment(date: "10/6/26", name: "Twin", meta: []),
                GradeInfoAssignment(date: "10/6/26", name: "Twin", meta: []),
            ])])
        let rows = CalendarAssignment.sourceAssignments(course: course, term: .q1, gradeInfo: info)
        let ids = Dictionary(rows.map { ($0.title, $0.id) }) { first, _ in first }
        return (SchoolCalendarData(term: .q1, assignments: rows, updatedAt: now), now, ids)
    }

    @Test func doneMovesWorkOutOfEveryActiveGroupOnce() throws {
        let (data, now, ids) = try doneFixture()
        let marked = Set(["Missing today", "Missing earlier", "Missing undated", "Due later", "Undated", "After window"]
            .compactMap { ids[$0] })
        let plan = SchoolWeekPlan(data: data, reminders: [], completedIDs: marked, now: now)
        #expect(plan.missing.isEmpty)
        #expect(plan.undated.isEmpty)
        #expect(plan.days.flatMap(\.assignments).map(\.title) == ["Twin", "Twin"])
        // Each Done assignment once, by due day, undated last; work outside
        // every active group isn't listed.
        #expect(plan.done.map(\.title) == ["Missing earlier", "Missing today", "Due later", "Missing undated", "Undated"])
        #expect(Set(plan.done.map(\.id)).count == plan.done.count)
        #expect(plan.doneDueCount == 2)
        // Skyward's Missing flag is untouched by a personal mark.
        #expect(plan.done.first { $0.title == "Missing today" }?.meta.contains { $0.type == "missing" } == true)

        let restored = SchoolWeekPlan(data: data, reminders: [], completedIDs: [], now: now)
        #expect(restored.done.isEmpty && restored.doneDueCount == 0)
        #expect(restored.missing.map(\.title) == ["Missing earlier", "Missing today", "Missing undated"])
        #expect(restored.undated.map(\.title) == ["Missing undated", "Undated"])
        #expect(restored.days.first?.assignments.map(\.title) == ["Missing today"])
    }

    @Test func ambiguousRowsIgnoreDoneMarks() throws {
        let (data, now, _) = try doneFixture()
        let twins = data.assignments.filter { $0.title == "Twin" }.map(\.id)
        let plan = SchoolWeekPlan(data: data, reminders: [], completedIDs: Set(twins), now: now)
        #expect(plan.ambiguousAssignmentIDs == Set(twins))
        #expect(plan.done.isEmpty && plan.doneDueCount == 0)
        #expect(plan.days.flatMap(\.assignments).filter { $0.title == "Twin" }.count == 2)
    }


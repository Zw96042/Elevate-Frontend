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

    @Test func remindersStayIndependentOfDone() throws {
        let (data, now, ids) = try doneFixture()
        let later = try #require(ids["Due later"])
        let earlier = try #require(ids["Missing earlier"])
        let course = try #require(data.assignments.first).course
        let fire = try #require(ISO8601DateFormatter().date(from: "2026-10-06T23:00:00Z"))
        let linked = LocalReminder(courseID: course.id, term: .q1, assignmentID: later, title: "Due later",
                                   courseName: course.courseName, fireDate: fire)
        let missingLinked = LocalReminder(courseID: course.id, term: .q1, assignmentID: earlier, title: "Missing earlier",
                                          courseName: course.courseName, fireDate: fire)
        let otherTerm = LocalReminder(courseID: course.id, term: .q2, assignmentID: later, title: "Other quarter",
                                      courseName: course.courseName, fireDate: fire)
        let standalone = LocalReminder(courseID: course.id, term: .q1, title: "Study", courseName: course.courseName, fireDate: fire)
        let reminders = [linked, missingLinked, otherTerm, standalone]

        let plan = SchoolWeekPlan(data: data, reminders: reminders, completedIDs: [later, earlier], now: now)
        let day = try #require(plan.days.first { $0.id == "2026-10-06" })
        // Every reminder remains in the week; none is dropped by a Done mark.
        #expect(Set(day.reminders.map(\.id)) == Set(reminders.map(\.id)))
        #expect(plan.doneReminders[later]?.map(\.id) == [linked.id])
        #expect(plan.doneReminders[earlier]?.map(\.id) == [missingLinked.id])
        #expect(Set(plan.shownReminders(on: day).map(\.id)) == [otherTerm.id, standalone.id])

        // A stricter link keeps an unmatched reminder standalone.
        let strict = SchoolWeekPlan(data: data, reminders: reminders, completedIDs: [later], now: now) { _, _ in false }
        let strictDay = try #require(strict.days.first { $0.id == "2026-10-06" })
        #expect(strict.doneReminders.isEmpty)
        #expect(strict.shownReminders(on: strictDay).count == 4)

        let undone = SchoolWeekPlan(data: data, reminders: reminders, now: now)
        let undoneDay = try #require(undone.days.first { $0.id == "2026-10-06" })
        #expect(undone.doneReminders.isEmpty)
        #expect(undone.shownReminders(on: undoneDay).count == 4)
    }

    @Test func schoolWeekUsesLocalDatesAcrossDSTAndYear() throws {
        let parser = ISO8601DateFormatter()
        let spring = SchoolWeek.containing(try #require(parser.date(from: "2026-03-08T08:30:00Z")))
        #expect(spring.firstDay == "2026-03-02")
        #expect(spring.lastDay == "2026-03-08")
        #expect(Set(spring.days).count == 7)
        let upcoming = SchoolWeek.upcoming(from: try #require(parser.date(from: "2026-03-07T19:00:00Z")))
        #expect(upcoming.firstDay == "2026-03-07")
        #expect(upcoming.lastDay == "2026-03-13")
        #expect(Set(upcoming.days).count == 7)
        let newYear = SchoolWeek.containing(try #require(parser.date(from: "2027-01-01T19:00:00Z")))
        #expect(newYear.firstDay == "2026-12-28")
        #expect(newYear.lastDay == "2027-01-03")
    }
    @Test func completionIsPersonalPersistentAndAccountScoped() throws {
        let name = "completion-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let a = AssignmentCompletionStore(accountIdentifier: "a", defaults: defaults)
        #expect(!a.setCompleted(true, id: "assignment", expectedAccountIdentifier: "b"))
        #expect(a.setCompleted(true, id: "assignment", expectedAccountIdentifier: "a"))
        #expect(AssignmentCompletionStore(accountIdentifier: "a", defaults: defaults).isCompleted("assignment"))
        #expect(!AssignmentCompletionStore(accountIdentifier: "b", defaults: defaults).isCompleted("assignment"))
        #expect(a.setCompleted(false, id: "assignment", expectedAccountIdentifier: "a"))
        #expect(!a.isCompleted("assignment"))
        defaults.set(Data("broken".utf8), forKey: "account.a.assignmentCompletion.v1")
        let corrupt = AssignmentCompletionStore(accountIdentifier: "a", defaults: defaults)
        #expect(corrupt.storageUnavailable)
        #expect(!corrupt.setCompleted(true, id: "assignment", expectedAccountIdentifier: "a"))
        #expect(defaults.data(forKey: "account.a.assignmentCompletion.v1") == Data("broken".utf8))
        corrupt.clear()
        #expect(corrupt.setCompleted(true, id: "assignment", expectedAccountIdentifier: "a"))
        AssignmentCompletionStore.remove(accountIdentifier: "a", defaults: defaults)
        #expect(AssignmentCompletionStore(accountIdentifier: "a", defaults: defaults).completed.isEmpty)
    }
    @Test func wrongTypedCompletionStorageIsPreserved() throws {
        let name = "completion-type-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let key = "account.a.assignmentCompletion.v1"
        defaults.set("unexpected", forKey: key)
        let store = AssignmentCompletionStore(accountIdentifier: "a", defaults: defaults)
        #expect(store.storageUnavailable)
        #expect(!store.setCompleted(true, id: "one", expectedAccountIdentifier: "a"))
        #expect(defaults.string(forKey: key) == "unexpected")
    }

    @Test func completionByteLimitPreservesReadableExistingMarks() throws {
        let name = "completion-limit-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var marks: [String: Date] = [:]
        let longID = String(repeating: "a", count: 8_180)
        var saved = Data()
        for index in 0..<300 {
            let nextID = "\(index)-\(longID)"
            var next = marks
            next[nextID] = Date(timeIntervalSince1970: 1_000)
            let data = try JSONEncoder().encode(next)
            if data.count > 2_000_000 { break }
            marks = next
            saved = data
        }
        let key = "account.a.assignmentCompletion.v1"
        defaults.set(saved, forKey: key)
        let store = AssignmentCompletionStore(accountIdentifier: "a", defaults: defaults)
        #expect(!store.storageUnavailable)
        #expect(!store.setCompleted(true, id: "new-\(longID)", expectedAccountIdentifier: "a"))
        #expect(defaults.data(forKey: key) == saved)
        let reloaded = AssignmentCompletionStore(accountIdentifier: "a", defaults: defaults)
        #expect(!reloaded.storageUnavailable && reloaded.completed == marks)
    }

}

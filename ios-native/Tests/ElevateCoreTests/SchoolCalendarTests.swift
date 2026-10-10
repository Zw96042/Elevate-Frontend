import Foundation
import Testing
@testable import ElevateCore

@Suite("School calendar source assignments")
struct SchoolCalendarTests {
    @Test("School dates normalize strict components without timezone conversion")
    func dates() {
        let valid = ["9/16/26": "2026-09-16", "09/16/2026": "2026-09-16",
                     "2026-09-16": "2026-09-16", "Wed Sep 16, 2026": "2026-09-16",
                     "2/29/00": "2000-02-29", " 2/29/24 ": "2024-02-29", "12/31/99": "2099-12-31"]
        for (source, expected) in valid { #expect(SchoolCalendarDate.normalize(source) == expected) }
        for source in ["", "No date", "2/29/26", "2/29/1900", "2/30/24", "13/1/26", "9/0/26",
                       "9/16/6", "9/16/026", "9/16/26 11:59 PM", "009/16/26", "9/16/-26",
                       "2026-9-16", "2026-09-16T00:00:00Z", "９/16/26"] {
            #expect(SchoolCalendarDate.normalize(source) == nil)
        }
    }

    @Test("Only current live identities in the requested quarter are eligible")
    func eligibility() {
        let fall = course("fall", semester: .fall)
        let spring = course("spring", semester: .spring)
        let full = course("full", semester: .both)
        let unknown = course("unknown", semester: .unknown)
        var archived = course("past", semester: .both)
        archived.gradeYear = 11
        var noParams = course("transcript", semester: .both)
        noParams.gbId = ""
        let all = [fall, spring, full, unknown, archived, noParams, fall]
        #expect(SchoolCalendar.eligibleCourses(all, term: .q1).map(\.id) == [fall.id, full.id, unknown.id])
        #expect(SchoolCalendar.eligibleCourses(all, term: .q4).map(\.id) == [spring.id, full.id, unknown.id])
        #expect(SchoolCalendar.eligibleCourses(all, term: .sm1).isEmpty)
        #expect(SchoolCalendar.quarter(for: .sm1) == .q2)
        #expect(SchoolCalendar.quarter(for: .sm2) == .q4)
        var currentUnknown = full
        currentUnknown.gradeYear = nil
        #expect(SchoolCalendar.eligibleCourses([currentUnknown], term: .q2) == [currentUnknown])
        #expect(SchoolCalendar.params(course: spring, term: .q3).gbId == spring.gbId)
        #expect(SchoolCalendar.params(course: spring, term: .q3).bucket == "TERM 9")
    }

    @Test("Occurrences retain duplicate names and source-only status without inferring missing")
    func occurrencesAndMetadata() throws {
        let live = course("live", semester: .both)
        let source = info([
            assignment("Practice", date: "9/16/26", score: 0),
            assignment("Practice", date: "9/16/26", score: nil),
            assignment("Source absent", date: "9/16/26", meta: [.init(type: "absent", note: "Absent")]),
            assignment("Source missing", date: "9/16/26", meta: [.init(type: "missing", note: "Missing")]),
            assignment("Source no count", date: "", meta: [.init(type: "noCount", note: "No count")]),
            assignment("Bad date", date: "2/30/26"),
        ])
        let rows = CalendarAssignment.sourceAssignments(course: live, term: .q1, gradeInfo: source)
        #expect(rows.count == 6)
        #expect(Set(rows.map(\.id)).count == 6)
        #expect(Set(rows.map(\.routeID)).count == 6)
        #expect(rows.map(\.routeID) == CalendarAssignment.sourceAssignments(course: live, term: .q1, gradeInfo: source).map(\.routeID))
        #expect(rows[0].meta.isEmpty && rows[1].meta.isEmpty)
        #expect(rows[2].meta == source.gradebook[0].assignments[2].meta)
        #expect(rows[2].meta.allSatisfy { $0.type != "missing" })
        #expect(rows[3].meta.first?.type == "missing")
        #expect(rows[4].sourceDate == "" && rows[4].date == nil)
        #expect(rows[5].sourceDate == "2/30/26" && rows[5].date == nil)
        let data = SchoolCalendarData(term: .q1, assignments: rows, updatedAt: nil)
        #expect(data.undatedCount == 2)
        #expect(rows == CalendarAssignment.sourceAssignments(course: live, term: .q1, gradeInfo: source))
        var reordered = source
        reordered.gradebook[0].assignments.reverse()
        #expect(Set(rows.map(\.id)) == Set(CalendarAssignment.sourceAssignments(course: live, term: .q1, gradeInfo: reordered).map(\.id)))
        let otherCourse = CalendarAssignment.sourceAssignments(course: course("other", semester: .both), term: .q1, gradeInfo: source)
        let otherQuarter = CalendarAssignment.sourceAssignments(course: live, term: .q2, gradeInfo: source)
        #expect(Set(rows.map(\.id)).isDisjoint(with: otherCourse.map(\.id)))
        #expect(Set(rows.map(\.id)).isDisjoint(with: otherQuarter.map(\.id)))
    }

    @Test("Coverage distinguishes a verified empty course from failure and uses saved timestamps")
    func coverage() {
        let old = Date(timeIntervalSince1970: 100)
        let fresh = Date(timeIntervalSince1970: 200)
        let first = course("first", semester: .both)
        let second = course("second", semester: .both)
        let third = course("third", semester: .both)
        let rows = CalendarAssignment.sourceAssignments(course: second, term: .q1, gradeInfo: info([assignment("Saved", date: "9/16/26")]))
        let data = SchoolCalendarData(term: .q1, snapshots: [
            .init(course: first, assignments: [], updatedAt: fresh, isResolved: true, didFail: false),
            .init(course: second, assignments: rows, updatedAt: old, isResolved: true, didFail: true),
            .init(course: third, assignments: [], updatedAt: nil, isResolved: false, didFail: true),
        ])
        #expect(data.updatedAt == old)
        #expect(data.eligibleCourseCount == 3)
        #expect(data.resolvedCourseCount == 2)
        #expect(data.failedCourseNames == [second.courseName, third.courseName])
        #expect(data.assignments == rows)
        #expect(data.courseUpdatedAt[second.id] == old)
        let unknownTimestamp = SchoolCalendarData(term: .q1, snapshots: [
            .init(course: first, assignments: [], updatedAt: nil, isResolved: true, didFail: false),
        ])
        #expect(unknownTimestamp.updatedAt == nil)
    }

    private func course(_ key: String, semester: Semester) -> UnifiedCourseData {
        UnifiedCourseData(corNumId: key, stuId: "synthetic", section: "section-\(key)", gbId: "book-\(key)",
            courseName: "Course \(key)", semester: semester, termLength: "", gradeYear: 12,
            currentScores: [], historicalGrades: HistoricalGrades())
    }

    private func assignment(_ title: String, date: String, score: Double? = nil,
                            meta: [AssignmentMeta] = []) -> GradeInfoAssignment {
        GradeInfoAssignment(date: date, name: title, score: score, meta: meta)
    }

    private func info(_ assignments: [GradeInfoAssignment]) -> GradeInfoResult {
        GradeInfoResult(course: "Synthetic", instructor: "", litName: "TERM 3",
                        gradebook: [GradeCategory(category: "Assignments", assignments: assignments)])
    }
}

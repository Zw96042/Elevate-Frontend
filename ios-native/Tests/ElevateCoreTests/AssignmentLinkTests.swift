import Foundation
import Testing
@testable import ElevateCore

@Suite("Assignment links and future quarters")
struct AssignmentLinkTests {
    private let scope = String(repeating: "a", count: 24)
    private let courseID = String(repeating: "b", count: 64)
    private let assignmentID = String(repeating: "c", count: 64)

    private func link(term: TermLabel = .q2) -> URL {
        var components = URLComponents()
        components.scheme = "com.zacharywilson.elevate"
        components.host = "assignment"
        components.queryItems = [
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "courseID", value: courseID),
            URLQueryItem(name: "term", value: term.rawValue),
            URLQueryItem(name: "assignmentID", value: assignmentID),
        ]
        return components.url!
    }

    @Test("Only complete opaque account and quarter links are accepted")
    func validLinks() throws {
        let parsed = try #require(AssignmentLink(url: link()))
        #expect(parsed.scope == scope)
        #expect(parsed.courseID == courseID)
        #expect(parsed.term == .q2)
        #expect(parsed.assignmentID == assignmentID)
        #expect(AssignmentLink(url: link(term: .sm1)) == nil)
        #expect(AssignmentLink(url: link(term: .sm2)) == nil)
        var components = URLComponents(url: link(), resolvingAgainstBaseURL: false)!
        components.queryItems?[0].value = "sample"
        #expect(AssignmentLink(url: components.url!)?.scope == "sample")
    }

    @Test("Malformed, duplicate, private composite and unrelated links are rejected")
    func invalidLinks() {
        for key in ["scope", "courseID", "term", "assignmentID"] {
            var components = URLComponents(url: link(), resolvingAgainstBaseURL: false)!
            let original = components.queryItems!.first { $0.name == key }!
            components.queryItems!.append(original)
            #expect(AssignmentLink(url: components.url!) == nil)
            components.queryItems!.removeAll { $0.name == key }
            #expect(AssignmentLink(url: components.url!) == nil)
        }
        for (key, value) in [("scope", "student@example.test"), ("courseID", "stu|course|private"),
                             ("assignmentID", "private title:date:0"), ("assignmentID", ""),
                             ("assignmentID", String(repeating: "g", count: 64)), ("term", "unknown")] {
            var components = URLComponents(url: link(), resolvingAgainstBaseURL: false)!
            components.queryItems = components.queryItems!.map {
                $0.name == key ? URLQueryItem(name: key, value: value) : $0
            }
            #expect(AssignmentLink(url: components.url!) == nil)
        }
        var components = URLComponents(url: link(), resolvingAgainstBaseURL: false)!
        components.queryItems!.append(URLQueryItem(name: "extra", value: "1"))
        #expect(AssignmentLink(url: components.url!) == nil)
        components = URLComponents(url: link(), resolvingAgainstBaseURL: false)!
        components.host = "courses"
        #expect(AssignmentLink(url: components.url!) == nil)
        components.host = "assignment"
        components.scheme = "https"
        #expect(AssignmentLink(url: components.url!) == nil)
        components.scheme = "com.zacharywilson.elevate"
        components.path = "/other"
        #expect(AssignmentLink(url: components.url!) == nil)
        components.path = ""
        components.fragment = "other"
        #expect(AssignmentLink(url: components.url!) == nil)
    }

    @Test("Opaque source tokens preserve identity without carrying private source text")
    func tokens() {
        let source = "synthetic course|Quarter 2|Synthetic assignment:0"
        let token = AssignmentLink.assignmentToken(for: source)
        #expect(token.count == 64)
        #expect(token == AssignmentLink.assignmentToken(for: source))
        #expect(token != AssignmentLink.assignmentToken(for: source + "1"))
        #expect(!token.contains("Synthetic"))
    }

    @Test("Source and legacy tokens focus distinct official duplicates and ignore hypothetical rows")
    func officialIdentityMapping() throws {
        let course = UnifiedCourseData(corNumId: "course", stuId: "synthetic", section: "1", gbId: "book",
            courseName: "Synthetic class", semester: .fall, termLength: "", gradeYear: 12,
            currentScores: [], historicalGrades: HistoricalGrades())
        let duplicate = GradeInfoAssignment(date: "10/14/26", name: "Repeated title", pointsEarned: 8, pointsTotal: 10, meta: [])
        var info = GradeInfoResult(course: "Synthetic", instructor: "", litName: TermLabel.q2.bucket,
            gradebook: [GradeCategory(category: "Practice", assignments: [duplicate, duplicate]),
                        GradeCategory(category: "Tests", assignments: [duplicate])])
        let source = CalendarAssignment.sourceAssignments(course: course, term: .q2, gradeInfo: info)
        let calculated = AssignmentGradeEdits.assignments(from: info, className: course.courseName, term: .q2)
        #expect(Set(source.map(\.routeID)).count == 3)
        for (row, calc) in zip(source, calculated) {
            #expect(AssignmentLink.calcAssignmentID(for: row.routeID, course: course, term: .q2, gradeInfo: info) == calc.id)
            #expect(AssignmentLink.calcAssignmentID(for: AssignmentLink.assignmentToken(for: calc.id), course: course, term: .q2, gradeInfo: info) == calc.id)
            #expect(AssignmentLink.sourceAssignmentID(for: calc.id, course: course, term: .q2, gradeInfo: info) == row.id)
        }
        let unknown = AssignmentLink.assignmentToken(for: "hypothetical row")
        #expect(AssignmentLink.calcAssignmentID(for: unknown, course: course, term: .q2, gradeInfo: info) == nil)
        #expect(AssignmentLink.sourceAssignmentID(for: "hypothetical row", course: course, term: .q2, gradeInfo: info) == nil)
        #expect(AssignmentLink.calcAssignmentID(for: source[0].routeID, course: course, term: .sm1, gradeInfo: info) == nil)
        #expect(AssignmentLink.sourceAssignmentID(for: calculated[0].id, course: course, term: .sm1, gradeInfo: info) == nil)
        #expect(AssignmentLink.calcAssignmentID(for: source[0].routeID, course: course, term: .q3, gradeInfo: info) == nil)

        // Source identity excludes scores/possible points. It still finds the
        // new calculation identity after the teacher changes point totals.
        info.gradebook[0].assignments[0].pointsTotal = 20
        info.gradebook[0].assignments[0].pointsEarned = 17
        let updated = AssignmentGradeEdits.assignments(from: info, className: course.courseName, term: .q2)
        #expect(updated[0].id != calculated[0].id)
        #expect(AssignmentLink.calcAssignmentID(for: source[0].routeID, course: course, term: .q2, gradeInfo: info) == updated[0].id)
        #expect(AssignmentLink.sourceAssignmentID(for: updated[0].id, course: course, term: .q2, gradeInfo: info) == source[0].id)

        // Reordering different source rows does not change their focus tokens.
        info.gradebook.reverse()
        let reorderedSource = CalendarAssignment.sourceAssignments(course: course, term: .q2, gradeInfo: info)
        #expect(Set(source.map(\.routeID)) == Set(reorderedSource.map(\.routeID)))
        #expect(AssignmentLink.calcAssignmentID(for: source[2].routeID, course: course, term: .q2, gradeInfo: info) == calculated[2].id)
    }

    @Test("Future starts use district midnight and only the verified school year")
    func upcomingDates() {
        func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
        let before = date("2026-10-13T04:59:59Z")
        let start = date("2026-10-13T05:00:00Z")
        #expect(SchoolCalendar.upcomingQuarterStart(term: .q2, now: before) == start)
        #expect(SchoolCalendar.upcomingQuarterStart(term: .q2, now: start) == nil)
        #expect(SchoolCalendar.upcomingQuarterStart(term: .q1, now: before) == nil)
        #expect(SchoolCalendar.upcomingQuarterStart(term: .sm1, now: before) == nil)
        #expect(SchoolCalendar.upcomingQuarterStart(term: .q3, now: before) == date("2027-01-05T06:00:00Z"))
        #expect(SchoolCalendar.upcomingQuarterStart(term: .q4, now: before) == date("2027-03-22T05:00:00Z"))
        #expect(SchoolCalendar.upcomingQuarterStart(term: .q2, now: date("2025-10-01T12:00:00Z")) == nil)
        #expect(SchoolCalendar.upcomingQuarterStart(term: .q2, now: date("2027-08-01T12:00:00Z")) == nil)
    }
}

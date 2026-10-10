import Foundation
import Testing
@testable import ElevateCore

@Suite("Course history and live gradebook matching")
struct CourseMergeTests {
    @Test("Fall grades match the fall transcript row regardless of live row order", arguments: [false, true])
    func repeatedSemesterNames(reverseLiveOrder: Bool) {
        var historyCourses = [
            "Physics": HistoryCourse(courseName: "Physics"),
            "Physics_2": HistoryCourse(courseName: "Physics"),
        ]
        // Put spring first in the dictionary's actual traversal order. This
        // catches name-only matching without relying on randomized hashing.
        let springKey = historyCourses.first!.key
        let fallKey = historyCourses.keys.first { $0 != springKey }!
        historyCourses[springKey]?.terms = "3 - 4"
        historyCourses[fallKey]?.terms = "1 - 2"
        let fall = liveCourse(number: 100, scores: [("TERM 3", 95)])
        let spring = liveCourse(number: 200, scores: [])
        let result = SkywardHistoryAPI.combine(
            history: ["2026-2027": AcademicYear(grade: 11, courses: historyCourses)],
            gradebook: reverseLiveOrder ? [spring, fall] : [fall, spring]
        )["2026-2027"]!.courses

        #expect(result.count == 2)
        #expect(result[fallKey]?.corNumId == "100")
        #expect(result[fallKey]?.gbId == "book-100")
        #expect(result[fallKey]?.rc1 == "95")
        #expect(result[springKey]?.corNumId == "200")
        #expect(result[springKey]?.rc1 == nil)
    }

    @Test("An exact course and section match takes precedence over the same name")
    func exactIdentityBeforeName() {
        var courses = [
            "Physics": HistoryCourse(courseName: "Physics", terms: "1 - 4"),
            "Physics_2": HistoryCourse(courseName: "Physics", terms: "1 - 4"),
        ]
        let otherKey = courses.first!.key
        let exactKey = courses.keys.first { $0 != otherKey }!
        courses[otherKey]?.corNumId = "200"
        courses[otherKey]?.section = "01"
        courses[exactKey]?.corNumId = "100"
        courses[exactKey]?.section = "01"
        let result = SkywardHistoryAPI.combine(
            history: ["2026-2027": AcademicYear(grade: 11, courses: courses)],
            gradebook: [liveCourse(number: 100, scores: [("TERM 3", 95)])]
        )["2026-2027"]!.courses

        #expect(result[exactKey]?.gbId == "book-100")
        #expect(result[exactKey]?.rc1 == "95")
        #expect(result[otherKey]?.corNumId == "200")
        #expect(result[otherKey]?.rc1 == nil)
    }

    @Test("A full-year course can match grades posted in just one semester")
    func fullYearWithFallGrades() {
        let result = SkywardHistoryAPI.combine(
            history: ["2026-2027": AcademicYear(grade: 11, courses: [
                "Physics": HistoryCourse(courseName: "Physics", terms: "1 - 4"),
            ])],
            gradebook: [liveCourse(number: 100, scores: [("TERM 3", 0)])]
        )["2026-2027"]!.courses

        #expect(result.count == 1)
        #expect(result["Physics"]?.terms == "1 - 4")
        #expect(result["Physics"]?.rc1 == "0")
    }

    @Test("Production live membership counts observed credit without manufacturing a school year")
    func independentEnrollmentTransport() throws {
        let observedAt = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
        var gradebook = liveCourse(number: 100, scores: [("TERM 3", 55)])
        gradebook.courseName = "AP English Language and Composition"
        let combined = SkywardHistoryAPI.combine(history: ["2025-2026": AcademicYear(grade: 10, courses: [:])],
            gradebook: [gradebook], fallbackGrade: 11, observedAt: observedAt)
        let courses = UnifiedCourseTransformer.transform(history: combined)
        let course = try #require(courses.first)
        #expect(course.isCurrentEnrollment == true)
        #expect(course.currentEnrollmentSemester == .fall)
        #expect(course.currentEnrollmentGradeYear == 11)
        #expect(course.currentEnrollmentObservedAt == observedAt)
        #expect(course.currentAcademicYearIsVerified == nil)
        #expect(course.academicYearIsVerified == false)
        #expect(course.semester == .unknown)
        let report = CoursePlanner.calculate(plan: CoursePlan(), officialCourses: courses, asOf: observedAt)
        #expect(report.currentTotal == 0.5)
        #expect(report.currentCourses.first?.academicYear == nil)
        #expect(report.currentCourses.first?.semesters == [.sm1])
        #expect(report.currentCourses.first?.status == .expected)
        #expect(report.earnedTotal == 0)
        #expect(report.gpa.allSatisfy { $0.officialBaseline == nil })
        #expect(try JSONDecoder().decode([UnifiedCourseData].self, from: JSONEncoder().encode(courses)) == courses)
    }

    @Test("Old transcript grade levels never supply independent enrollment grade")
    func noInheritedEnrollmentGrade() {
        let observedAt = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
        let combined = SkywardHistoryAPI.combine(history: ["2025-2026": AcademicYear(grade: 11, courses: [:])],
            gradebook: [liveCourse(number: 100, scores: [("TERM 3", 90)])], observedAt: observedAt)
        let courses = UnifiedCourseTransformer.transform(history: combined)
        #expect(courses.first?.gradeYear == 11)
        #expect(courses.first?.currentEnrollmentGradeYear == nil)
        let report = CoursePlanner.calculate(plan: CoursePlan(), officialCourses: courses, asOf: observedAt)
        #expect(report.currentTotal == 0)
        #expect(report.currentCourses.first?.status == .needsReview)
    }

    @Test("A new live snapshot clears prior membership without altering old grades or identities")
    func replacedEnrollmentSnapshot() throws {
        let observedAt = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
        let initial = SkywardHistoryAPI.combine(history: [:], gradebook: [liveCourse(number: 100, scores: [("TERM 3", 95)])],
            fallbackGrade: 11, observedAt: observedAt)
        let cleared = UnifiedCourseTransformer.transform(history: SkywardHistoryAPI.combine(history: initial, gradebook: [], observedAt: observedAt))
        let original = try #require(UnifiedCourseTransformer.transform(history: initial).first)
        let retained = try #require(cleared.first)
        #expect(retained.isCurrentEnrollment == nil)
        #expect(retained.currentEnrollmentObservedAt == nil)
        #expect(retained.historicalGrades == original.historicalGrades)
        #expect(retained.id == original.id)
        #expect(retained.hasGradebookParams)
        #expect(CoursePlanner.calculate(plan: CoursePlan(), officialCourses: cleared, asOf: observedAt).currentTotal == 0)
    }

    private func liveCourse(number: Int, scores: [(String, Double)]) -> GradebookCourse {
        GradebookCourse(
            course: number, courseName: "Physics", instructor: "Teacher", period: 1,
            time: nil, scores: scores, stuId: "synthetic-student", corNumId: number,
            section: "01", gbId: "book-\(number)"
        )
    }

    @Test("Separate semester course identities keep their own terms and gradebooks")
    func semesterIdentities() {
        let history: AcademicHistory = ["2026-2027": AcademicYear(grade: 11, courses: [
            "Physics fall": HistoryCourse(courseName: "AP Physics 1&2", terms: "1 - 2", corNumId: "100", section: "01", gbId: "fall"),
            "Physics spring": HistoryCourse(courseName: "AP Physics 1&2", terms: "3 - 4", corNumId: "200", section: "01", gbId: "spring"),
            "Calculus": HistoryCourse(courseName: "Multivariable Calculus", terms: "1 - 2"),
            "Linear": HistoryCourse(courseName: "Linear Algebra", terms: "3 - 4"),
        ])]
        let courses = UnifiedCourseTransformer.transform(history: history)
        #expect(courses.count == 4)
        #expect(Set(courses.map(\.id)).count == 4)
        for course in courses {
            #expect(course.availableTerms == (course.semester == .fall ? [.q1, .q2, .sm1] : [.q3, .q4, .sm2]))
        }
        var fullYear = courses[0]
        fullYear.semester = .both
        #expect(fullYear.availableTerms == TermLabel.allCases)
        fullYear.semester = .unknown
        #expect(fullYear.availableTerms == TermLabel.allCases)
    }

    @Test("Unmatched live courses retain unknown duration and distinct identities")
    func unmatchedDuration() {
        let combined = SkywardHistoryAPI.combine(
            history: ["2026-2027": AcademicYear(grade: 11, courses: [:])],
            gradebook: [liveCourse(number: 100, scores: [("TERM 3", 95)]), liveCourse(number: 200, scores: [])]
        )
        let courses = UnifiedCourseTransformer.transform(history: combined)
        #expect(courses.count == 2)
        #expect(Set(courses.map(\.id)).count == 2)
        #expect(courses.allSatisfy { $0.semester == .unknown })
    }
}

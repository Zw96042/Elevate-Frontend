import Foundation
import Testing
@testable import ElevateCore

@Suite("School-year course history")
struct CourseHistoryTests {
    @Test("Transformation retains source years and row keys without changing grades")
    func retainsSourceMetadata() {
        let courses = UnifiedCourseTransformer.transform(history: [
            "2025-2026": AcademicYear(grade: 10, courses: [
                "Physics_2": HistoryCourse(courseName: "Physics", terms: "1 - 2", sm1: "0", rc1: "A", rc2: ""),
            ]),
        ])
        let course = courses[0]
        #expect(course.academicYear == "2025-2026")
        #expect(course.historyRowKey == "Physics_2")
        #expect(course.academicYearIsVerified == true)
        #expect(course.availableTerms == [.q1, .q2, .sm1])
        #expect(course.historicalGrades.sm1 == "0")
        #expect(course.historicalGrades.rc1 == "A")
        #expect(course.historicalGrades.rc2 == nil)
        #expect(course.currentScores == [BucketScore(bucket: "S1", score: 0)])
    }

    @Test("Older course caches decode without inventing a school year")
    func decodesLegacyCache() throws {
        let original = coursesWithCurrentYear()[0]
        let encoded = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "academicYear")
        object.removeValue(forKey: "historyRowKey")
        object.removeValue(forKey: "academicYearIsVerified")
        object.removeValue(forKey: "currentAcademicYearIsVerified")
        object.removeValue(forKey: "isTranscriptRecord")
        object.removeValue(forKey: "postedHistoricalGrades")
        let course = try JSONDecoder().decode(UnifiedCourseData.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(course.academicYear == nil)
        #expect(course.historyRowKey == nil)
        #expect(course.currentAcademicYearIsVerified == nil)
        #expect(course.isTranscriptRecord == nil)
        #expect(course.postedGrades == course.historicalGrades)
        let report = CourseHistoryReport(courses: [course])
        #expect(report.hasLegacyMetadata)
        #expect(!report.hasCurrentYearEvidence)
        #expect(report.years.isEmpty)
        #expect(report.knownAcademicYears.isEmpty)
    }

    @Test("Repeated transcript names retain distinct stable IDs across rows and years")
    func distinctTranscriptIdentity() {
        let history: AcademicHistory = [
            "2024-2025": AcademicYear(grade: 10, courses: [
                "Physics": HistoryCourse(courseName: "Physics"),
                "Physics_2": HistoryCourse(courseName: "Physics"),
            ]),
            "2025-2026": AcademicYear(grade: 10, courses: [
                "Physics": HistoryCourse(courseName: "Physics"),
            ]),
        ]
        let first = UnifiedCourseTransformer.transform(history: history)
        let second = UnifiedCourseTransformer.transform(history: history)
        #expect(Set(first.map(\.id)).count == 3)
        #expect(Set(first.map(\.id)) == Set(second.map(\.id)))
        #expect(first.allSatisfy { $0.courseName == "Physics" })
    }

    @Test("Live gradebook identity stays compatible with viewing history and local edits")
    func preservesLiveIdentity() throws {
        let live = try #require(coursesWithCurrentYear().first { $0.hasGradebookParams })
        let oldID = [live.stuId, live.corNumId, live.section, live.gbId,
                     live.courseId.map(String.init) ?? "", live.gradeYear.map(String.init) ?? "", live.courseName]
            .joined(separator: "|")
        #expect(live.id == oldID)
    }

    @Test("Repeated grade levels group by school year and exclude current-year completed courses")
    func groupsRepeatedGrades() {
        let report = CourseHistoryReport(courses: coursesWithCurrentYear())
        #expect(report.currentAcademicYear == "2026-2027")
        #expect(report.years == ["2025-2026", "2024-2025"])
        #expect(report.courses(for: "2025-2026").count == 1)
        #expect(report.courses(for: "2024-2025").count == 1)
        #expect(report.courses(for: "2026-2027").isEmpty)
        #expect(report.courses(inAcademicYear: "2026-2027").count == 2)
    }

    @Test("No live gradebook evidence keeps archive years available without claiming prior years")
    func missingCurrentEvidence() {
        let courses = coursesWithCurrentYear().filter { !$0.hasGradebookParams }
        let report = CourseHistoryReport(courses: courses)
        #expect(!report.hasCurrentYearEvidence)
        #expect(report.years.isEmpty)
        #expect(report.knownAcademicYears == ["2026-2027", "2025-2026", "2024-2025"])
        #expect(report.courses(inAcademicYear: "2025-2026").count == 1)
    }


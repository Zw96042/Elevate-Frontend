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

    @Test("Synthetic next-year merge buckets do not become verified current-year evidence")
    func syntheticYearIsNotEvidence() {
        let merged = SkywardHistoryAPI.combine(
            history: ["2025-2026": AcademicYear(grade: 10, courses: ["Physics": HistoryCourse(courseName: "Physics")])],
            gradebook: [liveCourse()], fallbackGrade: 11
        )
        let courses = UnifiedCourseTransformer.transform(history: merged)
        let report = CourseHistoryReport(courses: courses)
        #expect(courses.first { $0.hasGradebookParams }?.academicYearIsVerified == false)
        #expect(!report.hasCurrentYearEvidence)
        #expect(report.years.isEmpty)
        #expect(report.knownAcademicYears == ["2025-2026"])
    }

    @Test("Invalid year keys and conflicting live years cannot establish current-year evidence")
    func rejectsAmbiguousYears() {
        for key in ["current", "2026-28", "2026-2028", " 2026-2027", "2026-2027-extra"] {
            #expect(AcademicYearKey.startYear(key) == nil)
            var course = coursesWithCurrentYear().first { $0.hasGradebookParams }!
            course.academicYear = key
            #expect(!CourseHistoryReport(courses: [course]).hasCurrentYearEvidence)
        }
        var live = coursesWithCurrentYear().first { $0.hasGradebookParams }!
        live.academicYear = "2025-2026"
        #expect(!CourseHistoryReport(courses: coursesWithCurrentYear() + [live]).hasCurrentYearEvidence)
        live.academicYearIsVerified = false
        #expect(!CourseHistoryReport(courses: coursesWithCurrentYear() + [live]).hasCurrentYearEvidence)
    }

    @Test("Attaching live rows to the latest transcript year is not independent current-year evidence", arguments: [false, true])
    func latestTranscriptIsNotCurrent(repeatedGrade: Bool) {
        let history: AcademicHistory = ["2025-2026": AcademicYear(grade: 10, courses: [
            "Physics": HistoryCourse(courseName: "Physics", terms: "1 - 4", rc1: "80"),
        ])]
        let merged = SkywardHistoryAPI.combine(history: history, gradebook: [liveCourse()], fallbackGrade: repeatedGrade ? 10 : nil)
        let courses = UnifiedCourseTransformer.transform(history: merged)
        let report = CourseHistoryReport(courses: courses)
        #expect(courses.first?.hasGradebookParams == true)
        #expect(courses.first?.academicYearIsVerified == true)
        #expect(courses.first?.currentAcademicYearIsVerified == nil)
        #expect(!report.hasCurrentYearEvidence)
        #expect(report.knownAcademicYears == ["2025-2026"])
        #expect(report.years.isEmpty)
    }

    @Test("Live overlays preserve original posted grades and cannot invent transcript records")
    func immutablePostedTranscript() throws {
        let header = ["c": [["h": "2025 - 2026 Grade 10"]]]
        let values = ["<a>Physics</a>", "1 - 4", "", "", "80", "", "", "88", "90", "85", "", "", "", "", "", "", "", ""]
        let transcriptRow = ["c": values.map { ["h": $0] }]
        let history = try SkywardHistoryAPI.condenseAcademicHistory([
            "gradeGrid_1_1_1": ["tb": ["r": [header, transcriptRow]]],
        ])
        #expect(history["2025-2026"]?.courses["Physics"]?.isTranscriptRecord == true)
        #expect(history["2025-2026"]?.courses["Physics"]?.postedHistoricalGrades?.rc1 == "80")
        var live = liveCourse()
        live.scores = [("TERM 3", 99), ("SEM 1", 98)]
        var introduced = liveCourse()
        introduced.courseName = "New current course"
        introduced.course = 200
        introduced.corNumId = 200
        introduced.gbId = "new-current-book"
        let merged = SkywardHistoryAPI.combine(history: history, gradebook: [live, introduced], fallbackGrade: 10)
        let courses = UnifiedCourseTransformer.transform(history: merged)
        let course = try #require(courses.first { $0.courseName == "Physics" })
        #expect(course.historicalGrades.rc1 == "99")
        #expect(course.historicalGrades.sm1 == "98")
        #expect(course.postedGrades.rc1 == "80")
        #expect(course.postedGrades.sm1 == "85")
        #expect(course.postedGrades.ex1 == "90")
        #expect(course.postedGrades.finalGrade == "85")
        #expect(courses.first { $0.courseName == "New current course" }?.isTranscriptRecord == false)
        let report = CourseHistoryReport(courses: courses)
        #expect(report.courses(inAcademicYear: "2025-2026").map(\.courseName) == ["Physics"])
        #expect(!report.hasCurrentYearEvidence)

        // A repeat merge must retain the first posted snapshot rather than
        // taking a snapshot of the already-overlaid live grades.
        live.scores = [("TERM 3", 100)]
        let again = UnifiedCourseTransformer.transform(history: SkywardHistoryAPI.combine(history: merged, gradebook: [live]))
        #expect(again.first { $0.courseName == "Physics" }?.postedGrades.rc1 == "80")
        let decoded = try JSONDecoder().decode([UnifiedCourseData].self, from: JSONEncoder().encode(courses))
        #expect(decoded == courses)
    }

    @Test("Semester archive hides rows without semester grades while raw quarter and progress grades remain")
    func displayPostedRows() {
        var dropped = displayCourse("dropped", grades: HistoricalGrades(rc1: " \n", sm1: ""))
        dropped.historicalGrades.rc1 = "100" // Live overlay is not posted history.
        let zero = displayCourse("zero", grades: HistoricalGrades(rc1: "0", sm1: "0"))
        let pass = displayCourse("pass", grades: HistoricalGrades(sm1: "P"))
        let partial = displayCourse("partial", grades: HistoricalGrades(rc2: "92.50"))
        let progress = displayCourse("progress", grades: HistoricalGrades(pr1: "A"))
        let finalOnly = displayCourse("final", grades: HistoricalGrades(finalGrade: "90"))
        let original = [dropped, zero, pass, partial, progress, finalOnly]
        let entries = CourseHistoryDisplay.entries(courses: original)
        #expect(entries.count == 2)
        #expect(Set(entries.map { $0.course.historyRowKey }) == Set(["zero", "pass"]))
        #expect(entries.first { $0.course.historyRowKey == "zero" }?.course.postedGrades.rc1 == "0")
        #expect(entries.first { $0.course.historyRowKey == "zero" }?.course.postedGrades.sm1 == "0")
        #expect(entries.first { $0.course.historyRowKey == "pass" }?.course.postedGrades.sm1 == "P")
        #expect(original[0].historicalGrades.rc1 == "100")
        #expect(original[0].postedGrades.rc1 == " \n")
        let raw = CourseHistoryReport(courses: original).courses(inAcademicYear: "2025-2026")
        #expect(raw.count == original.count)
        #expect(raw.first { $0.historyRowKey == "partial" }?.postedGrades.rc2 == "92.50")
        #expect(raw.first { $0.historyRowKey == "progress" }?.postedGrades.pr1 == "A")
    }


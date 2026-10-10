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

    @Test("Unique complementary semesters combine only their display snapshot and stable source IDs")
    func displayComplementarySemesters() throws {
        let fall = displayCourse("Physics", grades: HistoricalGrades(rc1: "85.00", sm1: " 86 ", finalGrade: "86"))
        let spring = displayCourse("Physics_2", grades: HistoricalGrades(rc3: "89", sm2: "P", finalGrade: "P"))
        let input = [fall, spring]
        let entries = CourseHistoryDisplay.entries(courses: input)
        let merged = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(merged.sourceRowIDs.count == 2)
        #expect(merged.course.postedGrades.rc1 == "85.00")
        #expect(merged.course.postedGrades.sm1 == " 86 ")
        #expect(merged.course.postedGrades.rc3 == "89")
        #expect(merged.course.postedGrades.sm2 == "P")
        #expect(merged.course.postedGrades.finalGrade == "P")
        #expect(merged.course.id == fall.id || merged.course.id == spring.id)
        #expect(CourseHistoryDisplay.entries(courses: input.reversed()) == entries)
        #expect(input == [fall, spring])
        #expect(fall.postedGrades.sm2 == nil && spring.postedGrades.sm1 == nil)
        #expect(merged.course.historicalGrades == fall.historicalGrades || merged.course.historicalGrades == spring.historicalGrades)
    }

    @Test("Conflicting, ambiguous and distinct source titles cannot be combined")
    func displayAmbiguousRows() {
        let fall = displayCourse("Physics", grades: HistoricalGrades(sm1: "86"))
        let spring = displayCourse("Physics_2", grades: HistoricalGrades(sm2: "90"))
        let repeatFall = displayCourse("Physics_3", grades: HistoricalGrades(sm1: "86"))
        #expect(CourseHistoryDisplay.entries(courses: [fall, spring, repeatFall]).count == 3)
        #expect(CourseHistoryDisplay.entries(courses: [fall, repeatFall]).count == 2)
        var conflicting = spring
        conflicting.postedHistoricalGrades?.rc1 = "80"
        #expect(CourseHistoryDisplay.entries(courses: [fall, conflicting]).count == 2)
        var otherTitle = spring
        otherTitle.courseName = "PHYSICS"
        #expect(CourseHistoryDisplay.entries(courses: [fall, otherTitle]).count == 2)
        var otherCatalog = spring
        var catalogFall = fall
        catalogFall.corNumId = "catalog-one"
        otherCatalog.corNumId = "catalog-two"
        #expect(CourseHistoryDisplay.entries(courses: [catalogFall, otherCatalog]).count == 2)
        let rcOnly = displayCourse("Physics_4", grades: HistoricalGrades(rc3: "91"))
        #expect(CourseHistoryDisplay.entries(courses: [fall, rcOnly]).map(\.course) == [fall])
        #expect(CourseHistoryReport(courses: [fall, rcOnly]).courses(inAcademicYear: "2025-2026").count == 2)
    }

    @Test("School years and grade-year identities remain separate and dropped duplicates do not prevent a unique pair")
    func displayYearIdentity() {
        let fall = displayCourse("Physics", grades: HistoricalGrades(sm1: "86"))
        let spring = displayCourse("Physics_2", grades: HistoricalGrades(sm2: "90"))
        let dropped = displayCourse("Physics_3", grades: HistoricalGrades())
        #expect(CourseHistoryDisplay.entries(courses: [fall, spring, dropped]).count == 1)
        var anotherYear = spring
        anotherYear.academicYear = "2024-2025"
        #expect(CourseHistoryDisplay.entries(courses: [fall, anotherYear]).count == 2)
        var anotherGrade = spring
        anotherGrade.gradeYear = 11
        #expect(CourseHistoryDisplay.entries(courses: [fall, anotherGrade]).count == 2)
        var unknownSource = spring
        unknownSource.historyRowKey = nil
        #expect(CourseHistoryDisplay.entries(courses: [fall, unknownSource]).count == 2)
    }

    @Test("LOTE keeps its acronym capitalization in shared course titles")
    func loteFormatting() {
        #expect(ClassNameFormatter.format("LOTE_SPANISH_II") == "LOTE Spanish II")
        #expect(ClassNameFormatter.format("lote_credit") == "LOTE Credit")
        #expect(ClassNameFormatter.format("AP_COMPUTER_SCIENCE_A") == "AP Computer Science A")
    }

    private func displayCourse(_ row: String, grades: HistoricalGrades) -> UnifiedCourseData {
        UnifiedCourseData(corNumId: "", stuId: "", section: "", gbId: "", courseName: "Physics",
            semester: .both, termLength: "1 - 4", gradeYear: 10, currentScores: [], historicalGrades: grades,
            academicYear: "2025-2026", historyRowKey: row, academicYearIsVerified: true,
            isTranscriptRecord: true, postedHistoricalGrades: grades)
    }

    private func coursesWithCurrentYear() -> [UnifiedCourseData] {
        let history: AcademicHistory = [
            "2024-2025": AcademicYear(grade: 10, courses: ["Physics": HistoryCourse(courseName: "Physics")]),
            "2025-2026": AcademicYear(grade: 10, courses: ["Physics": HistoryCourse(courseName: "Physics")]),
            "2026-2027": AcademicYear(grade: 10, courses: [
                "Physics": HistoryCourse(courseName: "Physics"),
                "Completed": HistoryCourse(courseName: "Completed", terms: "1 - 2", sm1: "90"),
            ]),
        ]
        var courses = UnifiedCourseTransformer.transform(history: SkywardHistoryAPI.combine(history: history, gradebook: [liveCourse()]))
        // This fixture deliberately supplies independent current-year evidence.
        // Real combine output must never infer it from a matching grade/name.
        for index in courses.indices where courses[index].hasGradebookParams {
            courses[index].currentAcademicYearIsVerified = true
        }
        return courses
    }

    private func liveCourse() -> GradebookCourse {
        GradebookCourse(course: 100, courseName: "Physics", instructor: "Teacher", period: 1,
                        scores: [("TERM 3", 90)], stuId: "synthetic-student", corNumId: 100,
                        section: "01", gbId: "synthetic-book")
    }
}

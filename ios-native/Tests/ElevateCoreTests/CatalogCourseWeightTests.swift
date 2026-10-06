import Foundation
import Testing
@testable import ElevateCore

struct CatalogCourseWeightTests {
    private let truncatedName = "INDEPENDENT STUDY IN ENGLISH ("

    @Test("Seven-course quarter total includes the verified English AP bonus")
    func sevenCourseQuarter() throws {
        let names = [truncatedName, "AP Biology", "Honors Chemistry", "Honors Algebra", "Honors History", "Art", "PE"]
        let grades = [99, 98, 100, 97, 100, 96, 99]
        var courses = zip(names, grades).map { name, grade in
            var source = course(name: name)
            source.historicalGrades = HistoricalGrades(rc1: String(grade))
            return source
        }
        #expect(GPACalculator.termGPAs(courses: courses)["RC1"]?.weighted == 102)
        courses[0].catalogCourseCode = "LA145"
        #expect(courses.filter { $0.courseLevel == .ap }.count == 2)
        #expect(courses.filter { $0.courseLevel == .honors }.count == 3)
        let total = zip(courses, grades).reduce(0.0) { $0 + Double($1.1) + $1.0.courseLevel.gpaBonus }
        #expect(total == 724)
        #expect(GPACalculator.termGPAs(courses: courses)["RC1"]?.weighted == 103.43)
    }

    @Test("Verified catalog codes weight truncated titles without changing source identity or grades")
    func catalogWeighting() throws {
        for code in ["LA145", "LA146"] {
            var source = course()
            let originalID = source.id
            let originalGrades = source.historicalGrades
            source.catalogCourseCode = code
            #expect(source.courseLevel == .ap)
            #expect(source.courseName == truncatedName)
            #expect(source.id == originalID)
            #expect(source.historicalGrades == originalGrades)
            let district = try #require(GPACalculator.termGPAs(courses: [source])["SM1"])
            #expect(district.weighted == 105)
            #expect(district.unweighted == 95)
            let weighted = GPAConversionCalculator.calculate(courses: [source], policy: .weighted5Point)
            #expect(weighted.value == 5)
            #expect(weighted.includedRecords.first?.courseLevel == .ap)
            #expect(weighted.includedRecords.first?.courseName == truncatedName)
            #expect(weighted.includedRecords.first?.percentage == 95)
            #expect(GPAConversionCalculator.calculate(courses: [source], policy: .unweighted4Point).value == 4)
        }
    }

    @Test("Missing and unknown catalog codes never guess truncated or generic independent study levels")
    func negativeControls() {
        for name in [truncatedName, "Independent Study in English", "Independent Study"] {
            for code in [nil, "LA147", "UNKNOWN", "LA145-extra", ""] as [String?] {
                var source = course(name: name)
                source.catalogCourseCode = code
                #expect(source.courseLevel == .regular)
                #expect(GPACalculator.termGPAs(courses: [source])["SM1"]?.weighted == 95)
                #expect(GPAConversionCalculator.calculate(courses: [source], policy: .weighted5Point).value == 4)
            }
        }
        var explicitAP = course(name: "AP Biology")
        explicitAP.catalogCourseCode = "UNKNOWN"
        #expect(explicitAP.courseLevel == .ap)
    }

    @Test("Old course caches decode without catalog metadata and new caches round trip")
    func cacheCompatibility() throws {
        var source = course()
        source.catalogCourseCode = "LA145"
        let data = try JSONEncoder().encode(source)
        #expect(try JSONDecoder().decode(UnifiedCourseData.self, from: data).catalogCourseCode == "LA145")
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "catalogCourseCode")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(UnifiedCourseData.self, from: oldData)
        #expect(decoded.catalogCourseCode == nil)
        #expect(decoded.courseLevel == .regular)
        #expect(decoded.courseName == source.courseName)
        #expect(decoded.id == source.id)
    }

    @Test("History transformation retains exact catalog metadata and source title")
    func transformation() throws {
        var historyCourse = HistoryCourse(courseName: truncatedName, terms: "1 - 2", sm1: "95")
        historyCourse.catalogCourseCode = "LA145"
        let history: AcademicHistory = ["2025-2026": AcademicYear(grade: 10, courses: ["source-row": historyCourse])]
        let transformed = try #require(UnifiedCourseTransformer.transform(history: history).first)
        #expect(transformed.catalogCourseCode == "LA145")
        #expect(transformed.courseLevel == .ap)
        #expect(transformed.courseName == truncatedName)
        #expect(transformed.historyRowKey == "source-row")
        #expect(transformed.historicalGrades.sm1 == "95")
    }

    @Test("Live course catalog metadata reaches GPA without weighting another same-name section")
    func liveCatalogPropagation() throws {
        let rows = [
            "seminar": HistoryCourse(courseName: truncatedName, terms: "1 - 2", sm1: "95", corNumId: "101", section: "1"),
            "other": HistoryCourse(courseName: truncatedName, terms: "1 - 2", sm1: "95", corNumId: "102", section: "2"),
        ]
        let live = GradebookCourse(course: 101, courseName: truncatedName,
            instructor: "Synthetic Teacher", period: 1, scores: [("TERM 3", 95)],
            stuId: "synthetic", corNumId: 101, section: "1", gbId: "101", catalogCourseCode: "LA145")
        var withoutCatalog = live
        withoutCatalog.catalogCourseCode = nil
        let original = UnifiedCourseTransformer.transform(history: SkywardHistoryAPI.combine(
            history: ["2025-2026": AcademicYear(grade: 10, courses: rows)], gradebook: [withoutCatalog]))
        let merged = SkywardHistoryAPI.combine(history: ["2025-2026": AcademicYear(grade: 10, courses: rows)], gradebook: [live])
        let courses = UnifiedCourseTransformer.transform(history: merged)
        let seminar = try #require(courses.first { $0.historyRowKey == "seminar" })
        let other = try #require(courses.first { $0.historyRowKey == "other" })
        #expect(seminar.courseLevel == .ap)
        #expect(other.courseLevel == .regular)
        #expect(seminar.courseName == truncatedName)
        #expect(seminar.id == original.first { $0.historyRowKey == "seminar" }?.id)
        #expect(seminar.historicalGrades.sm1 == "95")
        #expect(GPACalculator.termGPAs(courses: courses)["SM1"]?.weighted == 100)
    }

    private func course(name: String? = nil) -> UnifiedCourseData {
        UnifiedCourseData(
            courseId: 101, corNumId: "101", stuId: "synthetic", section: "1", gbId: "101",
            courseName: name ?? truncatedName, semester: .fall, termLength: "1 - 2", gradeYear: 10,
            currentScores: [], historicalGrades: HistoricalGrades(sm1: "95")
        )
    }
}

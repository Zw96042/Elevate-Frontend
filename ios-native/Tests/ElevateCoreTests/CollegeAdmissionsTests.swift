import Foundation
import Testing
@testable import ElevateCore

@Suite("Published college admissions and preparation context")
struct CollegeAdmissionsTests {
    @Test("Bundled admissions metadata expands the catalog without invented GPA figures")
    func bundledCatalog() throws {
        #expect(CollegeAdmissionsCatalog.profiles.count == 56)
        #expect(CollegeAdmissionsCatalog.additions.count == 36)
        #expect(Set(CollegeProfileCatalog.profiles.map(\.id)).count == CollegeProfileCatalog.profiles.count)
        #expect(CollegeProfileCatalog.profiles.count == 114)
        #expect(CollegeAdmissionsCatalog.profiles.allSatisfy { $0.isValid })
        #expect(CollegeAdmissionsCatalog.profiles.allSatisfy { !$0.cohort.isEmpty && !$0.population.isEmpty && $0.sourceURL.scheme == "https" })
        #expect(CollegeAdmissionsCatalog.additions.allSatisfy { !$0.hasPublishedStatistics && $0.publishedGPAScale == .unspecified })
        let txst = try #require(CollegeProfileCatalog.profiles.first { $0.id == "texas-state" })
        #expect(txst.searchAliases.contains("TXST"))
        #expect(CollegeProfileCatalog.search("TXST").map(\.id) == ["texas-state"])
        #expect(CollegeAdmissionsCatalog.details(for: txst.id)?.location == "San Marcos, Texas")
        #expect(CollegeAdmissionsCatalog.details(for: "unknown") == nil)
    }

    @Test("Each statistic preserves population/cohort and SAT sections never imply a total")
    func statisticProvenance() throws {
        let mit = try #require(CollegeAdmissionsCatalog.details(for: "mit"))
        #expect(mit.satRange == nil)
        #expect(mit.satSections.count == 2)
        #expect(mit.satSections.first?.population == "Admitted first-year students")
        #expect(mit.acceptance?.applicants == 29_281)
        let rice = try #require(CollegeAdmissionsCatalog.details(for: "rice"))
        #expect(rice.satRange?.population == "Deposited students reporting SAT")
        #expect(rice.enrollment?.population == "Enrolled first-year students")
        let trinity = try #require(CollegeAdmissionsCatalog.details(for: "trinity"))
        #expect(trinity.testMeans.first { $0.test == "SAT" }?.value == 1404)
        #expect(trinity.satRange == nil)
        let georgia = try #require(CollegeAdmissionsCatalog.details(for: "georgia"))
        #expect(georgia.acceptance?.isApproximate == true)
        #expect(georgia.acceptance?.resolvedRatePercent == nil)
        let purdue = try #require(CollegeAdmissionsCatalog.details(for: "purdue"))
        #expect(purdue.satRange == nil)
        #expect(purdue.actRange == nil)
        #expect(purdue.acceptance?.ratePercent == 43.4)
    }

    @Test("Invalid rates or contradictory counts cannot decode or produce an admission rate")
    func invalidAcceptance() throws {
        let source = URL(string: "https://example.edu/admissions")!
        for value in [-1.0, 100.1, .infinity, .nan] {
            let figure = CollegeAcceptance(ratePercent: value, population: "Applicants", cohort: "Fall 2026", sourceURL: source)
            #expect(!figure.isValid)
            #expect(figure.resolvedRatePercent == nil)
        }
        let impossible = CollegeAcceptance(applicants: 10, admitted: 11, population: "Applicants", cohort: "Fall 2026", sourceURL: source)
        #expect(!impossible.isValid)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(CollegeAcceptance.self, from: JSONEncoder().encode(impossible)) }
        let valid = CollegeAcceptance(applicants: 20, admitted: 5, population: "Applicants", cohort: "Fall 2026", sourceURL: source)
        #expect(valid.resolvedRatePercent == 25)
        let nc = try #require(CollegeAdmissionsCatalog.details(for: "nc-state"))
        #expect(nc.acceptance?.admitted == nil)
        #expect(nc.acceptance?.resolvedRatePercent == 41)
    }

    @Test("Preparation retains missing-data and lab/language/academic-elective limits")
    func unavailablePreparation() throws {
        let details = try #require(CollegeAdmissionsCatalog.details(for: "oklahoma"))
        let rows = CollegePreparationContext.rows(details: details, courses: [], asOf: date)
        #expect(rows.count == details.preparation.count)
        #expect(rows.allSatisfy { $0.earned == nil && $0.current == nil && $0.remaining == nil && $0.availabilityReason != nil })
        #expect(rows.first { $0.subject == "Laboratory science" }?.availabilityReason?.contains("general science") == true)
        #expect(rows.first { $0.subject == "Academic electives" }?.availabilityReason?.contains("not comparable") == true)
        let texas = try #require(CollegeAdmissionsCatalog.details(for: "texas-state"))
        let language = CollegePreparationContext.rows(details: texas, courses: [], asOf: date).first { $0.subject == "World language" }
        #expect(language?.availabilityReason?.contains("same language") == true)
        #expect(language?.note.contains("assured admission") == true)
    }

    @Test("Program scopes remain visible and senior English is never fulfilled by pooled English credits")
    func scopedPreparation() throws {
        for id in ["villanova", "rutgers", "iowa", "indiana", "toronto"] {
            #expect(CollegeAdmissionsCatalog.details(for: id)?.preparationScope?.isEmpty == false)
        }
        let toronto = try #require(CollegeAdmissionsCatalog.details(for: "toronto"))
        #expect(toronto.preparation.first?.comparisonScope == .seniorEnglish)
        let earlierEnglish = ["English I", "English II", "English III"].map { transcript($0, gradeYear: 10) }
        let rows = CollegePreparationContext.rows(details: toronto, courses: earlierEnglish + [enrollment("English IV")], asOf: date)
        let english = try #require(rows.first)
        #expect(english.earned == nil)
        #expect(english.current == nil)
        #expect(english.remaining == nil)
        #expect(english.availabilityReason?.contains("Senior/Grade 12 equivalent") == true)
        #expect(english.note.contains("not a total") == true)
    }

    @Test("Local context counts high-school credits separately from expected enrollments and preserves gaps")
    func localCreditContext() throws {
        let details = try #require(CollegeAdmissionsCatalog.details(for: "texas-state"))
        let prior = transcript("English I", gradeYear: 9)
        let middle = transcript("Algebra I", gradeYear: 8)
        let live = enrollment("English II")
        let rows = CollegePreparationContext.rows(details: details, courses: [prior, middle, live], asOf: date)
        let english = try #require(rows.first { $0.subject == "English" })
        #expect(english.earned == 1)
        #expect(english.current == 0.5)
        #expect(english.remaining == 2.5)
        #expect(rows.first { $0.subject == "Mathematics" }?.earned == 0)
        #expect(rows.first { $0.subject == "World language" }?.earned == nil)
        #expect(live.historicalGrades.sm1 == nil)
        let unknown = transcript("Uncatalogued Seminar", gradeYear: 10)
        let reviewed = CollegePreparationContext.rows(details: details, courses: [prior, unknown, live], asOf: date)
        #expect(reviewed.first { $0.subject == "English" }?.earned == 1)
        #expect(reviewed.first { $0.subject == "English" }?.remaining == nil)
        #expect(reviewed.first { $0.subject == "English" }?.availabilityReason?.contains("classification") == true)
        let withoutTranscript = CollegePreparationContext.rows(details: details, courses: [live], asOf: date)
        #expect(withoutTranscript.first { $0.subject == "English" }?.earned == nil)
        #expect(withoutTranscript.first { $0.subject == "English" }?.current == 0.5)
        #expect(withoutTranscript.first { $0.subject == "English" }?.remaining == nil)
        var missingGrade = prior
        missingGrade.gradeYear = nil
        let missingGradeRows = CollegePreparationContext.rows(details: details, courses: [missingGrade], asOf: date)
        #expect(missingGradeRows.first { $0.subject == "English" }?.earned == 0)
        #expect(missingGradeRows.first { $0.subject == "English" }?.remaining == nil)
        #expect(missingGradeRows.first { $0.subject == "English" }?.availabilityReason?.contains("review") == true)
    }

    @Test("Preparation respects source-bound planner credit and subject corrections")
    func correctedCreditContext() throws {
        let details = try #require(CollegeAdmissionsCatalog.details(for: "texas-state"))
        let courses = [transcript("English I", gradeYear: 9), transcript("Uncatalogued Seminar", gradeYear: 10)]
        let source = TranscriptCreditCalculator.calculate(courses: courses, asOf: date)
        let corrections = source.records.map { record in
            TranscriptCreditOverride(id: record.id, credits: record.name == "English I" ? 0.25 : 0.5,
                subject: record.name == "English I" ? .math : .english)
        }
        let corrected = CollegePreparationContext.rows(details: details, courses: courses, creditOverrides: corrections, asOf: date)
        #expect(corrected.first { $0.subject == "English" }?.earned == 1)
        #expect(corrected.first { $0.subject == "English" }?.remaining == 3)
        #expect(corrected.first { $0.subject == "Mathematics" }?.earned == 0.5)
        #expect(corrected.first { $0.subject == "Mathematics" }?.remaining == 3.5)
        #expect(corrected.first { $0.subject == "English" }?.availabilityReason?.contains("classification") == false)
        let original = CollegePreparationContext.rows(details: details, courses: courses, asOf: date)
        #expect(original.first { $0.subject == "English" }?.earned == 1)
        #expect(original.first { $0.subject == "English" }?.remaining == nil)
        #expect(original.first { $0.subject == "Mathematics" }?.earned == 0)
    }

    private var date: Date { ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z")! }
    private func transcript(_ name: String, gradeYear: Int) -> UnifiedCourseData {
        let grades = HistoricalGrades(sm1: "90", sm2: "90")
        return UnifiedCourseData(courseId: nil, corNumId: "", stuId: "", section: "", gbId: "", courseName: name,
            semester: .both, termLength: "1-4", gradeYear: gradeYear, currentScores: [], historicalGrades: grades,
            academicYear: "2025-2026", historyRowKey: name, academicYearIsVerified: true, isTranscriptRecord: true,
            postedHistoricalGrades: grades)
    }
    private func enrollment(_ name: String) -> UnifiedCourseData {
        UnifiedCourseData(courseId: 1, corNumId: "synthetic", stuId: "synthetic", section: "1", gbId: "1", courseName: name,
            semester: .unknown, termLength: "", gradeYear: nil, currentScores: [], historicalGrades: HistoricalGrades(),
            academicYearIsVerified: false, isTranscriptRecord: false, isCurrentEnrollment: true,
            currentEnrollmentSemester: .fall, currentEnrollmentGradeYear: 10, currentEnrollmentObservedAt: date)
    }
}

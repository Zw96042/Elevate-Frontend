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


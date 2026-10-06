import Foundation
import Testing
@testable import ElevateCore

struct CollegeGPATests {
    @Test("Verified Capstone aliases receive AP recognition without upgrading independent study")
    func capstoneAliases() {
        for title in ["Independent Study In English (1)", "English Independent Study I (AP Capstone: Seminar) - LA145", "LA145", "Independent Study in English II", "LA146"] {
            #expect(CollegeGPACalculator.isExplicitAPOrIB(title))
            let result = CollegeGPACalculator.calculate(profile: profile("ucla"), courses: [course(1, title, 10, "95")], asOf: date)
            #expect(result.value == 5)
            #expect(result.unweightedValue == 4)
        }
        for title in ["Independent Study in English", "Independent Study in English III", "Independent Study in English 10", "Independent Study in English 1 Workshop", "LA147", "Pre-AP Seminar"] {
            #expect(!CollegeGPACalculator.isExplicitAPOrIB(title))
        }
    }

    private let date = ISO8601DateFormatter().date(from: "2026-10-04T18:00:00Z")!
    private func profile(_ id: String) -> CollegeProfile { CollegeProfileCatalog.profiles.first { $0.id == id }! }

    @Test("UC fully weighted recalculates only completed grade 10–11 records")
    func ucRecalculation() {
        let courses = [course(1, "AP Biology", 10, "90"), course(2, "English Honors", 11, "90"),
                       course(3, "Multivariable Calculus", 11, "90"), course(4, "AP History", 9, "100"),
                       course(5, "AP English", 12, "100", academicYear: "2026-2027")]
        let weighted = CollegeGPACalculator.calculate(profile: profile("ucla"), courses: courses, asOf: date)
        #expect(weighted.records.map(\.points) == [5, 4, 4])
        #expect(abs(weighted.value! - 13.0 / 3.0) < 1e-10)
        #expect(weighted.skipped.contains { $0.reason == .inProgress })
        let unweighted = CollegeGPACalculator.calculate(profile: profile("berkeley"), courses: courses, asOf: date)
        #expect(unweighted.value == 4)
    }

    @Test("UC AP and IB bonus requires C or better; local exceptions receive none")
    func bonus() {
        let result = CollegeGPACalculator.calculate(profile: profile("ucla"), courses: [
            course(1, "IB Biology", 10, "70"), course(2, "English AP", 10, "69.999"),
            course(3, "AP Biology", 10, "0"), course(4, "Stats 2: Beyond AP Statistics", 10, "100"),
            course(5, "AP Statistics", 10, "100"), course(6, "Biology Honors", 10, "80"),
        ], asOf: date)
        #expect(result.records.map(\.points) == [3, 1, 0, 4, 5, 3])
        #expect(!CollegeGPACalculator.isExplicitAPOrIB("Stats_2:_Beyond_AP_Statistics"))
        #expect(CollegeGPACalculator.isExplicitAPOrIB("AP_PHYSICS"))
        #expect(CollegeGPACalculator.isExplicitAPOrIB("Advanced Placement Biology"))
        #expect(!CollegeGPACalculator.isExplicitAPOrIB("CAPSTONE"))
    }

    @Test("UCLA profile is fully weighted without the UC eligibility eight-semester cap")
    func uncapped() {
        let courses = (1...10).map { course($0, "AP Subject \($0)", 10, "90") }
        #expect(CollegeGPACalculator.calculate(profile: profile("ucla"), courses: courses, asOf: date).value == 5)
    }

    @Test("Private-college comparison normalizes all completed years without honors bonuses")
    func normalizedEstimate() {
        let result = CollegeGPACalculator.calculate(profile: profile("princeton"), courses: [
            course(1, "AP Biology", 9, "90"), course(2, "English Honors", 10, "80"),
            course(3, "English", 11, "70"), course(4, "AP Math", 12, "100", academicYear: "2026-2027"),
        ], asOf: date)
        #expect(result.records.map(\.gradeYear) == [9, 10, 11])
        #expect(result.value == 3)
        #expect(result.profile.method == .reported4Point)
        #expect(result.profile.method.explanation.contains("has not verified"))
    }

    @Test("Unavailable semesters and future records never fabricate a comparison")
    func noData() {
        let result = CollegeGPACalculator.calculate(profile: profile("ucla"), courses: [
            course(1, "AP Biology", 10, "P"), course(2, "English", 11, nil),
            course(3, "AP Math", 11, "99", academicYear: "2027-2028"),
        ], asOf: date)
        #expect(result.records.isEmpty && result.value == nil && result.standing == nil)
        #expect(result.displayValue == "—")
    }

    @Test("Published distribution boundaries are half-open; exact 4.0 is a tie band")
    func bands() {
        let p = profile("princeton")
        let below = CollegeGPAStanding.compare(3.749999, profile: p)!
        let at = CollegeGPAStanding.compare(3.75, profile: p)!
        #expect(below.bandLabel == "3.50–3.74")
        #expect(below.higherBandPercent == nil)
        #expect(below.title == "Your unweighted GPA")
        #expect(at.bandLabel == "3.75–3.99")
        #expect(at.higherBandPercent == nil && at.sameBandPercent == 24)
        let capped = CollegeGPAStanding.compare(4, profile: p)!
        #expect(capped.title == "Highest possible unweighted GPA")
        #expect(capped.higherBandPercent == nil)
        #expect(capped.detail.contains("All A grades"))
        #expect(capped.sameBandPercent == 72)
        #expect(CollegeGPAStanding.compare(3.0, profile: p)?.cohortContext == nil) // lower bands unreported
    }


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

    @Test("Comparisons retain source rounding and reporting-subset coverage")
    func sourcePrecision() {
        let jhu = CollegeGPAStanding.compare(3.8, profile: profile("hopkins"))!
        #expect(jhu.higherBandPercent == nil && jhu.sameBandPercent == 25.36)
        #expect(profile("stanford").reportingPercent == 69.60)
        #expect(profile("hopkins").bands.map(\.percent).reduce(0, +) > 100)
    }

    @Test("Quartiles support bands, not interpolated percentiles or ranks at capped ties")
    func quartiles() {
        let ucla = profile("ucla")
        for value in [4.0, 4.44, 4.6, 4.78, 4.8, 5] {
            #expect(CollegeGPAStanding.compare(value, profile: ucla)?.title == "Your fully weighted GPA")
            #expect(CollegeGPAStanding.compare(value, profile: ucla)?.cohortContext?.contains("4.44–4.78") == true)
        }
        #expect(CollegeGPAStanding.compare(4, profile: profile("berkeley"))?.title == "Highest possible unweighted GPA")
    }

    @Test("Invalid GPA is rejected; malformed class statistics never hide a valid perfect GPA")
    func invalidData() {
        for value in [Double.nan, .infinity, -.infinity, -1, 4.1] {
            #expect(CollegeGPAStanding.compare(value, profile: profile("princeton")) == nil)
        }
        var p = profile("princeton")
        p.bands[0].percent = 1
        #expect(CollegeGPAStanding.compare(4, profile: p)?.title == "Highest possible unweighted GPA")
        #expect(CollegeGPAStanding.compare(4, profile: p)?.cohortContext == nil)
        p = profile("ucla")
        p.quartiles?.lower = .nan
        #expect(CollegeGPAStanding.compare(4, profile: p)?.title == "Your fully weighted GPA")
        #expect(CollegeGPAStanding.compare(4, profile: p)?.cohortContext == nil)
        p = profile("vanderbilt")
        p.reportingPercent = 101
        #expect(CollegeGPAStanding.compare(4, profile: p)?.title == "Highest possible unweighted GPA")
        #expect(CollegeGPAStanding.compare(4, profile: p)?.cohortContext == nil)
        p = profile("vanderbilt")
        p.reportedMean = .nan
        #expect(CollegeGPAStanding.compare(4, profile: p)?.cohortContext == nil)
    }

    @Test("Displayed GPA never rounds across a published band boundary")
    func displayPrecision() {
        let p = profile("princeton")
        func result(_ value: Double) -> CollegeGPAResult {
            CollegeGPAResult(profile: p, records: [GPAConversionRecord(id: "x", courseName: "Synthetic", gradeYear: 11, semester: .sm1, percentage: 90, points: value, source: .transcript)], skipped: [])
        }
        #expect(result(3.7499999).displayValue == "3.74")
        #expect(result(3.999999999999).displayValue == "3.99")
        #expect(result(3.999999999999).standing?.title == "Your unweighted GPA")
        #expect(result(4).displayValue == "4.00")
        #expect(result(4.6).displayValue == "4.60")
    }

    @Test("Vanderbilt's 31.6% is reporting-cohort share, never a student's percentile")
    func perfectVanderbilt() {
        let standing = CollegeGPAStanding.compare(4, profile: profile("vanderbilt"))!
        #expect(standing.title == "Highest possible unweighted GPA")
        #expect(!standing.title.contains("31.6"))
        #expect(standing.sameBandPercent == 31.6 && standing.higherBandPercent == nil)
        #expect(standing.cohortContext?.contains("31.6% of Fall 2025 enrolled first-year students reporting GPA") == true)
        #expect(standing.cohortContext?.contains("not your individual percentile") == true)
        var unpublished = profile("vanderbilt")
        unpublished.bands = []; unpublished.reportedMean = nil; unpublished.reportingPercent = nil
        #expect(CollegeGPAStanding.compare(4, profile: unpublished)?.title == "Highest possible unweighted GPA")
        #expect(CollegeGPAStanding.compare(4, profile: unpublished)?.cohortContext == nil)
    }

    @Test("UC weighted totals keep a separately verified unweighted component")
    func weightedAndUnweightedAreDistinct() {
        let allA = CollegeGPACalculator.calculate(profile: profile("ucla"), courses: [course(1, "AP Biology", 10, "90")], asOf: date)
        #expect(allA.value == 5 && allA.unweightedValue == 4)
        #expect(allA.standing?.title == "Your fully weighted GPA")
        let weightedFour = CollegeGPACalculator.calculate(profile: profile("ucla"), courses: [course(2, "AP Biology", 10, "80")], asOf: date)
        #expect(weightedFour.value == 4 && weightedFour.unweightedValue == 3)
        #expect(weightedFour.standing?.title == "Your fully weighted GPA")
        #expect(weightedFour.standing?.detail.contains("All A") == false)
    }

    @Test("College search supports names, abbreviations, case, diacritics, whitespace and empty results")
    func search() {
        #expect(CollegeProfileCatalog.search("  jHu ").map(\.id) == ["hopkins"])
        #expect(CollegeProfileCatalog.search("  Los    Angeles  ").map(\.id) == ["ucla", "usc"])
        #expect(CollegeProfileCatalog.search("vÁndy").map(\.id) == ["vanderbilt"])
        #expect(CollegeProfileCatalog.search("cwru").map(\.id) == ["case-western"])
        #expect(CollegeProfileCatalog.search("ASU").map(\.id) == ["arizona-state"])
        #expect(CollegeProfileCatalog.search("UIUC").map(\.id) == ["illinois"])
        #expect(CollegeProfileCatalog.search("College that does not exist").isEmpty)
        let all = CollegeProfileCatalog.search("   ")
        #expect(all.count >= 64)
        #expect(all.map(\.name) == all.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(CollegeProfileCatalog.search("mIt").map(\.id) == ["mit"])
    }

    @Test("Expanded publications preserve unavailable statistics and guidance distinctions")
    func expandedCatalog() {
        #expect(profile("boston-university").bands.map(\.percent) == [36, 36, 27, 1, 0, 0, 0, 0, 0])
        #expect(profile("case-western").bands.count == 6 && profile("case-western").reportingPercent == 92)
        #expect(profile("arizona").cohort == "Fall 2024" && profile("arizona").reportedMean == 3.47)
        for id in ["mit", "yale", "pittsburgh"] {
            let p = profile(id)
            #expect(!p.hasPublishedStatistics && p.reportingPercent == nil)
            #expect(CollegeGPAStanding.compare(4, profile: p)?.title == "Highest possible unweighted GPA")
            #expect(CollegeGPAStanding.compare(4, profile: p)?.cohortContext == nil)
        }
        for id in ["wisconsin", "arizona-state"] {
            let p = profile(id)
            #expect(p.population == .admissionsGuidance && p.quartiles == nil)
            #expect(p.publishedSummary != nil && !p.hasPublishedStatistics)
        }
        #expect(profile("purdue").population == .publishedProfile)
        #expect(profile("illinois").cohort == "Rolling three-year admitted profile")
    }

    private func weightedProfile(_ method: CollegeGPAMethod) -> CollegeProfile {
        CollegeProfile(id: "synthetic", name: "Synthetic college", cohort: "Synthetic cohort", population: .admitted,
            method: method, sourceURL: URL(string: "https://example.com")!,
            quartiles: CollegeGPAQuartiles(lower: 4.2, median: nil, upper: 4.6), publishedGPAScale: .weighted)
    }

    @Test("UGA uses core grades and AP arts with no Honors or dual-enrollment bonus")
    func ugaCoreWeighting() {
        let result = CollegeGPACalculator.calculate(profile: weightedProfile(.ugaWeighted), courses: [
            course(1, "AP Biology", 9, "90"), course(2, "English Honors", 10, "90"),
            course(3, "Dual Enrollment Calculus", 11, "90"), course(4, "AP Studio Art", 11, "90"),
            course(5, "AP Music Theory", 11, "80"), course(6, "AP Computer Science", 11, "90"),
            course(7, "Business Math", 10, "90"), course(8, "Journalism", 11, "90"),
            course(9, "English", 12, "90", academicYear: "2026-2027"),
        ], asOf: date)
        #expect(result.records.map(\.points) == [5, 4, 4, 5, 4])
        #expect(result.value == 4.4)
        #expect(result.omittedRecords.count == 3)
        #expect(result.skipped.contains { $0.reason == .inProgress })
        #expect(result.calculationNotes.contains { $0.contains("3 completed") })
        #expect(result.standing?.title == "Your weighted GPA")
        #expect(result.standing?.cohortContext?.contains("4.20–4.60") == true)
    }

    @Test("UF counts AP electives while FSU limits its estimate to core subjects")
    func floridaSubjectDifferences() {
        let courses = [course(1, "AP Art", 10, "90"), course(2, "AP Computer Science", 11, "90"),
            course(3, "Biology Honors", 9, "90"), course(4, "Dual Credit Algebra", 11, "90"),
            course(5, "Pre-AP English", 9, "90"), course(6, "AICE History", 11, "90"),
            course(7, "Robotics", 11, "90")]
        let uf = CollegeGPACalculator.calculate(profile: weightedProfile(.ufWeighted), courses: courses, asOf: date)
        #expect(uf.records.map(\.points) == [5, 5, 4.5, 5, 4.5, 5])
        #expect(uf.omittedRecords.count == 1)
        let fsu = CollegeGPACalculator.calculate(profile: weightedProfile(.fsuWeighted), courses: courses, asOf: date)
        #expect(fsu.records.map(\.points) == [4.5, 5, 4.5, 5])
        #expect(fsu.omittedRecords.count == 3)
    }

    @Test("Pre-level designations never become AP bonuses and district exceptions stay regular")
    func explicitLevels() {
        let titles = ["Pre-AP Biology", "English Pre AP", "PreIB Chemistry", "History Pre-AICE",
            "Multivariable Calculus", "AP Biology", "IB Biology"]
        let courses = titles.enumerated().map { course($0.offset, $0.element, 10, "90") }
        let uf = CollegeGPACalculator.calculate(profile: weightedProfile(.ufWeighted), courses: courses, asOf: date)
        #expect(uf.records.map(\.points) == [4.5, 4.5, 4.5, 4.5, 4, 5, 5])
        let uga = CollegeGPACalculator.calculate(profile: weightedProfile(.ugaWeighted), courses: courses, asOf: date)
        #expect(uga.records.map(\.points) == [4, 4, 4, 4, 4, 5, 5])
        for name in titles.prefix(4) { #expect(!CollegeGPACalculator.isExplicitAPOrIB(name)) }
    }

    @Test("FSU C cutoff retains lower grades with no bonus; other unverified bonuses withhold the total")
    func lowerGradeBonuses() {
        let courses = [course(1, "AP Biology", 10, "70"), course(2, "English Honors", 11, "69.99"),
            course(3, "AP Chemistry", 11, "0")]
        let fsu = CollegeGPACalculator.calculate(profile: weightedProfile(.fsuWeighted), courses: courses, asOf: date)
        #expect(fsu.records.map(\.points) == [3, 1, 0])
        #expect(fsu.value == 4.0 / 3.0)
        for method in [CollegeGPAMethod.ugaWeighted, .ufWeighted] {
            let result = CollegeGPACalculator.calculate(profile: weightedProfile(method), courses: courses, asOf: date)
            #expect(result.records.count == 3)
            #expect(result.value == nil && result.unweightedValue == nil && result.standing == nil && result.displayValue == "—")
            #expect(result.calculationNotes.contains { $0.contains("not been dropped") })
        }
        let regular = CollegeGPACalculator.calculate(profile: weightedProfile(.ufWeighted),
            courses: [course(1, "English", 10, "60")], asOf: date)
        #expect(regular.value == 1)
        let cBoundary = CollegeGPACalculator.calculate(profile: weightedProfile(.ufWeighted),
            courses: [course(1, "AP English", 10, "70")], asOf: date)
        #expect(cBoundary.value == 3)
    }

    @Test("Unrecognized subjects withhold core estimates instead of silently raising the denominator's average")
    func unknownSubject() {
        for method in [CollegeGPAMethod.ugaWeighted, .ufWeighted, .fsuWeighted] {
            let result = CollegeGPACalculator.calculate(profile: weightedProfile(method), courses: [
                course(1, "English", 10, "90"), course(2, "Independent Study", 10, "60"),
            ], asOf: date)
            #expect(result.records.count == 1 && result.omittedRecords.count == 1)
            #expect(result.value == nil && result.unavailableReason != nil)
            #expect(result.calculationNotes.contains { $0.contains("eligibility") && $0.contains("unverified") })
        }
    }

    @Test("District trailing H earns Florida Honors credit but no UGA or UC bonus")
    func districtHonorsSuffix() {
        let courses = [course(1, "ENGLISH 1 H", 10, "95"), course(2, "GEOMETRY H", 10, "80")]
        for method in [CollegeGPAMethod.ufWeighted, .fsuWeighted, .ucfWeighted] {
            let result = CollegeGPACalculator.calculate(profile: weightedProfile(method), courses: courses, asOf: date)
            #expect(result.records.map(\.points) == [4.5, 3.5])
            #expect(result.value == 4)
        }
        for p in [weightedProfile(.ugaWeighted), profile("ucla")] {
            #expect(CollegeGPACalculator.calculate(profile: p, courses: courses, asOf: date).records.map(\.points) == [4, 3])
        }
    }

    @Test("Art History follows explicit UGA and UF rules; unresolved Florida core classification withholds the total")
    func artHistoryEligibility() {
        let titles = ["Art History", "AP Art History", "APHISART", "IB Art History", "AICE Art History"]
        for title in titles {
            let courses = [course(1, "English", 10, "95"), course(2, title, 10, "80")]
            let uga = CollegeGPACalculator.calculate(profile: weightedProfile(.ugaWeighted), courses: courses, asOf: date)
            let ugaBonus = title == "AP Art History" || title == "APHISART" || title == "IB Art History"
            #expect(uga.records.map(\.points) == [4, ugaBonus ? 4 : 3])
            #expect(uga.value != nil && uga.omittedRecords.isEmpty)
            let uf = CollegeGPACalculator.calculate(profile: weightedProfile(.ufWeighted), courses: courses, asOf: date)
            if title == "Art History" {
                #expect(uf.value == nil && uf.unweightedValue == nil)
                #expect(uf.omittedRecords.map(\.courseName) == [title])
            } else {
                #expect(uf.value == 4 && uf.records.count == 2)
            }
            for method in [CollegeGPAMethod.fsuWeighted, .ucfWeighted] {
                let result = CollegeGPACalculator.calculate(profile: weightedProfile(method), courses: courses, asOf: date)
                #expect(result.value == nil && result.unweightedValue == nil && result.standing == nil)
                #expect(result.records.count == 1 && result.omittedRecords.map(\.courseName) == [title])
                #expect(result.unavailableReason == "Course eligibility is unverified.")
                #expect(result.calculationNotes.contains { $0.contains("Art History") && $0.contains("not verified") })
            }
        }
        // The caveat concerns core admission methods, not a blanket arts ban.
        let uc = CollegeGPACalculator.calculate(profile: profile("ucla"), courses: [course(1, "APHISART", 10, "90")], asOf: date)
        #expect(uc.value == 5 && uc.omittedRecords.isEmpty)
        for method in [CollegeGPAMethod.ufWeighted, .fsuWeighted, .ucfWeighted] {
            let mixed = CollegeGPACalculator.calculate(profile: weightedProfile(method), courses: [
                course(1, "Art History", 10, "100"), course(2, "English", 10, "80")], asOf: date)
            #expect(mixed.records.map(\.points) == [3])
            #expect(mixed.omittedRecords.map(\.percentage) == [100])
            #expect(mixed.value == nil && mixed.unweightedValue == nil && mixed.displayValue == "—")
        }
    }

    @Test("Exact catalog short codes preserve core subjects and explicit AP weighting")
    func catalogAliases() {
        let names = ["APUSH", "APENG3", "ALG2", "GEOM", "BIO", "CHEM", "GOVT", "APMACECO", "APCALCBC",
            "AP Macroeconomics", "AP Microeconomics"]
        let courses = names.enumerated().map { course($0.offset, $0.element, 10, "95") }
        for p in [weightedProfile(.ugaWeighted), weightedProfile(.ufWeighted), weightedProfile(.fsuWeighted),
                  weightedProfile(.ucfWeighted), profile("ucla")] {
            let result = CollegeGPACalculator.calculate(profile: p, courses: courses, asOf: date)
            #expect(result.records.map(\.points) == [5, 5, 4, 4, 4, 4, 4, 5, 5, 5, 5])
            #expect(result.value != nil && result.omittedRecords.isEmpty)
        }
        #expect(!CollegeGPACalculator.isExplicitAPOrIB("Applied Music"))
        #expect(!CollegeGPACalculator.isExplicitAPOrIB("APUSH invented suffix"))
        #expect(!CollegeGPACalculator.isExplicitAPOrIB("Pre-AP APUSH"))
        #expect(!CollegeGPACalculator.isExplicitAPOrIB("PreAP Biology"))
    }

    @Test("Known noncore classes do not make academic-core estimates unavailable")
    func knownNoncoreSubjects() {
        let excluded = ["Soccer", "Baseball", "Softball", "Track", "Golf", "Swimming", "Cross Country",
            "Cheerleading", "Personal Fitness", "Team Sports", "Yoga", "Guitar", "MUS1GTR", "Office Aide",
            "Peer Partners", "MAPS", "Robotics III", "Engineering", "Personal Financial Literacy", "TACS2"]
        let courses = [course(100, "English", 10, "95")] + excluded.enumerated().map { course($0.offset, $0.element, 10, "60") }
        for method in [CollegeGPAMethod.ugaWeighted, .ufWeighted, .fsuWeighted, .ucfWeighted] {
            let result = CollegeGPACalculator.calculate(profile: weightedProfile(method), courses: courses, asOf: date)
            #expect(result.value == 4)
            #expect(result.records.count == 1 && result.omittedRecords.count == excluded.count)
        }
    }

    @Test("AP computer-science aliases stay electives; UCF has core-only weighting and withholds uncertain low bonuses")
    func ucfCoreAndCutoff() {
        let courses = [course(1, "APCSP", 10, "95"), course(2, "APTACSA", 10, "95"), course(3, "English H", 10, "95")]
        let uf = CollegeGPACalculator.calculate(profile: weightedProfile(.ufWeighted), courses: courses, asOf: date)
        #expect(uf.records.map(\.points) == [5, 5, 4.5])
        for method in [CollegeGPAMethod.ugaWeighted, .fsuWeighted, .ucfWeighted] {
            let result = CollegeGPACalculator.calculate(profile: weightedProfile(method), courses: courses, asOf: date)
            #expect(result.records.count == 1 && result.omittedRecords.count == 2)
            #expect(result.value == (method == .ugaWeighted ? 4 : 4.5))
        }
        let low = CollegeGPACalculator.calculate(profile: profile("ucf"), courses: [
            course(1, "English H", 10, "69"), course(2, "AP Biology", 10, "95")], asOf: date)
        #expect(low.value == nil && low.records.count == 2)
        #expect(low.unavailableReason == "Bonus treatment for lower grades is unverified.")
        let regular = CollegeGPACalculator.calculate(profile: profile("ucf"), courses: [course(1, "English", 10, "60")], asOf: date)
        #expect(regular.value == 1)
    }

    @Test("UC omits known nonacademic courses but retains arts and discloses remaining A–G uncertainty")
    func ucSubjectExclusions() {
        let excluded = ["PE", "Athletics", "Girls Soccer", "Health", "HLTH ED", "Office Aide", "MAPS"]
        let courses = [course(100, "APBIO2", 10, "95"), course(101, "Art 1", 10, "80"),
            course(102, "MUS1GTR", 10, "80"), course(103, "APCSP", 10, "95")]
            + excluded.enumerated().map { course($0.offset, $0.element, 10, "100") }
        let weighted = CollegeGPACalculator.calculate(profile: profile("ucla"), courses: courses, asOf: date)
        #expect(weighted.records.map(\.points) == [5, 3, 3, 5])
        #expect(weighted.value == 4 && weighted.omittedRecords.count == excluded.count)
        #expect(weighted.calculationNotes.contains { $0.contains("A–G eligibility is unverified") })
        #expect(weighted.calculationNotes.contains { $0.contains("7 completed") })
        let unweighted = CollegeGPACalculator.calculate(profile: profile("berkeley"), courses: courses, asOf: date)
        #expect(unweighted.value == 3.5 && unweighted.omittedRecords.count == excluded.count)
        let uncertain = CollegeGPACalculator.calculate(profile: profile("ucla"), courses: [
            course(1, "Principles of Health Science", 10, "90"), course(2, "Independent Study", 10, "80")], asOf: date)
        #expect(uncertain.records.count == 2 && uncertain.omittedRecords.isEmpty)
        #expect(uncertain.calculationNotes.contains { $0.contains("unverified") })
    }

    @Test("Published scales never match a generic unweighted estimate to weighted cohort statistics")
    func incompatibleSourceScales() {
        var generic = profile("princeton")
        generic.publishedGPAScale = .weighted
        #expect(CollegeGPAStanding.compare(4, profile: generic)?.cohortContext == nil)
        #expect(CollegeGPAStanding.compare(4, profile: generic)?.sameBandPercent == nil)
        var weighted = weightedProfile(.ufWeighted)
        weighted.publishedGPAScale = .unweighted
        #expect(CollegeGPAStanding.compare(4, profile: weighted)?.cohortContext == nil)
        #expect(CollegeGPAMethod.ugaWeighted.gradeYears == nil)
        #expect(CollegeGPAMethod.fsuWeighted.maximum == 5)
    }

    @Test("Expanded catalog preserves unique identities and independently validates published GPA scales")
    func catalogScaleIntegrity() {
        let profiles = CollegeProfileCatalog.profiles
        #expect(profiles.count >= 64)
        #expect(Set(profiles.map(\.id)).count == profiles.count)
        for p in profiles {
            #expect(p.sourceURL.scheme == "https")
            let limit = p.publishedGPAScale == .unweighted ? 4.0 : 5.0
            if let mean = p.reportedMean { #expect(mean.isFinite && (0...limit).contains(mean)) }
            if let q = p.quartiles {
                #expect(q.lower.isFinite && q.upper.isFinite)
                #expect(q.lower >= 0 && q.lower <= q.upper && q.upper <= limit)
                if let median = q.median { #expect((q.lower...q.upper).contains(median)) }
            }
            if let coverage = p.reportingPercent { #expect((0...100).contains(coverage)) }
        }
        #expect(profile("georgia").method == .ugaWeighted)
        #expect(profile("florida").method == .ufWeighted)
        #expect(profile("florida-state").method == .fsuWeighted)
        #expect(profile("ucf").publishedGPAScale == .weighted)
        #expect(profile("ucf").method == .ucfWeighted)
        #expect(profile("ucf").definitionSourceURL != nil)
        #expect(profile("ucla").publishedGPAScale == .weighted)
        #expect(profile("berkeley").publishedGPAScale == .unweighted)
    }

    private func course(_ id: Int, _ name: String, _ year: Int, _ sm1: String?,
                        academicYear: String = "2025-2026") -> UnifiedCourseData {
        let grades = HistoricalGrades(pr1: nil, pr2: nil, pr3: nil, pr4: nil, pr5: nil, pr6: nil, pr7: nil, pr8: nil,
            rc1: nil, rc2: nil, rc3: nil, rc4: nil, ex1: nil, ex2: nil, sm1: sm1, sm2: nil, finalGrade: nil)
        return UnifiedCourseData(courseId: nil, corNumId: "", stuId: "", section: "", gbId: "", courseName: name,
            instructor: nil, period: nil, time: nil, semester: .fall, termLength: "1 - 2", gradeYear: year,
            currentScores: [], historicalGrades: grades, academicYear: academicYear, historyRowKey: "synthetic-\(id)",
            academicYearIsVerified: true, isTranscriptRecord: true, postedHistoricalGrades: grades)
    }
}

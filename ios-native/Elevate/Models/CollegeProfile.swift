import Foundation

enum CollegeProfilePopulation: String, Hashable {
    case admitted = "Admitted first-year students"
    case enrolled = "Enrolled first-year students reporting GPA"
    case publishedProfile = "Published first-year class profile"
    case admissionsGuidance = "Admissions guidance"
    var sentenceDescription: String {
        switch self {
        case .admitted: return "admitted first-year students"
        case .enrolled: return "enrolled first-year students reporting GPA"
        case .publishedProfile: return "published first-year class profile"
        case .admissionsGuidance: return "admissions guidance"
        }
    }
}

/// Admissions GPA, never the university's grading scale for its own students.
enum CollegeGPAMethod: String, Hashable {
    case ucFullyWeighted, ucUnweighted, reported4Point
    case ugaWeighted, ufWeighted, fsuWeighted, ucfWeighted
    var hasPublishedCalculation: Bool { self != .reported4Point }
    var usesAcademicCore: Bool { [.ugaWeighted, .ufWeighted, .fsuWeighted, .ucfWeighted].contains(self) }
    var title: String {
        switch self {
        case .ucFullyWeighted: return "UC fully weighted estimate"
        case .ucUnweighted: return "UC unweighted estimate"
        case .reported4Point: return "4.0 comparison estimate"
        case .ugaWeighted: return "UGA weighted estimate"
        case .ufWeighted: return "UF weighted estimate"
        case .fsuWeighted: return "FSU weighted estimate"
        case .ucfWeighted: return "UCF weighted estimate"
        }
    }
    var maximum: Double { isUnweighted ? 4 : 5 }
    var isUnweighted: Bool { self == .ucUnweighted || self == .reported4Point }
    var gradeYears: Set<Int>? { self == .ucFullyWeighted || self == .ucUnweighted ? [10, 11] : nil }
    var yearsLabel: String { gradeYears == nil ? "Grades 9–12" : "Grades 10–11" }
    var explanation: String {
        let common = "Only completed semesters count, equally because course credits aren't available. Numeric grades use 90 = A, 80 = B, 70 = C, 60 = D, below 60 = F, without rounding or plus/minus grades. GPA is shown to two decimals without rounding up; comparisons use the full value. This is an estimate, not an official admissions GPA."
        switch self {
        case .ucFullyWeighted:
            return common + " UC uses grades 10–11. For students outside California, AP/IB courses with C or better receive one additional point; school-designated Honors courses receive none. This fully weighted profile has no eight-semester cap. Course names identify AP/IB; UC subject and course eligibility and summer grade-year placement aren't verified."
        case .ucUnweighted:
            return common + " UC uses grades 10–11 with no honors bonus. UC subject eligibility and summer grade-year placement aren't verified. Berkeley's published weighted range doesn't specify its cap, so this comparison uses its unweighted range."
        case .reported4Point:
            return common + " Elevate has not verified a complete admissions recalculation formula from the linked source. The legacy generic conversion normalizes completed grades to 4.0 without an AP/Honors bonus. The published cohort may use different course selection, credits or weighting. Published class statistics describe that cohort, not your individual percentile."
        case .ugaWeighted:
            return common + " UGA uses academic core courses, including AP Art and Music Theory. AP/IB receive +1; Honors and dual enrollment receive no bonus. Course names provide an approximate subject and level classification. UGA uses your school's official letter-grade scale; Elevate's numeric conversion is an assumption. Elevate withholds the estimate when a subject is unrecognized or an AP/IB grade is below C because its bonus treatment has not been verified. No bonus cap is applied."
        case .ufWeighted:
            return common + " UF uses academic core courses plus AP/IB/AICE electives. AP/IB/AICE and core dual enrollment receive +1; Honors and pre-AP/pre-IB/pre-AICE receive +0.5. Names provide an approximate subject and level classification. Elevate withholds the estimate when a subject is unrecognized or a bonus-eligible grade is below C because its bonus treatment has not been verified. No bonus cap is applied."
        case .fsuWeighted:
            return common + " FSU uses academic core courses. AP/IB/AICE and dual enrollment receive +1; Honors and pre-AP/pre-IB/pre-AICE receive +0.5, only for C or better. Lower grades remain in the average without a bonus. Names provide an approximate subject and level classification; unrecognized subjects make the estimate unavailable. No bonus cap is applied."
        case .ucfWeighted:
            return common + " UCF uses academic core courses. AP/IB/AICE and dual enrollment receive +1; Honors and pre-AP/pre-IB/pre-AICE receive +0.5. Names provide an approximate subject and level classification. Elevate withholds the estimate when a subject is unrecognized or a bonus-eligible grade is below C because its bonus treatment has not been verified. No bonus cap is applied."
        }
    }
}

struct CollegeGPAQuartiles: Hashable {
    var lower: Double
    var median: Double?
    var upper: Double
}

struct CollegeGPABand: Identifiable, Hashable {
    var id: String { label }
    var label: String
    var minimum: Double
    /// Exclusive upper bound; nil identifies the exact capped 4.0 band.
    var maximum: Double?
    var percent: Double
    func contains(_ value: Double) -> Bool {
        if let maximum { return value >= minimum && value < maximum }
        return value == minimum
    }
}

/// Describes the published class figures, separately from the student's estimate.
enum CollegePublishedGPAScale: String, Hashable {
    case unweighted, weighted, unspecified
    var title: String {
        switch self {
        case .unweighted: return "Unweighted GPA"
        case .weighted: return "Weighted GPA"
        case .unspecified: return "Reported GPA"
        }
    }
}

struct CollegeProfile: Hashable, Identifiable {
    var id: String
    var name: String
    var cohort: String
    var population: CollegeProfilePopulation
    var method: CollegeGPAMethod
    var sourceURL: URL
    var definitionSourceURL: URL? = nil
    var verifiedOn: String = "2026-10-04"
    var quartiles: CollegeGPAQuartiles? = nil
    var bands: [CollegeGPABand] = []
    var reportedMean: Double? = nil
    var reportingPercent: Double? = nil
    var searchAliases: [String] = []
    /// Official guidance is not a class distribution or an admissions cutoff.
    var publishedSummary: String? = nil
    /// Source scope, missing statistics, or a published scale's comparability limits.
    var publicationNote: String? = nil
    var publishedGPAScale: CollegePublishedGPAScale = .unspecified
    var hasPublishedStatistics: Bool { quartiles != nil || !bands.isEmpty || reportedMean != nil }
}

/// A small, offline catalog of primary publications. Cohorts never establish
/// admissions odds. Private-college formulas are undisclosed; don't invent them.
enum CollegeProfileCatalog {
    /// Local search over verified profiles; no query-dependent network request.
    static func search(_ query: String, in profiles: [CollegeProfile] = CollegeProfileCatalog.profiles) -> [CollegeProfile] {
        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let tokens = normalized(String(query.prefix(256))).split(separator: " ").map(String.init)
        return profiles.filter { profile in
            let fields = ([profile.name] + profile.searchAliases).map(normalized)
            return tokens.allSatisfy { token in fields.contains { $0.contains(token) } }
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }
    private static let ucPolicy = URL(string: "https://admission.universityofcalifornia.edu/admission-requirements/first-year-requirements/gpa-requirement.html")!
    private static func distribution(_ percentages: [Double]) -> [CollegeGPABand] {
        let labels = ["4.0", "3.75–3.99", "3.50–3.74", "3.25–3.49", "3.00–3.24", "2.50–2.99", "2.00–2.49", "1.00–1.99", "Below 1.00"]
        let minima = [4.0, 3.75, 3.5, 3.25, 3.0, 2.5, 2.0, 1.0, 0.0]
        return percentages.enumerated().map { index, percent in
            CollegeGPABand(label: labels[index], minimum: minima[index], maximum: index == 0 ? nil : minima[index - 1], percent: percent)
        }
    }
    static let profiles: [CollegeProfile] = (baseProfiles + expandedProfiles + CollegeAdmissionsCatalog.additions).sorted {
        let comparison = $0.name.localizedStandardCompare($1.name)
        return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
    }
    private static let baseProfiles: [CollegeProfile] = [
        CollegeProfile(id: "arizona-state", name: "Arizona State", cohort: "Current admissions guidance", population: .admissionsGuidance, method: .reported4Point,
            sourceURL: URL(string: "https://admission.asu.edu/apply/first-year/admission")!,
            searchAliases: ["ASU", "Arizona State University"],
            publishedSummary: "A 3.00 unweighted GPA in competency courses is one alternative aptitude route.",
            publicationNote: "This is an admissions requirement option, not a class GPA distribution or a guarantee of admission. Elevate's all-subject estimate does not verify competency-course eligibility."),
        CollegeProfile(id: "boston-university", name: "Boston University", cohort: "Fall 2025", population: .enrolled, method: .reported4Point,
            sourceURL: URL(string: "https://www.bu.edu/asir/files/2026/07/CDS-2025-2026-C-updated.pdf")!,
            bands: distribution([36, 36, 27, 1, 0, 0, 0, 0, 0]), reportedMean: 3.86, reportingPercent: 100,
            searchAliases: ["BU", "Boston U"], publicationNote: "2025–26 Common Data Set, sections C11/C12. A reported 4.0 scale does not establish an unweighted admissions formula."),
        CollegeProfile(id: "case-western", name: "Case Western Reserve", cohort: "Fall 2025", population: .enrolled, method: .reported4Point,
            sourceURL: URL(string: "https://case.edu/ir/sites/default/files/2026-02/CDS%202025-26%20Adjusted%20Final.pdf")!,
            bands: distribution([16.4, 48.2, 25.7, 7.7, 1.7, 0.3]), reportedMean: 3.78, reportingPercent: 92,
            searchAliases: ["CWRU", "Case Western Reserve University"],
            publicationNote: "Adjusted final 2025–26 Common Data Set, sections C11/C12. Blank lower bands remain unavailable; reported course selection and weighting may differ from Elevate's estimate."),
        CollegeProfile(id: "hopkins", name: "Johns Hopkins", cohort: "Fall 2025", population: .enrolled, method: .reported4Point,
            sourceURL: URL(string: "https://oira.jhu.edu/wp-content/uploads/2025-2026-CDS-Johns-Hopkins-University-v2.pdf")!,
            bands: distribution([66.09, 25.36, 5.53, 2.04, 0.76, 0.23]), reportedMean: 3.93, reportingPercent: 95.86,
            searchAliases: ["JHU", "Johns Hopkins University"]),
        CollegeProfile(id: "mit", name: "MIT", cohort: "2025–26 publication", population: .publishedProfile, method: .reported4Point,
            sourceURL: URL(string: "https://ir.mit.edu/projects/2025-26-common-data-set/")!,
            searchAliases: ["Massachusetts Institute of Technology"],
            publicationNote: "The 2025–26 Common Data Set marks GPA distribution and average as unavailable. This source provides no GPA comparison for MIT."),
        CollegeProfile(id: "princeton", name: "Princeton", cohort: "Fall 2025", population: .enrolled, method: .reported4Point,
            sourceURL: URL(string: "https://ir.princeton.edu/sites/g/files/toruqf2041/files/documents/CDS_2526_Princeton_v2.pdf")!,
            bands: distribution([72, 24, 3, 1]), reportedMean: 3.96, reportingPercent: 99, searchAliases: ["Princeton University"]),
        CollegeProfile(id: "purdue", name: "Purdue", cohort: "2025 published profile", population: .publishedProfile, method: .reported4Point,
            sourceURL: URL(string: "https://admissions.purdue.edu/become-student/class-profile/")!,
            quartiles: CollegeGPAQuartiles(lower: 3.70, median: nil, upper: 4.00), searchAliases: ["Purdue University"],
            publicationNote: "For reporting after the admission cycle, Purdue converts GPA to an unweighted 4.00 scale. The page's class/admits wording does not establish a single population or reporting coverage. GPA is not used as an admission factor; this is a published class summary, not an admissions formula."),
        CollegeProfile(id: "stanford", name: "Stanford", cohort: "Fall 2025", population: .enrolled, method: .reported4Point,
            sourceURL: URL(string: "https://drive.google.com/file/d/1GIPKgVj1d86dkmLkHI_mZVCk_iY6kiCp/view")!,
            bands: distribution([72.97, 16.17, 7.89, 2.89, 0.08]), reportedMean: 3.94, reportingPercent: 69.60, searchAliases: ["Stanford University"]),
        CollegeProfile(id: "berkeley", name: "UC Berkeley", cohort: "Fall 2026", population: .admitted, method: .ucUnweighted,
            sourceURL: URL(string: "https://admissions.berkeley.edu/apply-to-berkeley/student-profile/")!, definitionSourceURL: ucPolicy,
            quartiles: CollegeGPAQuartiles(lower: 3.90, median: nil, upper: 4.00), searchAliases: ["University of California Berkeley", "Cal", "UCB"], publishedGPAScale: .unweighted),
        CollegeProfile(id: "ucla", name: "UCLA", cohort: "Fall 2025", population: .admitted, method: .ucFullyWeighted,
            sourceURL: URL(string: "https://admission.ucla.edu/apply/first-year/first-year-profile/2025")!, definitionSourceURL: ucPolicy,
            quartiles: CollegeGPAQuartiles(lower: 4.44, median: 4.61, upper: 4.78), searchAliases: ["University of California Los Angeles", "UC Los Angeles"], publishedGPAScale: .weighted),
        CollegeProfile(id: "arizona", name: "University of Arizona", cohort: "Fall 2024", population: .enrolled, method: .reported4Point,
            sourceURL: URL(string: "https://uair.arizona.edu/sites/default/files/2025-03/CDS-2024-2025-FINAL.pdf")!,
            bands: distribution([14, 24, 17, 14, 12, 17, 2]), reportedMean: 3.47, reportingPercent: 97.5,
            searchAliases: ["U of A", "UArizona", "Arizona"],
            publicationNote: "Historical 2024–25 Common Data Set, sections C11/C12; this is the verified usable dataset, not a claim that no newer publication exists. Blank lower bands remain unavailable; reported weighting may differ."),
        CollegeProfile(id: "illinois", name: "University of Illinois Urbana-Champaign", cohort: "Rolling three-year admitted profile", population: .admitted, method: .reported4Point,
            sourceURL: URL(string: "https://www.admissions.illinois.edu/class-profile/")!,
            quartiles: CollegeGPAQuartiles(lower: 3.70, median: nil, upper: 4.00), searchAliases: ["UIUC", "Illinois", "U of I", "Urbana Champaign"],
            publicationNote: "The published middle 50% covers admitted students over the past three years. The page does not specify the exact year span, reporting coverage or weighting, so it is not a verified match to Elevate's unweighted scale."),
        CollegeProfile(id: "pittsburgh", name: "University of Pittsburgh", cohort: "2025–26 publication", population: .publishedProfile, method: .reported4Point,
            sourceURL: URL(string: "https://www.ir.pitt.edu/sites/default/files/2026-02/CDS_2025-2026_PGH-UA_0.pdf")!,
            searchAliases: ["Pitt", "Pittsburgh"],
            publicationNote: "Pittsburgh campus 2025–26 Common Data Set, sections C11/C12, contains unfilled GPA fields. No GPA distribution, average or reporting coverage is available; blank templates are not zero values."),
        CollegeProfile(id: "wisconsin", name: "University of Wisconsin–Madison", cohort: "Current admissions guidance", population: .admissionsGuidance, method: .reported4Point,
            sourceURL: URL(string: "https://admissions.wisc.edu/apply-as-a-freshman/")!,
            searchAliases: ["UW Madison", "Wisconsin", "Wisc", "University of Wisconsin Madison"],
            publishedSummary: "The admissions page describes a typical unweighted academic GPA of 3.8–4.0.",
            publicationNote: "This is guidance, not a published middle-50% range. The page does not identify a source cohort or reporting coverage, and Elevate does not verify the university's academic-course selection."),
        CollegeProfile(id: "vanderbilt", name: "Vanderbilt", cohort: "Fall 2025", population: .enrolled, method: .reported4Point,
            sourceURL: URL(string: "https://cdn.vanderbilt.edu/vu-wpfsx/wp-content/uploads/sites/70/2026/07/CDS_2025-2026.xlsx")!,
            bands: distribution([31.6, 56.6, 9.1, 1.4, 0.6, 0.6, 0.1, 0, 0]), reportedMean: 3.895, reportingPercent: 99.8,
            searchAliases: ["Vanderbilt University", "Vandy"]),
        CollegeProfile(id: "yale", name: "Yale", cohort: "2025–26 publication", population: .publishedProfile, method: .reported4Point,
            sourceURL: URL(string: "https://oir.yale.edu/sites/default/files/yale_cds_2025-26_md_20260410_0.pdf")!,
            searchAliases: ["Yale University"],
            publicationNote: "2025–26 Common Data Set, sections C11/C12, leaves GPA fields blank. Template totals are not evidence of zero GPA or zero reporting coverage; published GPA statistics are unavailable."),
    ]
}

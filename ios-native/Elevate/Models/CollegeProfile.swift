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


import Foundation

/// Local planning records never modify Skyward courses, grades, or GPA inputs.
struct CoursePlan: Codable, Equatable {
    var earnedCourses: [CoursePlanCourse] = []
    var plannedCourses: [CoursePlanCourse] = []
    var path: CoursePlanPath = .westlakeDistinguished
    var checkedRequirements: Set<CoursePlanChecklistItem> = []
    var creditOverrides: [TranscriptCreditOverride] = []

    init(earnedCourses: [CoursePlanCourse] = [], plannedCourses: [CoursePlanCourse] = [],
         path: CoursePlanPath = .westlakeDistinguished, checkedRequirements: Set<CoursePlanChecklistItem> = [],
         creditOverrides: [TranscriptCreditOverride] = []) {
        self.earnedCourses = earnedCourses
        self.plannedCourses = plannedCourses
        self.path = path
        self.checkedRequirements = checkedRequirements
        self.creditOverrides = creditOverrides
    }

    private enum CodingKeys: String, CodingKey {
        case earnedCourses, plannedCourses, path, checkedRequirements, creditOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        earnedCourses = try container.decode([CoursePlanCourse].self, forKey: .earnedCourses)
        plannedCourses = try container.decode([CoursePlanCourse].self, forKey: .plannedCourses)
        path = try container.decode(CoursePlanPath.self, forKey: .path)
        checkedRequirements = try container.decode(Set<CoursePlanChecklistItem>.self, forKey: .checkedRequirements)
        creditOverrides = try container.decodeIfPresent([TranscriptCreditOverride].self, forKey: .creditOverrides) ?? []
    }

    var isValidForStorage: Bool {
        let records = earnedCourses + plannedCourses
        return records.count <= 500 && Set(records.map(\.id)).count == records.count && records.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 256 &&
            $0.credits.isFinite && $0.credits > 0 && $0.credits <= 4 &&
            ($0.score.map { $0.isFinite && $0 >= 0 && $0 <= AcademicScoreValue.magnitudeLimit } ?? true) &&
            ($0.academicYear.map { AcademicYearKey.startYear($0) != nil } ?? true) &&
            ($0.semester.map(\.isSemester) ?? true)
        } && creditOverrides.count <= 500 && Set(creditOverrides.map(\.id)).count == creditOverrides.count &&
            creditOverrides.allSatisfy { !$0.id.isEmpty && $0.id.utf8.count <= 16_384 && $0.credits.isFinite && (0...4).contains($0.credits) }
    }
}

/// One GPA-bearing planned record represents one semester. Credits are an
/// explicit allocation to a single subject; no course-name classification occurs.
struct CoursePlanCourse: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var credits: Double
    var subject: CoursePlanSubject
    var level: CoursePlanLevel = .regular
    var score: Double? = nil
    var excludedFromGPA: Bool = false
    /// True is an explicit missing-course supplement. Older aggregate/manual
    /// records decode nil and require reconciliation when transcript rows exist.
    var isSupplemental: Bool? = nil
    /// Optional future scope disambiguates a repeated course from current enrollment.
    var academicYear: String? = nil
    var semester: TermLabel? = nil
}

enum CoursePlanSubject: String, Codable, CaseIterable, Identifiable {
    case english, math, science, socialStudies, worldLanguage
    case physicalEducation, health, fineArts, elective
    var id: String { rawValue }
    var title: String {
        switch self {
        case .english: return "English"
        case .math: return "Mathematics"
        case .science: return "Science"
        case .socialStudies: return "Social studies"
        case .worldLanguage: return "World language"
        case .physicalEducation: return "Physical education"
        case .health: return "Health"
        case .fineArts: return "Fine arts"
        case .elective: return "Electives"
        }
    }
}

enum CoursePlanLevel: String, Codable, CaseIterable, Identifiable {
    case regular, honors, ap
    var id: String { rawValue }
    var title: String { courseLevel.rawValue }
    var courseLevel: CourseLevel {
        switch self {
        case .regular: return .regular
        case .honors: return .honors
        case .ap: return .ap
        }
    }
}

enum CoursePlanPath: String, Codable, CaseIterable, Identifiable {
    case westlakeDistinguished
    var id: String { rawValue }
    var title: String { "Westlake distinguished pathway" }
    var detail: String { "Foundation + Multidisciplinary Endorsement with Distinguished Level of Achievement" }
    var totalRequired: Double { 26 }
    var source: CoursePlanSource { .westlakeRequirements }
    var requirements: [(subject: CoursePlanSubject, credits: Double)] {
        [(.english, 4), (.math, 4), (.science, 4), (.socialStudies, 4),
         (.worldLanguage, 2), (.physicalEducation, 1), (.health, 0.5),
         (.fineArts, 1), (.elective, 5.5)]
    }
}

struct CoursePlanSource: Identifiable {
    var id: String { url }
    var title: String
    var url: String
    var checkedOn: String
    var scope: String
    static let westlakeRequirements = CoursePlanSource(
        title: "Westlake graduation requirements",
        url: "https://whs.eanesisd.net/coursecatalog/info/graduation-requirements",
        checkedOn: "2026-10-04",
        scope: "Current online catalog linked by 2026–27 course selection resources; confirm your entering cohort with a counselor."
    )
    static let texasToolkit = CoursePlanSource(
        title: "TEA 2025 Graduation Toolkit",
        url: "https://tea.texas.gov/about-tea/newsroom/brochures/tea-graduation-toolkit-2025.pdf",
        checkedOn: "2026-10-04",
        scope: "Pages 4–7 and 9: state credits, endorsements, additional requirements and distinguished achievement; cohort rules may vary."
    )
    static let courseSelection = CoursePlanSource(
        title: "Westlake 2026–27 course selection resources",
        url: "https://sites.google.com/eanesisd.net/westlakecounseling/course-selection/course-selection-resources",
        checkedOn: "2026-10-04",
        scope: "2026–27 selection resources link the online course catalog and require the separate Skyward Career Plan."
    )
    static let athleticsCatalog = CoursePlanSource(
        title: "Westlake athletics course credits",
        url: "https://whs.eanesisd.net/coursecatalog/courses/health-and-physical-education/athletics",
        checkedOn: "2026-10-06",
        scope: "Sports course names and codes; Athletic Training/Sports Medicine earns elective credit and does not satisfy the state PE requirement."
    )
}

/// Personal confirmations only. The calculator does not verify these against
/// student records, and checking every item never certifies graduation.
enum CoursePlanChecklistItem: String, Codable, CaseIterable, Identifiable {
    case cohortAndCreditEligibility, requiredCourseSequence, sameWorldLanguage
    case algebraII, multidisciplinaryEndorsement, endOfCourseExams
    case speech, cprAndAED, peaceOfficerInstruction, financialAid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cohortAndCreditEligibility: return "Counselor confirmed cohort rules and credit eligibility"
        case .requiredCourseSequence: return "Required named courses and substitutions reviewed"
        case .sameWorldLanguage: return "Two credits in the same world language reviewed"
        case .algebraII: return "Algebra II completion reviewed"
        case .multidisciplinaryEndorsement: return "Multidisciplinary endorsement requirements reviewed"
        case .endOfCourseExams: return "EOC exams or approved alternatives reviewed"
        case .speech: return "Speech proficiency requirement reviewed"
        case .cprAndAED: return "CPR and applicable AED instruction reviewed"
        case .peaceOfficerInstruction: return "Peace officer interaction instruction reviewed"
        case .financialAid: return "Financial aid application or applicable opt-out reviewed"
        }
    }
}

struct CoursePlanRequirementProgress: Identifiable {
    var subject: CoursePlanSubject
    var required: Double
    var earned: Double
    var planned: Double
    var current: Double = 0
    var id: String { subject.rawValue }
    var combined: Double { earned + current + planned }
    var earnedRemaining: Double { max(0, required - earned) }
    var remaining: Double { max(0, required - combined) }
}

enum CoursePlanGPAPolicy: String, CaseIterable, Identifiable {
    case districtPercentage, districtWeightedPercentage, generic4Point, generic5Point
    var id: String { rawValue }
    var title: String {
        switch self {
        case .districtPercentage: return "District unweighted percentage"
        case .districtWeightedPercentage: return "District weighted percentage"
        case .generic4Point: return "Generic 4.0 unweighted"
        case .generic5Point: return "Generic 5.0 weighted"
        }
    }
    var explanation: String {
        switch self {
        case .districtPercentage: return "Average of semester percentages, using Elevate's district calculation policy."
        case .districtWeightedPercentage: return "Average of semester percentages with +10 AP-level or +5 Honors, capped at 110 per record, using Elevate's district calculation policy."
        case .generic4Point: return GPAConversionPolicy.unweighted4Point.explanation
        case .generic5Point: return GPAConversionPolicy.weighted5Point.explanation
        }
    }
    func points(score: Double, level: CourseLevel) -> Double? {
        guard score.isFinite, score >= 0, score <= AcademicScoreValue.magnitudeLimit else { return nil }
        switch self {
        case .districtPercentage: return score
        case .districtWeightedPercentage: return min(score + level.gpaBonus, 110)
        case .generic4Point: return GPAConversionPolicy.unweighted4Point.points(for: score, level: level)
        case .generic5Point: return GPAConversionPolicy.weighted5Point.points(for: score, level: level)
        }
    }
}

struct CoursePlanGPAProjection: Identifiable {
    var policy: CoursePlanGPAPolicy
    var officialBaseline: Double?
    var projected: Double?
    var officialCount: Int
    var plannedCount: Int
    var skippedPlannedCount: Int
    var id: String { policy.rawValue }
}

enum CoursePlanIssueReason: String {
    case invalidCredits = "Credits must be finite, greater than zero and no more than 4 per record."
    case emptyName = "Course name is required."
    case duplicateID = "Duplicate planning identity; all matching records are excluded."
    case invalidScore = "Expected grade is invalid and excluded from GPA."
    case missingScore = "No expected semester grade; excluded from GPA."
    case excludedFromGPA = "Excluded from projected GPA by your choice."
    case currentEnrollmentOverlap = "This planned course matches current enrollment. Confirm a different future school year or semester before counting it again."
    case invalidScope = "Use a verified school-year format and a semester for the planned course scope."
}

struct CoursePlanIssue: Identifiable {
    var id: String
    var courseID: UUID
    var courseName: String
    var isPlanned: Bool
    var reason: CoursePlanIssueReason
}

struct CoursePlanReport {
    var path: CoursePlanPath
    var requirements: [CoursePlanRequirementProgress]
    var earnedTotal: Double
    var plannedTotal: Double
    var currentTotal: Double
    var currentCourses: [CurrentCourseCredit]
    var manualPlannedReviewCourses: [CoursePlanCourse]
    var gpa: [CoursePlanGPAProjection]
    var issues: [CoursePlanIssue]
    var officialSkippedCount: Int
    var checkedRequirements: Set<CoursePlanChecklistItem>
    var transcriptCredits: TranscriptCreditReport
    var manualEarnedCourses: [CoursePlanCourse]
    var manualReviewCourses: [CoursePlanCourse]
    var combinedTotal: Double { earnedTotal + currentTotal + plannedTotal }
    var remainingTotal: Double { max(0, path.totalRequired - combinedTotal) }
    var earnedRemainingTotal: Double { max(0, path.totalRequired - earnedTotal) }
    /// Numeric planning status only; named courses/checklist are independent.
    var creditTargetsCovered: Bool { remainingTotal == 0 && requirements.allSatisfy { $0.remaining == 0 } }
    var uncheckedRequirements: [CoursePlanChecklistItem] {
        CoursePlanChecklistItem.allCases.filter { !checkedRequirements.contains($0) }
    }
    var sources: [CoursePlanSource] { [path.source, .athleticsCatalog, .texasToolkit, .courseSelection] }
    var creditExplanation: String {
        "Earned credits are estimated automatically from posted transcript semesters and the district course catalog, with your corrections and confirmed missing-course additions. The endpoint does not supply awarded credit values. Unknown or conflicting records need review. Current and planned credits assume successful completion and eligibility; current enrollment is separate from earned credit. Credit totals do not establish required course sequences, an endorsement, or graduation eligibility."
    }
    var gpaExplanation: String {
        "Baseline uses completed posted high-school semester grades. Projected GPA adds only planned semester grades; each record counts equally, regardless of credits. Enter each semester separately. Manual earned entries count credits only, preventing them from duplicating imported grades. Missing, invalid and excluded planned grades are skipped. These are local estimates, not an official GPA or college admissions calculation."
    }
}

enum CoursePlanner {
    private static func isFutureAcademicYear(_ year: String, asOf: Date) -> Bool {
        guard let start = AcademicYearKey.startYear(year) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let ongoing = calendar.component(.year, from: asOf) - (calendar.component(.month, from: asOf) < 8 ? 1 : 0)
        return start > ongoing
    }


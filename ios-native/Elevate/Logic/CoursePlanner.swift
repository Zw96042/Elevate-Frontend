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


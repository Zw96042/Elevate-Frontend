import Foundation

/// Immutable source rows used only for credit planning. No credit fields are
/// supplied by the current endpoint; inferred allocations remain estimates.
struct PlanningTranscriptCourse: Codable, Hashable, Identifiable {
    var academicYear: String
    var gradeYear: Int?
    var name: String
    var terms: String
    var sm1: String?
    var sm2: String?
    var ex1: String? = nil
    var ex2: String? = nil
    var isNonLinked: Bool = false
    var id: String { sourceSignature }
    var sourceSignature: String {
        [academicYear, gradeYear.map(String.init) ?? "", name, terms, sm1 ?? "", sm2 ?? "",
         ex1 ?? "", ex2 ?? "", String(isNonLinked)].map { "\($0.utf8.count):\($0)" }.joined()
    }
}

/// Corrections replace a source allocation (including zero to exclude it).
/// They never add a second earned record for the same source signature.
struct TranscriptCreditOverride: Codable, Equatable, Identifiable {
    var id: String
    var credits: Double
    var subject: CoursePlanSubject
}

enum TranscriptCreditStatus: String {
    case estimated = "Estimated from posted grades"
    case corrected = "Your correction"
    case needsReview = "Needs review"
    case notEarned = "No passing credit"
    case excluded = "Not counted"
    case inProgress = "Semester not completed"
}

struct TranscriptCreditRecord: Identifiable {
    var id: String
    var name: String
    var academicYear: String
    var gradeYear: Int?
    var semester: TermLabel
    var subject: CoursePlanSubject?
    var credits: Double
    var status: TranscriptCreditStatus
    var detail: String
}

struct TranscriptCreditReport {
    var records: [TranscriptCreditRecord]
    var usedLegacyFallback: Bool
    var orphanedOverrideIDs: [String]
    var unresolved: [TranscriptCreditRecord] { records.filter { $0.status == .needsReview } }
    var total: Double { records.reduce(0) { $0 + $1.credits } }
    func credits(for subject: CoursePlanSubject) -> Double {
        records.filter { $0.subject == subject }.reduce(0) { $0 + $1.credits }
    }
}

/// Prospective credit from verified live enrollment; never an awarded credit.
enum CurrentCourseCreditStatus: String {
    case expected = "Expected if passed"
    case needsReview = "Needs review"
    case excluded = "Not counted"
}

struct CurrentCourseCredit: Identifiable {
    var id: String
    var course: UnifiedCourseData
    var sourceCourseIDs: [String]
    var name: String
    var academicYear: String?
    var subject: CoursePlanSubject?
    var semesters: [TermLabel]
    var credits: Double
    var status: CurrentCourseCreditStatus
    var detail: String
}

enum TranscriptCreditCalculator {
    private struct Definition {
        var key: String
        var subject: CoursePlanSubject
        var credits: Double = 1
        var semesterOnly: Bool = false
        var middleSchoolEligible: Bool = false
        var repeatable: Bool = false
    }
    private struct Candidate {
        var course: PlanningTranscriptCourse
        var semester: TermLabel
        var grade: String?
        var definition: Definition?
        var normalizedName: String
        var groupingKey: String {
            "\(course.academicYear)|\(definition?.key ?? normalizedName)|\(semester.historicalKey)"
        }
    }


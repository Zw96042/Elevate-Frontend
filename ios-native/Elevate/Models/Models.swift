import Foundation

// MARK: - Session / Auth

struct SkywardSessionCodes: Codable, Equatable {
    var dwd: String
    var wfaacl: String
    var encses: String
    var userType: String
    var sessionid: String
}

struct SkywardCredentials: Codable, Equatable {
    var username: String
    var password: String
    var baseURL: String
}

enum SkywardError: LocalizedError {
    case sessionExpired
    case missingSession
    case invalidCredentials
    case invalidResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .sessionExpired: return "Session expired"
        case .missingSession: return "Missing session credentials"
        case .invalidCredentials: return "Invalid username or password"
        case .invalidResponse(let detail): return "Unexpected response from Skyward: \(detail)"
        case .network(let detail): return detail
        }
    }
}

// MARK: - Gradebook (per-class grade info dialog)

struct AssignmentMeta: Codable, Hashable {
    var type: String   // "missing" | "noCount" | "absent"
    var note: String
}

struct GradeInfoAssignment: Codable, Hashable {
    var date: String
    var name: String
    var grade: Int?
    var score: Double?
    var pointsEarned: Double?
    var pointsTotal: Double?
    var meta: [AssignmentMeta]
}

struct GradeCategory: Codable, Hashable {
    var category: String
    var weight: Double?
    var adjustedWeight: Double?
    var assignments: [GradeInfoAssignment]
}

struct GradeInfoResult: Codable, Hashable {
    var course: String
    var instructor: String
    var period: Int?
    var litName: String
    var litBegin: String?
    var litEnd: String?
    var gradebook: [GradeCategory]
    var score: Double?
    var grade: Int?
}

struct GradeInfoParams: Hashable {
    var stuId: String
    var corNumId: String
    var gbId: String
    var section: String
    var bucket: String
    var entityId: String = ""
    var track: String = ""
    var subjectId: String = ""
    var dialogLevel: String = ""
    var isEoc: String = "no"
}

// MARK: - Messages

struct SkywardMessage: Codable, Hashable, Identifiable {
    var className: String
    var content: String
    var date: String
    var from: String
    var messageRowId: String
    var subject: String

    var id: String {
        messageRowId.isEmpty
            ? "\(subject)|\(date)|\(from)|\(className)|\(content)"
            : messageRowId
    }
    var isAdministrator: Bool { subject == "Administrator Message" || className == "Administrator" }
}

// MARK: - Unified course data (history + current gradebook combined)

struct HistoricalGrades: Codable, Hashable {
    var pr1: String?, pr2: String?, pr3: String?, pr4: String?
    var pr5: String?, pr6: String?, pr7: String?, pr8: String?
    var rc1: String?, rc2: String?, rc3: String?, rc4: String?
    var ex1: String?, ex2: String?
    var sm1: String?, sm2: String?
    var finalGrade: String?

    subscript(key: String) -> String? {
        switch key.lowercased() {
        case "pr1": return pr1; case "pr2": return pr2; case "pr3": return pr3; case "pr4": return pr4
        case "pr5": return pr5; case "pr6": return pr6; case "pr7": return pr7; case "pr8": return pr8
        case "rc1": return rc1; case "rc2": return rc2; case "rc3": return rc3; case "rc4": return rc4
        case "ex1": return ex1; case "ex2": return ex2
        case "sm1": return sm1; case "sm2": return sm2
        case "finalgrade": return finalGrade
        default: return nil
        }
    }
}

struct BucketScore: Codable, Hashable {
    var bucket: String  // "Q1", "Q2", "S1", "EX1", ...
    var score: Double
}

enum AcademicScoreValue {
    /// Grade and point values are small in practice. This generous boundary
    /// rejects corrupted numeric payloads before they can overflow integer
    /// conversion or poison SwiftUI/widget calculations.
    static let magnitudeLimit = 1_000_000_000.0

    static func finiteDouble(_ text: String?) -> Double? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let value = Double(trimmed),
              value.isFinite,
              abs(value) <= magnitudeLimit else { return nil }
        return value
    }

    static func sanitizedGradeText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if Double(trimmed) != nil { return finiteDouble(trimmed) == nil ? nil : trimmed }
        let normalized = trimmed.lowercased()
        guard normalized != "nan",
              normalized != "infinity",
              normalized != "+infinity",
              normalized != "-infinity" else { return nil }
        return trimmed
    }
}

enum UnifiedCourseTransformer {
    static func transform(history: AcademicHistory) -> [UnifiedCourseData] {
        var courses: [UnifiedCourseData] = []
        for (academicYear, yearData) in history {
            for (storageKey, course) in yearData.courses {
                let courseName = course.courseName ?? storageKey
                let scores: [BucketScore] = [
                    ("Q1", course.rc1), ("Q2", course.rc2), ("S1", course.sm1), ("EX1", course.ex1),
                    ("Q3", course.rc3), ("Q4", course.rc4), ("S2", course.sm2), ("EX2", course.ex2),
                ].compactMap { bucket, text in
                    AcademicScoreValue.finiteDouble(text).map { BucketScore(bucket: bucket, score: $0) }
                }

                courses.append(UnifiedCourseData(
                    courseId: course.courseId,
                    corNumId: course.corNumId ?? "",
                    stuId: course.stuId ?? "",
                    section: course.section ?? "",
                    gbId: course.gbId ?? "",
                    courseName: courseName,
                    instructor: course.instructor,
                    period: course.period,
                    time: course.time,
                    semester: inferSemester(course.terms),
                    termLength: course.terms,
                    gradeYear: yearData.grade,
                    currentScores: scores,
                    historicalGrades: historicalGrades(for: course),
                    academicYear: academicYear,
                    historyRowKey: storageKey,
                    academicYearIsVerified: yearData.academicYearIsVerified
                        ?? (AcademicYearKey.startYear(academicYear) != nil),
                    isTranscriptRecord: course.isTranscriptRecord,
                    postedHistoricalGrades: course.postedHistoricalGrades,
                    isCurrentEnrollment: course.isCurrentEnrollment,
                    currentEnrollmentSemester: course.currentEnrollmentSemester,
                    currentEnrollmentGradeYear: course.currentEnrollmentGradeYear,
                    currentEnrollmentObservedAt: course.currentEnrollmentObservedAt,
                    catalogCourseCode: course.catalogCourseCode
                ))
            }
        }
        courses = courses.sorted {
            if $0.gradeYear != $1.gradeYear { return ($0.gradeYear ?? 0) < ($1.gradeYear ?? 0) }
            if $0.period != $1.period { return ($0.period ?? 99) < ($1.period ?? 99) }
            return $0.courseName < $1.courseName
        }
        let planning = history.keys.sorted().flatMap { history[$0]?.planningTranscriptCourses ?? [] }
        if history.values.contains(where: { $0.planningTranscriptCourses != nil }) {
            if !courses.isEmpty {
                // The whole immutable projection is attached once to a stable
                // existing record. It remains in the account's course cache.
                let index = courses.indices.min { courses[$0].id < courses[$1].id }!
                courses[index].planningTranscriptCourses = planning
            } else {
                // Internal transport only. AppStore strips this carrier before
                // publishing official courses; it has no grade or enrollment.
                courses.append(UnifiedCourseData(
                    courseId: nil, corNumId: "", stuId: "", section: "", gbId: "",
                    courseName: "", semester: .unknown, termLength: "", gradeYear: nil,
                    currentScores: [], historicalGrades: HistoricalGrades(), isTranscriptRecord: false,
                    planningTranscriptCourses: planning, isPlanningOnly: true
                ))
            }
        }
        return courses
    }

    private static func clean(_ value: String?) -> String? {
        AcademicScoreValue.sanitizedGradeText(value)
    }

    static func historicalGrades(for course: HistoryCourse) -> HistoricalGrades {
        HistoricalGrades(
            pr1: clean(course.pr1), pr2: clean(course.pr2),
            pr3: clean(course.pr3), pr4: clean(course.pr4),
            pr5: clean(course.pr5), pr6: clean(course.pr6),
            pr7: clean(course.pr7), pr8: clean(course.pr8),
            rc1: clean(course.rc1), rc2: clean(course.rc2),
            rc3: clean(course.rc3), rc4: clean(course.rc4),
            ex1: clean(course.ex1), ex2: clean(course.ex2),
            sm1: clean(course.sm1), sm2: clean(course.sm2),
            finalGrade: clean(course.finalGrade)
        )
    }

    static func inferSemester(_ terms: String) -> Semester {
        switch terms.replacingOccurrences(of: " ", with: "") {
        case "1-4": return .both
        case "1-2": return .fall
        case "3-4": return .spring
        default: return .unknown
        }
    }
}

enum Semester: String, Codable {
    case fall, spring, both, unknown
}

struct UnifiedCourseData: Codable, Hashable, Identifiable {
    var courseId: Int?
    var corNumId: String
    var stuId: String
    var section: String
    var gbId: String
    var courseName: String
    var instructor: String?
    var period: Int?
    var time: String?
    var semester: Semester
    var termLength: String
    var gradeYear: Int?
    var currentScores: [BucketScore]
    var historicalGrades: HistoricalGrades
    /// Source year and row identity are optional for caches saved before history browsing.
    var academicYear: String? = nil
    var historyRowKey: String? = nil
    /// False for a year manufactured by the existing live-gradebook merge.
    var academicYearIsVerified: Bool? = nil
    /// Requires independent current-school-year evidence; matching the latest
    /// transcript year by grade level or course name does not establish it.
    var currentAcademicYearIsVerified: Bool? = nil
    var isTranscriptRecord: Bool? = nil
    /// Source grades before the live merge, separate from the existing GPA data.
    var postedHistoricalGrades: HistoricalGrades? = nil
    var planningTranscriptCourses: [PlanningTranscriptCourse]? = nil
    /// Internal cache/transport carrier, never an official course/enrollment.
    var isPlanningOnly: Bool? = nil
    /// Independent membership in a successfully parsed live gradebook snapshot.
    /// These fields do not date, reclassify or modify the historical source row.
    var isCurrentEnrollment: Bool? = nil
    var currentEnrollmentSemester: Semester? = nil
    var currentEnrollmentGradeYear: Int? = nil
    var currentEnrollmentObservedAt: Date? = nil

    /// Verified same-course catalog metadata; independent of the source title and identity.
    var catalogCourseCode: String? = nil

    var courseLevel: CourseLevel {
        CourseLevelDetector.level(for: courseName, catalogCourseCode: catalogCourseCode)
    }

    var postedGrades: HistoricalGrades { postedHistoricalGrades ?? historicalGrades }

    var id: String {
        // Keep live gradebook IDs unchanged for assignments, local edits and
        // viewed-grade tracking. Only transcript-only rows gain source identity.
        if courseId == nil, corNumId.isEmpty,
           let academicYear, let historyRowKey {
            return "history:\(academicYear.count):\(academicYear)\(historyRowKey.count):\(historyRowKey)"
        }
        return [
            stuId,
            corNumId,
            section,
            gbId,
            courseId.map(String.init) ?? "",
            gradeYear.map(String.init) ?? "",
            courseName,
        ].joined(separator: "|")
    }

    var hasGradebookParams: Bool {
        isPlanningOnly != true && !courseName.isEmpty && !stuId.isEmpty && !corNumId.isEmpty && !section.isEmpty && !gbId.isEmpty
    }

    /// A semester class has its own gradebook, assignments and local edits.
    /// Switching terms must never query the other semester on this identity.
    var availableTerms: [TermLabel] {
        if isPlanningOnly == true { return [] }
        switch semester {
        case .fall: return [.q1, .q2, .sm1]
        case .spring: return [.q3, .q4, .sm2]
        case .both, .unknown: return TermLabel.allCases
        }
    }
}

// MARK: - Terms

enum TermLabel: String, Codable, CaseIterable, Identifiable {
    case q1 = "Q1 Grades"
    case q2 = "Q2 Grades"
    case sm1 = "SM1 Grade"
    case q3 = "Q3 Grades"
    case q4 = "Q4 Grades"
    case sm2 = "SM2 Grades"

    var id: String { rawValue }

    /// Skyward bucket name used by the grade-info dialog.
    var bucket: String {
        switch self {
        case .q1: return "TERM 3"
        case .q2: return "TERM 6"
        case .sm1: return "SEM 1"
        case .q3: return "TERM 9"
        case .q4: return "TERM 12"
        case .sm2: return "SEM 2"
        }
    }

    /// Key into historical grades / current scores.
    var historicalKey: String {
        switch self {
        case .q1: return "rc1"
        case .q2: return "rc2"
        case .sm1: return "sm1"
        case .q3: return "rc3"
        case .q4: return "rc4"
        case .sm2: return "sm2"
        }
    }

    var shortName: String {
        switch self {
        case .q1: return "Q1"; case .q2: return "Q2"; case .sm1: return "SM1"
        case .q3: return "Q3"; case .q4: return "Q4"; case .sm2: return "SM2"
        }
    }

    var isFall: Bool { self == .q1 || self == .q2 || self == .sm1 }
    var isSemester: Bool { self == .sm1 || self == .sm2 }
}

// MARK: - GPA

struct GPAData: Codable, Hashable {
    var unweighted: Double
    var weighted: Double
}

enum GradeLevel: String, Codable, CaseIterable, Identifiable {
    case current = "Current"
    case freshman = "Freshman"
    case sophomore = "Sophomore"
    case junior = "Junior"
    case senior = "Senior"
    case allTime = "All Time"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .current: return "Now"
        case .freshman: return "9th"
        case .sophomore: return "10th"
        case .junior: return "11th"
        case .senior: return "12th"
        case .allTime: return "All"
        }
    }

    var gradeYear: Int? {
        switch self {
        case .freshman: return 9
        case .sophomore: return 10
        case .junior: return 11
        case .senior: return 12
        case .current, .allTime: return nil
        }
    }

    static func from(gradeYear: Int) -> GradeLevel {
        switch gradeYear {
        case 9: return .freshman
        case 10: return .sophomore
        case 11: return .junior
        case 12: return .senior
        default: return .freshman
        }
    }
}

// MARK: - What-if (artificial) assignments

struct WhatIfAssignment: Codable, Hashable, Identifiable {
    var id: String
    var className: String
    var name: String
    var term: String       // "Q1", "Q2", "SM1", ...
    var category: String
    var grade: Double?
    var outOf: Double
    var dueDate: String
    var noCount: Bool?
    var status: WhatIfAssignmentStatus?

    init(id: String = UUID().uuidString, className: String, name: String, term: String,
         category: String, grade: Double?, outOf: Double, dueDate: String,
         status: WhatIfAssignmentStatus = .counted) {
        self.id = id
        self.className = className
        self.name = name
        self.term = term
        self.category = category
        self.grade = grade
        self.outOf = outOf
        self.dueDate = dueDate
        self.noCount = status == .noCount
        self.status = status
    }

    var resolvedStatus: WhatIfAssignmentStatus {
        get { status ?? (noCount == true ? .noCount : .counted) }
        set {
            status = newValue
            noCount = newValue == .noCount
        }
    }
}

enum WhatIfAssignmentStatus: String, Codable, CaseIterable, Identifiable {
    case counted = "Counted"
    case noCount = "No Count"
    case missing = "Missing"
    case absent = "Absent"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .counted: return "circle"
        case .noCount: return "minus.circle"
        case .missing: return "exclamationmark.circle"
        case .absent: return "person.crop.circle.badge.xmark"
        }
    }
}

// MARK: - Manual GPA entry

struct ManualClass: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var className: String
    var sm1: Double?
    var sm2: Double?
}

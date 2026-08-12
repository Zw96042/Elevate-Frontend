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

    var id: String {
        [
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
        !courseName.isEmpty && !stuId.isEmpty && !corNumId.isEmpty && !section.isEmpty && !gbId.isEmpty
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

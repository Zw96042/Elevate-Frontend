import Foundation

/// Explicit estimates, separate from the district's 100-point GPACalculator.
enum GPAConversionPolicy: String, CaseIterable, Identifiable, Hashable {
    case unweighted4Point
    case weighted5Point

    var id: String { rawValue }
    var title: String {
        switch self {
        case .unweighted4Point: return "4.0 unweighted"
        case .weighted5Point: return "5.0 weighted"
        }
    }
    var maximum: Double { self == .unweighted4Point ? 4 : 5 }
    var explanation: String {
        let cutoffs = "Each posted semester grade converts to points: 90 or above = 4, 80 to below 90 = 3, 70 to below 80 = 2, 60 to below 70 = 1, below 60 = 0. No plus/minus grades or rounding before conversion."
        switch self {
        case .unweighted4Point: return cutoffs
        case .weighted5Point:
            return cutoffs + " Passing grades (60 or above) receive +1 for AP-level courses or +0.5 for Honors; failing grades receive no bonus. Elevate's course-level policy includes district advanced-course exceptions and verified catalog codes. These labels do not verify a college's honors eligibility."
        }
    }

    func points(for percentage: Double, level: CourseLevel) -> Double? {
        guard percentage.isFinite, percentage >= 0,
              percentage <= AcademicScoreValue.magnitudeLimit else { return nil }
        let base: Double
        switch percentage {
        case 90...: base = 4
        case 80..<90: base = 3
        case 70..<80: base = 2
        case 60..<70: base = 1
        default: base = 0
        }
        guard self == .weighted5Point, base > 0 else { return base }
        switch level {
        case .ap: return base + 1
        case .honors: return base + 0.5
        case .regular: return base
        }
    }
}

enum GPAConversionSource: String, Hashable {
    case transcript = "Posted transcript"
    case skyward = "Skyward semester grade"
    case manual = "Manual entry"
}

struct GPAConversionRecord: Hashable, Identifiable {
    var id: String
    var courseName: String
    var gradeYear: Int
    var semester: TermLabel
    var percentage: Double
    var points: Double
    var source: GPAConversionSource
    var courseLevel: CourseLevel = .regular
}

enum GPAConversionSkipReason: String, Hashable, CaseIterable {
    case missingGrade = "No posted semester grade"
    case nonnumericGrade = "Pass code or nonnumeric grade"
    case invalidGrade = "Invalid numeric grade"
    case unknownYear = "Grade year unavailable"
    case outsideHighSchool = "Outside grades 9–12"
    case outsideSelectedYears = "Outside selected years"
    case duplicateRecord = "Duplicate semester record"
    case conflictingDuplicate = "Conflicting duplicate semester grades"
    case inProgress = "Semester not completed"
}

struct GPAConversionSkippedRecord: Hashable, Identifiable {
    var id: String
    var courseName: String
    var gradeYear: Int?
    var semester: TermLabel
    var reason: GPAConversionSkipReason
}

struct GPAConversionReport {
    var policy: GPAConversionPolicy
    var includedRecords: [GPAConversionRecord]
    var skippedRecords: [GPAConversionSkippedRecord]
    var completedOnly: Bool = false
    var includedCount: Int { includedRecords.count }
    var skippedCount: Int { skippedRecords.count }
    /// Keep calculation precision; the caller formats only for display.
    var value: Double? {
        guard !includedRecords.isEmpty else { return nil }
        return includedRecords.reduce(0) { $0 + $1.points } / Double(includedRecords.count)
    }
    var scopeExplanation: String {
        (completedOnly ? "Completed semesters only. " : "") + "Known grades 9–12 only, using posted semester grades. Every included semester counts equally because course credits are unavailable. Missing, pass-code, and invalid grades are skipped. Repeated courses retain separate source identities; no college repeat replacement or subject-eligibility rules are applied. Manual entries fill only years with no Skyward courses. This is an estimate, not an official transcript or admissions GPA."
    }
}


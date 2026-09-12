import Foundation

/// Exact source school-year keys, rather than grade levels or the device date.
enum AcademicYearKey {
    static func startYear(_ key: String) -> Int? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ $0.count == 4 && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let start = Int(parts[0]), let end = Int(parts[1]),
              start >= 1000, end == start + 1 else { return nil }
        return start
    }
}

/// The existing high-school course subset, restricted to previous school years.
/// This does not broaden transcript inclusion or change any grade/GPA policy.
struct CourseHistoryReport {
    let currentAcademicYear: String?
    /// Exact archive years remain available when the current year is unknown.
    /// They must then be labelled school-year history, rather than previous years.
    let knownAcademicYears: [String]
    let years: [String]
    let hasLegacyMetadata: Bool
    private let coursesByYear: [String: [UnifiedCourseData]]
    private let archiveByYear: [String: [UnifiedCourseData]]

    var hasCurrentYearEvidence: Bool { currentAcademicYear != nil }

    init(courses: [UnifiedCourseData]) {
        let courses = courses.filter { $0.isPlanningOnly != true }
        hasLegacyMetadata = courses.contains { $0.academicYear == nil || $0.historyRowKey == nil }
        let datedCourses = courses.filter {
            guard let year = $0.academicYear else { return false }
            return AcademicYearKey.startYear(year) != nil && $0.academicYearIsVerified != false
        }
        // A grade level can repeat. A fabricated next-year merge bucket and an
        // older cache with only gradeYear cannot establish the current year.
        let archiveCourses = datedCourses.filter { $0.isTranscriptRecord != false }
        archiveByYear = Dictionary(grouping: archiveCourses, by: { $0.academicYear! })
        knownAcademicYears = archiveByYear.keys.sorted(by: >)
        let liveCourses = courses.filter(\.hasGradebookParams)
        let datedLiveCourses = datedCourses.filter(\.hasGradebookParams)
        let liveYears = Set(datedLiveCourses.compactMap(\.academicYear))
        let verifiedCurrentYears = Set(datedLiveCourses.filter { $0.currentAcademicYearIsVerified == true }.compactMap(\.academicYear))
        let current = verifiedCurrentYears.count == 1 && liveYears == verifiedCurrentYears
            && liveCourses.count == datedLiveCourses.count ? verifiedCurrentYears.first : nil
        currentAcademicYear = current
        guard let current, let currentStart = AcademicYearKey.startYear(current) else {
            years = []
            coursesByYear = [:]
            return
        }

        let previousCourses = archiveCourses.filter {
            guard let year = $0.academicYear, let start = AcademicYearKey.startYear(year) else { return false }
            return start < currentStart
        }
        coursesByYear = Dictionary(grouping: previousCourses, by: { $0.academicYear! })
        years = coursesByYear.keys.sorted(by: >)
    }

    func courses(for year: String) -> [UnifiedCourseData] {
        sorted(coursesByYear[year] ?? [])
    }

    func courses(inAcademicYear year: String) -> [UnifiedCourseData] {
        sorted(archiveByYear[year] ?? [])
    }

    private func sorted(_ courses: [UnifiedCourseData]) -> [UnifiedCourseData] {
        courses.sorted {
            if $0.courseName != $1.courseName { return $0.courseName < $1.courseName }
            return $0.id < $1.id
        }
    }
}

/// A read-only presentation projection. Store/cache courses and GPA inputs
/// retain every original row; only this projection hides or combines rows.
struct CourseHistoryDisplayEntry: Hashable, Identifiable {
    var id: String
    var course: UnifiedCourseData
    var sourceRowIDs: [String]
}

enum CourseHistoryDisplay {
    private static var fallSlots: [WritableKeyPath<HistoricalGrades, String?>] { [
        \.pr1, \.pr2, \.pr3, \.pr4, \.rc1, \.rc2, \.ex1, \.sm1,
    ] }
    private static var springSlots: [WritableKeyPath<HistoricalGrades, String?>] { [
        \.pr5, \.pr6, \.pr7, \.pr8, \.rc3, \.rc4, \.ex2, \.sm2,
    ] }
    private static var sourceSlots: [WritableKeyPath<HistoricalGrades, String?>] { fallSlots + springSlots }


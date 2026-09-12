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

    static func postedValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// This list is a semester archive. Quarter/progress-only source records
    /// remain in the report and GPA inputs but have no semester grade to show.
    static func hasPostedSemesterGrades(_ grades: HistoricalGrades) -> Bool {
        postedValue(grades.sm1) != nil || postedValue(grades.sm2) != nil
    }

    static func entries(courses: [UnifiedCourseData]) -> [CourseHistoryDisplayEntry] {
        var occurrences: [String: Int] = [:]
        let visible = courses.filter { $0.isTranscriptRecord != false && hasPostedSemesterGrades($0.postedGrades) }.map { course in
            let source = sourceIdentity(course)
            let occurrence = occurrences[source, default: 0]
            occurrences[source] = occurrence + 1
            let id = "source:\(source):\(occurrence)"
            return CourseHistoryDisplayEntry(id: id, course: course, sourceRowIDs: [id])
        }
        struct Group: Hashable {
            var name: String
            var year: String?
            var gradeYear: Int?
        }
        let groups = Dictionary(grouping: visible) {
            Group(name: $0.course.courseName, year: $0.course.academicYear, gradeYear: $0.course.gradeYear)
        }
        return groups.values.flatMap { rows -> [CourseHistoryDisplayEntry] in
            guard rows.count == 2, let combined = combine(rows[0], rows[1]) else { return rows }
            return [combined]
        }.sorted {
            if $0.course.courseName != $1.course.courseName { return $0.course.courseName < $1.course.courseName }
            return $0.id < $1.id
        }
    }

    private static func combine(_ first: CourseHistoryDisplayEntry,
                                _ second: CourseHistoryDisplayEntry) -> CourseHistoryDisplayEntry? {
        let a = first.course, b = second.course
        guard let year = a.academicYear, AcademicYearKey.startYear(year) != nil,
              a.academicYearIsVerified != false, b.academicYearIsVerified != false,
              a.isTranscriptRecord != false, b.isTranscriptRecord != false,
              a.historyRowKey != nil, b.historyRowKey != nil,
              a.historyRowKey != b.historyRowKey else { return nil }
        if !a.corNumId.isEmpty, !b.corNumId.isEmpty, a.corNumId != b.corNumId { return nil }
        if !a.stuId.isEmpty, !b.stuId.isEmpty, a.stuId != b.stuId { return nil }
        if a.corNumId.isEmpty, b.corNumId.isEmpty,
           let aID = a.courseId, let bID = b.courseId, aID != bID { return nil }

        func isOnlyFall(_ grades: HistoricalGrades) -> Bool {
            postedValue(grades.sm1) != nil && springSlots.allSatisfy { postedValue(grades[keyPath: $0]) == nil }
        }
        func isOnlySpring(_ grades: HistoricalGrades) -> Bool {
            postedValue(grades.sm2) != nil && fallSlots.allSatisfy { postedValue(grades[keyPath: $0]) == nil }
        }
        let fall: UnifiedCourseData, spring: UnifiedCourseData
        if isOnlyFall(a.postedGrades), isOnlySpring(b.postedGrades) {
            fall = a; spring = b
        } else if isOnlyFall(b.postedGrades), isOnlySpring(a.postedGrades) {
            fall = b; spring = a
        } else {
            return nil
        }
        var grades = fall.postedGrades
        for slot in sourceSlots {
            let existing = postedValue(grades[keyPath: slot])
            let incoming = postedValue(spring.postedGrades[keyPath: slot])
            if let existing, let incoming, existing != incoming { return nil }
            if existing == nil, incoming != nil { grades[keyPath: slot] = spring.postedGrades[keyPath: slot] }
        }
        // finalGrade is derived by the parser from the last posted semester or
        // quarter, not a separate transcript column. Retain the spring source.
        grades.finalGrade = postedValue(spring.postedGrades.finalGrade) != nil
            ? spring.postedGrades.finalGrade : fall.postedGrades.finalGrade
        let sourceIDs = (first.sourceRowIDs + second.sourceRowIDs).sorted()
        var course = first.id < second.id ? a : b
        course.postedHistoricalGrades = grades
        course.semester = .both
        return CourseHistoryDisplayEntry(id: "combined:" + lengthPrefixed(sourceIDs),
                                         course: course, sourceRowIDs: sourceIDs)
    }

    private static func sourceIdentity(_ course: UnifiedCourseData) -> String {
        if let year = course.academicYear, let row = course.historyRowKey {
            return lengthPrefixed([year, row])
        }
        // Older caches may lack row keys; source values distinguish their rows
        // without depending on randomized hash values or current list position.
        let values = (sourceSlots + [\.finalGrade]).map { course.postedGrades[keyPath: $0] ?? "" }
        return lengthPrefixed([course.id] + values)
    }

    private static func lengthPrefixed(_ values: [String]) -> String {
        values.map { "\($0.utf8.count):\($0)" }.joined()
    }
}

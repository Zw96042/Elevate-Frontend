import SwiftUI

/// Saved manual classes for every high-school year; the calculator uses them
/// only for years with no Skyward courses.
enum GPAConversionInputs {
    static var manualClassesByYear: [Int: [ManualClass]] {
        Dictionary(uniqueKeysWithValues: [GradeLevel.freshman, .sophomore, .junior, .senior].compactMap { level in
            level.gradeYear.map { ($0, WhatIfStore.manualClasses(gradeLevel: level)) }
        })
    }

    /// Completed semesters only, independent of the GPA screen's school year.
    static func completedReport(courses: [UnifiedCourseData]?, gradeYears: Set<Int>? = nil,
                                policy: GPAConversionPolicy) -> GPAConversionReport {
        GPAConversionCalculator.calculate(
            courses: courses ?? [],
            manualClassesByYear: manualClassesByYear,
            gradeYears: gradeYears,
            policy: policy,
            completedOnly: true
        )
    }

    /// Both generic scales over the same completed semesters.
    static func completedScales(courses: [UnifiedCourseData]?, gradeYears: Set<Int>? = nil) -> GPAScaleReports {
        GPAScaleReports(
            unweighted: completedReport(courses: courses, gradeYears: gradeYears, policy: .unweighted4Point),
            weighted: completedReport(courses: courses, gradeYears: gradeYears, policy: .weighted5Point)
        )
    }

    /// Out-of-scope and unfinished semesters are intentionally excluded, not data gaps.
    static func notConverted(_ skipped: [GPAConversionSkippedRecord]) -> [GPAConversionSkippedRecord] {
        skipped.filter { $0.reason != .outsideSelectedYears && $0.reason != .inProgress }
    }

    /// The years actually included, not the full eligible high-school range.
    static func yearScope(_ records: [GPAConversionRecord]) -> String {
        let years = Array(Set(records.map(\.gradeYear))).sorted()
        guard let first = years.first, let last = years.last else { return "Completed grades" }
        if years.count == 1 { return "Grade \(first)" }
        if years.count == last - first + 1 { return "Grades \(first)–\(last)" }
        return "Grades " + ListFormatter.localizedString(byJoining: years.map(String.init))
    }

    /// "1 semester grade", "12 semester grades".
    static func semesterGrades(_ count: Int) -> String {
        "\(count) semester \(count == 1 ? "grade" : "grades")"
    }

    /// "Grade 11, Semester 1".
    static func recordName(year: Int?, semester: TermLabel) -> String {
        let term = semester.displayName
        guard let year else { return term }
        return "Grade \(year), \(term)"
    }

    static func courseName(_ raw: String) -> String {
        ClassNameFormatter.format(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_"))
    }
}

/// Elevate's generic unweighted 4.0 and weighted 5.0 reports for one scope.
/// Both come from `GPAConversionCalculator`; nothing is recalculated here.
struct GPAScaleReports {
    var unweighted: GPAConversionReport
    var weighted: GPAConversionReport

    /// Both values, or nil when no completed semester is included.
    var values: (unweighted: Double, weighted: Double)? {
        guard let unweighted = unweighted.value, let weighted = weighted.value else { return nil }
        return (unweighted, weighted)
    }

    /// The weighted scale's bonus for each included record, by record ID,
    /// where the weighted report gave more points than the unweighted one.
    var bonuses: [String: Double] {
        let base = Dictionary(unweighted.includedRecords.map { ($0.id, $0.points) }, uniquingKeysWith: { first, _ in first })
        var result: [String: Double] = [:]
        for record in weighted.includedRecords {
            if let points = base[record.id], record.points > points { result[record.id] = record.points - points }
        }
        return result
    }

    /// Included semesters that received an AP/Honors bonus.
    var advancedCount: Int { bonuses.count }

    /// Skipped records are the same on both scales; the unweighted list is used.
    var notConverted: [GPAConversionSkippedRecord] {
        GPAConversionInputs.notConverted(unweighted.skippedRecords)
    }
}


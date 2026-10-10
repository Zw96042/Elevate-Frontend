import Foundation

/// How the GPA screen and the Courses summary assemble a school year's term
/// GPAs. Both go through this one path, so the summary can never disagree
/// with the screen it opens. Every value comes from `GPACalculator`; this
/// only chooses the inputs and orders and names the results.
enum GPAReport {
    /// Display order from earliest to latest. FIN exists only when both semesters do.
    static let chronologicalTerms = [
        "PR1", "PR2", "RC1", "PR3", "PR4", "RC2", "SM1",
        "PR5", "PR6", "RC3", "PR7", "PR8", "RC4", "SM2", "FIN",
    ]

    /// Manual classes stand in only for a single school year Skyward has no
    /// classes for.
    static func supportsManualEntry(level: GradeLevel, courses: [UnifiedCourseData]) -> Bool {
        level.gradeYear != nil && courses.isEmpty
    }

    /// Term GPAs for one school year. `courses` are that year's classes and
    /// `manualClasses` the classes saved by hand for it.
    static func termGPAs(
        level: GradeLevel,
        courses: [UnifiedCourseData],
        manualClasses: [ManualClass]
    ) -> [String: GPAData] {
        if level == .allTime {
            return GPACalculator.termGPAs(
                courses: courses,
                manualClasses: allTimeManualClasses(courses: courses)
            )
        }
        if !courses.isEmpty {
            return GPACalculator.termGPAs(courses: courses)
        }
        if supportsManualEntry(level: level, courses: courses) {
            return GPACalculator.termGPAs(manualClasses: manualClasses)
        }
        return [:]
    }

    /// Saved manual classes for every year that has no Skyward history.
    private static func allTimeManualClasses(courses: [UnifiedCourseData]) -> [ManualClass] {
        let realYears = Set(courses.compactMap(\.gradeYear))
        return [GradeLevel.freshman, .sophomore, .junior, .senior]
            .filter { level in
                guard let year = level.gradeYear else { return false }
                return !realYears.contains(year)
            }
            .flatMap { WhatIfStore.manualClasses(gradeLevel: $0) }
    }

    /// The year's final: the average of both semesters, only when both exist.
    static func finalGPA(_ data: [String: GPAData]) -> GPAData? {
        guard let sm1 = data["SM1"], let sm2 = data["SM2"] else { return nil }
        return GPAData(
            unweighted: (sm1.unweighted + sm2.unweighted) / 2,
            weighted: (sm1.weighted + sm2.weighted) / 2
        )
    }

    static func includingFinal(_ data: [String: GPAData]) -> [String: GPAData] {
        var result = data
        if let fin = finalGPA(data) { result["FIN"] = fin }
        return result
    }

    /// The most recent term with a GPA, including the final.
    static func latest(in data: [String: GPAData]) -> (label: String, data: GPAData)? {
        let all = includingFinal(data)
        guard let label = chronologicalTerms.last(where: { all[$0] != nil }),
              let value = all[label] else { return nil }
        return (label, value)
    }

    /// The GPA table key for a grading term: Q1 is RC1, S1 is SM1. The
    /// widgets use the same mapping.
    static func key(for term: TermLabel) -> String {
        term.historicalKey.uppercased()
    }

    /// "Quarter 1", "Progress report 3", "Final".
    static func termName(_ code: String) -> String {
        switch code {
        case "RC1": return "Quarter 1"
        case "RC2": return "Quarter 2"
        case "RC3": return "Quarter 3"
        case "RC4": return "Quarter 4"
        case "SM1": return "Semester 1"
        case "SM2": return "Semester 2"
        case "FIN": return "Final"
        default:
            if code.hasPrefix("PR"), let number = code.dropFirst(2).first {
                return "Progress report \(number)"
            }
            return code
        }
    }

    /// "Q1", "P3": short names for the ends of the chart.
    static func shortName(_ code: String) -> String {
        switch code {
        case "RC1": return "Q1"
        case "RC2": return "Q2"
        case "RC3": return "Q3"
        case "RC4": return "Q4"
        default: return code.replacingOccurrences(of: "PR", with: "P")
        }
    }
}

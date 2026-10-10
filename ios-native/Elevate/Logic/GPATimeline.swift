import Foundation

/// A trend retains each school year's identity instead of pooling matching
/// term codes across years. Overall GPA calculations are separate.
enum GPATimeline {
    static let terms = [
        "PR1", "PR2", "RC1", "PR3", "PR4", "RC2", "SM1",
        "PR5", "PR6", "RC3", "PR7", "PR8", "RC4", "SM2",
    ]

    struct Entry: Hashable, Identifiable {
        var level: GradeLevel
        var term: String
        var data: GPAData
        var id: String { "\(level.rawValue).\(term)" }
    }

    static func allYears(
        courses: [UnifiedCourseData],
        manualClassesByYear: [Int: [ManualClass]]
    ) -> [Entry] {
        let levels: [GradeLevel] = [.freshman, .sophomore, .junior, .senior, .current]
        return levels.flatMap { level -> [Entry] in
            let yearCourses = courses.filter { $0.isPlanningOnly != true && $0.gradeYear == level.gradeYear }
            // Manual semesters fill a year with no Skyward courses, never
            // supplement or replace a year with real history.
            let manual = yearCourses.isEmpty
                ? level.gradeYear.flatMap { manualClassesByYear[$0] } ?? []
                : []
            let data = GPACalculator.termGPAs(courses: yearCourses, manualClasses: manual)
            return terms.compactMap { term in
                guard let value = data[term], value.weighted.isFinite,
                      value.unweighted.isFinite else { return nil }
                return Entry(level: level, term: term, data: value)
            }
        }
    }
}

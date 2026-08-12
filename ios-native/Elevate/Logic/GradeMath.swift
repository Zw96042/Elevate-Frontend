import Foundation

// MARK: - Class name formatting (port of formatClassName.tsx)

enum ClassNameFormatter {
    private static let acronyms: Set<String> = [
        "AP", "IB", "GT", "ELA", "BC", "AB", "CSA", "CSP", "APUSH", "US", "UK", "EU",
        "PE", "IT", "CS", "AI", "ML", "CAD", "CTE", "STEM",
    ]

    static func format(_ raw: String) -> String {
        var name = raw
        if name.hasSuffix("FF") { return "Invention & Innovation FF" }
        if name.hasSuffix("HONORS") {
            name = name.replacingOccurrences(of: "HONORS", with: "H").trimmingCharacters(in: .whitespaces)
        }
        return name.uppercased()
            .split(separator: "_")
            .map { word -> String in
                let w = String(word)
                if acronyms.contains(w) { return w }
                if w.range(of: "II", options: .caseInsensitive) != nil, w.allSatisfy({ $0 == "I" || $0 == "i" }) {
                    return w.uppercased()
                }
                guard let first = w.first else { return w }
                return String(first) + w.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

// MARK: - Course level detection (port of gpaCalculator.tsx)

enum CourseLevel: String {
    case ap = "AP"
    case honors = "Honors"
    case regular = "Regular"

    var gpaBonus: Double {
        switch self {
        case .ap: return 10
        case .honors: return 5
        case .regular: return 0
        }
    }
}

enum CourseLevelDetector {
    private static let apExceptions: Set<String> = [
        "multivariable calculus", "linear algebra", "stats 2: beyond ap statistics",
        "computer science 2", "computer science ii", "computer science 3", "computer science iii",
        "computer science ind study 1", "organic chemistry",
        "art historical methods", "art historical methods 2",
        "chinese 5 advanced", "chinese 6 advanced", "french 5 advanced", "french 6 advanced",
        "german 5 advanced", "german 6 advanced", "latin 5 advanced", "latin 6 advanced",
        "heritage, and immersion students", "spanish 6",
    ]

    private static let honorsExceptions: Set<String> = [
        "editorial leadership 1, 2, and 3", "anatomy & physiology", "mentorship",
        "health science clinical", "practicum in health science - pharmacy or phlebotomy",
        "robotics 2", "robotics ii", "robotics 3", "robotics iii", "swift coding",
        "business incubator", "business acceleratoredu", "anatomy and physiology", "engineering",
    ]

    /// Normalizes trailing Roman numerals to digits so "Robotics II" matches "robotics 2".
    private static func normalizeNumbers(_ text: String) -> String {
        var normalized = text
        let romanToNumber = [" i": " 1", " ii": " 2", " iii": " 3", " iv": " 4", " v": " 5", " vi": " 6"]
        // Longest first so " iii" doesn't get eaten by " i".
        for (roman, number) in romanToNumber.sorted(by: { $0.key.count > $1.key.count }) {
            if normalized.hasSuffix(roman) {
                normalized = String(normalized.dropLast(roman.count)) + number
            }
        }
        return normalized
    }

    static func level(for className: String) -> CourseLevel {
        let normalized = className.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return .regular }

        let hasAPKeyword = normalized.range(of: #"\bap\b"#, options: .regularExpression) != nil
        if hasAPKeyword || matchesException(normalized, in: apExceptions) { return .ap }

        let hasHonorsKeyword = normalized.range(of: #"\bhonors?\b"#, options: .regularExpression) != nil
        if hasHonorsKeyword || matchesException(normalized, in: honorsExceptions) { return .honors }

        return .regular
    }

    private static func matchesException(_ normalized: String, in exceptions: Set<String>) -> Bool {
        let normalizedCourse = normalizeNumbers(normalized)
        for ex in exceptions {
            let normalizedEx = normalizeNumbers(ex)
            if normalized == ex || normalizedCourse == normalizedEx { return true }
            if ex.count > 10, normalized.contains(ex) || normalizedCourse.contains(normalizedEx) { return true }
            if ex.count <= 10, normalized.count > 5 {
                let courseWords = normalizedCourse.split(separator: " ").map(String.init)
                let exWords = normalizedEx.split(separator: " ").map(String.init)
                if courseWords.count >= 2, exWords.count >= 2 {
                    if courseWords.dropLast().joined(separator: " ") == exWords.dropLast().joined(separator: " "),
                       courseWords.last == exWords.last {
                        return true
                    }
                } else if ex.contains(normalized) || normalizedEx.contains(normalizedCourse) {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - Grade summary / what-if calculation (port of calculateGrades.tsx)

struct GradeSummary {
    var courseTotal: Double?          // nil ⇔ "*" in the RN app
    var categories: [String: CategoryResult]
    var sm1: Double?
    var sm2: Double?

    struct CategoryResult {
        var average: Double
        var weight: Double
        var rawPoints: Double
        var rawTotal: Double
    }
}

/// Assignment shape used by the calculator and the class-detail UI.
struct CalcAssignment: Identifiable, Hashable {
    var id: String
    var className: String
    var name: String
    var term: String
    var category: String
    var grade: Double?     // earned points; nil ⇔ ungraded ("*")
    var outOf: Double
    var dueDate: String
    var artificial: Bool
    var meta: [AssignmentMeta]

    var isNoCount: Bool { meta.contains { $0.type == "noCount" } }
    var isMissing: Bool { meta.contains { $0.type == "missing" } }
    var isAbsent: Bool { meta.contains { $0.type == "absent" } }
}

enum GradeCalculator {
    static func percentage(earned: Double?, outOf: Double?) -> Double? {
        guard let earned, let outOf,
              earned.isFinite, outOf.isFinite, outOf > 0 else {
            return nil
        }
        return earned / outOf * 100
    }

    /// Weighted course total from assignments + per-category weights.
    /// For SM1/SM2 views, computes the semester grade as 40/40/20 (RC, RC, exam)
    /// or RC average when no exam grade exists — matching the district's policy.
    static func summary(
        assignments: [CalcAssignment],
        categoryWeights: [String: Double],
        quarterTotals: (first: Double?, second: Double?)? = nil,
        selectedTerm: TermLabel? = nil,
        finalExamGrade: Double? = nil
    ) -> GradeSummary {
        let countable = assignments.filter { !$0.isNoCount && $0.grade != nil }

        var raw: [String: (points: Double, total: Double)] = [:]
        for a in countable {
            var entry = raw[a.category] ?? (0, 0)
            entry.points += a.grade ?? 0
            entry.total += a.outOf
            raw[a.category] = entry
        }

        var weightedSum = 0.0
        var totalWeight = 0.0
        var categories: [String: GradeSummary.CategoryResult] = [:]
        for (cat, data) in raw {
            let weight = categoryWeights[cat] ?? 0
            let average = data.total > 0 ? (data.points / data.total) * 100 : 0
            weightedSum += average * weight
            totalWeight += weight
            categories[cat] = .init(average: (average * 100).rounded() / 100, weight: weight,
                                    rawPoints: data.points, rawTotal: data.total)
        }

        var sm1: Double? = nil
        var sm2: Double? = nil
        var courseTotal: Double? = totalWeight > 0 ? weightedSum / totalWeight : nil

        if let selectedTerm, selectedTerm.isSemester, let quarterTotals {
            let rcA = quarterTotals.first.map { $0.rounded() }
            let rcB = quarterTotals.second.map { $0.rounded() }
            var semester: Double? = nil
            if let rcA, let rcB {
                if let exam = finalExamGrade {
                    semester = rcA * 0.4 + rcB * 0.4 + exam * 0.2
                } else {
                    semester = (rcA + rcB) / 2
                }
            } else {
                semester = rcA ?? rcB
            }
            if selectedTerm == .sm1 { sm1 = semester } else { sm2 = semester }
            if let semester { courseTotal = semester }
        }

        return GradeSummary(courseTotal: courseTotal, categories: categories, sm1: sm1, sm2: sm2)
    }

    /// Normalizes weights over only the categories that have graded work.
    static func normalizedWeights(categories: [GradeCategory], assignments: [CalcAssignment]) -> [String: Double] {
        let nonEmpty = Set(assignments.filter { $0.grade != nil && $0.category != "Final Exam" }.map(\.category))
        let adjusted = categories.compactMap { cat -> (String, Double)? in
            guard nonEmpty.contains(cat.category), let weight = cat.weight else { return nil }
            return (cat.category, weight)
        }
        let total = adjusted.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [:] }
        return Dictionary(uniqueKeysWithValues: adjusted.map { ($0.0, $0.1 / total * 100) })
    }
}

// MARK: - Semester averages (port of semesterAverageCalculator.tsx)

enum SemesterMath {
    static func parseAndRoundRC(_ grade: String?) -> Double? {
        guard let grade, !grade.isEmpty, grade != "P", grade != "X", let value = Double(grade) else { return nil }
        return value.rounded()
    }

    static func semesterAverage(rcA: String?, rcB: String?, exam: String?) -> Double? {
        let a = parseAndRoundRC(rcA)
        let b = parseAndRoundRC(rcB)
        let examGrade = exam.flatMap { Double($0) }
        if let a, let b {
            if let examGrade { return a * 0.4 + b * 0.4 + examGrade * 0.2 }
            return (a + b) / 2
        }
        return a ?? b
    }
}

// MARK: - Term GPA across courses (port of unifiedGpaManager.tsx)

enum GPACalculator {
    static let allTerms = ["PR1", "PR2", "RC1", "PR3", "PR4", "RC2",
                           "PR5", "PR6", "RC3", "PR7", "PR8", "RC4", "SM1", "SM2"]
    static let graphTerms = ["PR1", "PR2", "RC1", "PR3", "PR4", "RC2",
                             "PR5", "PR6", "RC3", "PR7", "PR8", "RC4"]

    static func termGPAs(courses: [UnifiedCourseData]) -> [String: GPAData] {
        termGPAs(courses: courses, manualClasses: [])
    }

    /// Term GPAs for manually entered classes (sm1/sm2 only).
    static func termGPAs(manualClasses: [ManualClass]) -> [String: GPAData] {
        termGPAs(courses: [], manualClasses: manualClasses)
    }

    /// Combines Skyward courses with manual classes used only for school years
    /// that have no Skyward history.
    static func termGPAs(
        courses: [UnifiedCourseData],
        manualClasses: [ManualClass]
    ) -> [String: GPAData] {
        var result: [String: GPAData] = [:]
        for term in allTerms {
            var totalUnweighted = 0.0
            var totalWeighted = 0.0
            var count = 0

            for course in courses {
                var gradeStr = course.historicalGrades[term.lowercased()]

                if ["RC1", "RC2", "RC3", "RC4"].contains(term),
                   let g = gradeStr, let value = Double(g) {
                    gradeStr = String(value.rounded())
                }

                if ["SM1", "SM2"].contains(term), gradeStr == nil || gradeStr?.isEmpty == true {
                    let h = course.historicalGrades
                    let avg = term == "SM1"
                        ? SemesterMath.semesterAverage(rcA: h.rc1, rcB: h.rc2, exam: h.ex1)
                        : SemesterMath.semesterAverage(rcA: h.rc3, rcB: h.rc4, exam: h.ex2)
                    gradeStr = avg.map { String($0) }
                }

                guard let g = gradeStr, let score = Double(g), score.isFinite else { continue }
                totalUnweighted += score
                totalWeighted += score + CourseLevelDetector.level(for: course.courseName).gpaBonus
                count += 1
            }

            if term == "SM1" || term == "SM2" {
                let keyPath = term == "SM1" ? \ManualClass.sm1 : \ManualClass.sm2
                for manualClass in manualClasses {
                    guard let grade = manualClass[keyPath: keyPath],
                          grade.isFinite, grade >= 0 else { continue }
                    let score = min(max(grade, 0), 100)
                    let bonus = CourseLevelDetector.level(for: manualClass.className).gpaBonus
                    totalUnweighted += score
                    totalWeighted += min(score + bonus, 110)
                    count += 1
                }
            }

            if count > 0 {
                result[term] = GPAData(
                    unweighted: roundTo2(totalUnweighted / Double(count)),
                    weighted: roundTo2(totalWeighted / Double(count))
                )
            }
        }
        return result
    }

    private static func roundTo2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

// MARK: - Academic calendar (port of academicCalendar.tsx)

enum AcademicCalendar {
    /// The term the given date falls in. Academic year runs Aug–Jul.
    static func currentTerm(for date: Date = Date()) -> TermLabel {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)   // 1-based
        let day = calendar.component(.day, from: date)
        let dayOfYearKey = month * 100 + day

        switch dayOfYearKey {
        case 815...1025: return .q1
        case 1026...1222: return .q2
        case 1223...1231, 101...108: return .sm1
        case 109...315: return .q3
        case 316...531: return .q4
        case 601...731: return .sm2
        default: return .q1   // early August / gaps
        }
    }
}

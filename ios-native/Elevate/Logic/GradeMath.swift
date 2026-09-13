import Foundation

extension TermLabel {
    /// Quarter buckets that contribute to this selected term. New semester
    /// what-if assignments must choose one of these buckets so their effect is
    /// unambiguous and can be recomputed from the matching gradebook.
    var whatIfQuarterTerms: [TermLabel] {
        switch self {
        case .sm1: return [.q1, .q2]
        case .sm2: return [.q3, .q4]
        default: return [self]
        }
    }

    /// Older builds stored semester-created assignments as SM1/SM2 even though
    /// those buckets cannot be recalculated as a quarter. Treat them as part of
    /// the semester's second quarter during one-time migration.
    var legacyWhatIfQuarter: TermLabel? {
        switch self {
        case .sm1: return .q2
        case .sm2: return .q4
        default: return nil
        }
    }
}

enum TermSelectionPolicy {
    /// Advance a term automatically only while the user is still following the
    /// term that was selected automatically on the previous activation.
    static func selectionOnActivation(
        selected: TermLabel,
        current: TermLabel,
        lastAutomatic: TermLabel
    ) -> TermLabel {
        selected == lastAutomatic ? current : selected
    }
}

// MARK: - Class name formatting (port of formatClassName.tsx)

/// Exact district titles, not a general independent-study bonus. The current
/// WHS English electives catalog identifies LA145 as Seminar and LA146 as
/// Research; Independent Study III (LA147) is a separate non-AP course.
/// https://whs.eanesisd.net/coursecatalog/courses/la/electives
enum APCapstoneCourse: CaseIterable {
    case seminar, research

    static func matching(_ title: String) -> APCapstoneCourse? {
        let tokens = title.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { $0 == "I" ? "1" : $0 == "II" ? "2" : String($0) }
        for course in allCases {
            let number = course == .seminar ? "1" : "2"
            let subject = course == .seminar ? "SEMINAR" : "RESEARCH"
            let code = course == .seminar ? "LA145" : "LA146"
            if tokens == [code] { return course }
            let name = (tokens.last == code ? Array(tokens.dropLast()) : tokens).joined(separator: " ")
            let stems = ["ENGLISH INDEPENDENT STUDY \(number)", "INDEPENDENT STUDY IN ENGLISH \(number)"]
            let aliases = ["AP \(subject)", "AP CAPSTONE \(subject)"] + stems
                + (stems + ["ENGLISH INDEPENDENT STUDY", "INDEPENDENT STUDY IN ENGLISH"])
                    .map { "\($0) AP CAPSTONE \(subject)" }
            if aliases.contains(name) { return course }
        }
        return nil
    }
}

enum ClassNameFormatter {
    private static let acronyms: Set<String> = [
        "AP", "IB", "GT", "ELA", "BC", "AB", "CSA", "CSP", "APUSH", "US", "UK", "EU",
        "PE", "IT", "CS", "AI", "ML", "CAD", "CTE", "STEM", "LOTE",
    ]

    static func format(_ raw: String) -> String {
        var name = raw
        if name.hasSuffix("FF") { return "Invention & Innovation FF" }
        if name.hasSuffix("HONORS") {
            name = name.replacingOccurrences(of: "HONORS", with: "H").trimmingCharacters(in: .whitespaces)
        }
        return name.uppercased()
            .split(whereSeparator: { $0 == "_" || $0.isWhitespace })
            .map { word -> String in
                let w = String(word)
                guard let start = w.firstIndex(where: \.isLetter),
                      let end = w.lastIndex(where: \.isLetter) else { return w }
                let prefix = String(w[..<start])
                let suffix = String(w[w.index(after: end)...])
                let letters = String(w[start...end])
                if acronyms.contains(letters) || letters.allSatisfy({ $0 == "I" }) {
                    return prefix + letters + suffix
                }
                return prefix + letters.prefix(1) + letters.dropFirst().lowercased() + suffix
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

    static func level(for className: String, catalogCourseCode: String? = nil) -> CourseLevel {
        // These exact district codes identify the two AP Capstone courses even
        // when Skyward truncates their titles. Unknown codes retain name policy.
        switch catalogCourseCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "LA145", "LA146": return .ap
        default: break
        }
        let normalized = className.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return .regular }

        if APCapstoneCourse.matching(className) != nil { return .ap }
        let hasAPKeyword = normalized.range(of: #"\bap\b"#, options: .regularExpression) != nil
        if hasAPKeyword || matchesException(normalized, in: apExceptions) { return .ap }

        let hasHonorsKeyword = normalized.range(of: #"\bhonors?\b"#, options: .regularExpression) != nil
        let hasTrailingHonorsMarker = normalized.range(of: #"\bh$"#, options: .regularExpression) != nil
        if hasHonorsKeyword || hasTrailingHonorsMarker || matchesException(normalized, in: honorsExceptions) {
            return .honors
        }

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
        sourceCategories: [GradeCategory] = [],
        quarterTotals: (first: Double?, second: Double?)? = nil,
        selectedTerm: TermLabel? = nil,
        finalExamGrade: Double? = nil
    ) -> GradeSummary {
        // Preserve decimal input precision through category accumulation. Skyward's
        // observed weighted totals round each category's contribution, not its
        // average or only the final sum, to hundredths before adding them.
        var raw: [String: (points: Decimal, total: Decimal)] = [:]
        for assignment in assignments where !assignment.isNoCount {
            guard let grade = assignment.grade,
                  let points = decimal(grade), let total = decimal(assignment.outOf) else { continue }
            var entry = raw[assignment.category] ?? (0, 0)
            entry.points += points
            entry.total += total
            raw[assignment.category] = entry
        }

        // Original weights avoid converting repeating normalized Double ratios
        // back into decimals at a half-cent boundary. Display weights stay normalized.
        var originalWeights: [String: Double] = [:]
        for category in sourceCategories {
            if let weight = category.weight { originalWeights[category.category] = weight }
        }
        var calculationWeights: [String: Decimal] = [:]
        for category in raw.keys {
            calculationWeights[category] = decimal(originalWeights[category] ?? categoryWeights[category] ?? 0) ?? 0
        }
        let totalWeight = calculationWeights.values.reduce(Decimal.zero, +)
        var weightedTotal = Decimal.zero
        var categories: [String: GradeSummary.CategoryResult] = [:]
        for (category, data) in raw {
            let average = data.total > 0 ? data.points / data.total * 100 : 0
            if totalWeight > 0 {
                let contribution = average * (calculationWeights[category] ?? 0) / totalWeight
                weightedTotal += roundedHundredths(contribution)
            }
            categories[category] = .init(
                average: double(roundedHundredths(average)), weight: categoryWeights[category] ?? 0,
                rawPoints: double(data.points), rawTotal: double(data.total)
            )
        }

        var sm1: Double? = nil
        var sm2: Double? = nil
        var courseTotal: Double? = totalWeight > 0 ? double(weightedTotal) : nil

        if let selectedTerm, selectedTerm.isSemester, let quarterTotals {
            let semester = semesterTotal(
                firstQuarter: quarterTotals.first,
                secondQuarter: quarterTotals.second,
                finalExamGrade: finalExamGrade
            )
            if selectedTerm == .sm1 { sm1 = semester } else { sm2 = semester }
            if let semester { courseTotal = semester }
        }

        return GradeSummary(courseTotal: courseTotal, categories: categories, sm1: sm1, sm2: sm2)
    }

    private static func decimal(_ value: Double) -> Decimal? {
        guard value.isFinite else { return nil }
        return Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func double(_ value: Decimal) -> Double {
        // Decimal's direct doubleValue conversion can land one ULP above the
        // nearest Double (for example 92.02). Parse its decimal representation.
        let number = NSDecimalNumber(decimal: value)
        return Double(number.stringValue) ?? number.doubleValue
    }

    private static func roundedHundredths(_ value: Decimal) -> Decimal {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }

    /// Points-based gradebooks can omit category weights, including an empty
    /// quarter to which the student adds hypothetical work.
    static func pointsTotal(assignments: [CalcAssignment]) -> Double? {
        let counted = assignments.filter {
            !$0.isNoCount && $0.category != "Final Exam" && $0.grade?.isFinite == true
                && $0.outOf.isFinite && $0.outOf > 0
        }
        let possible = counted.reduce(0) { $0 + $1.outOf }
        guard possible > 0 else { return nil }
        return counted.reduce(0) { $0 + ($1.grade ?? 0) } / possible * 100
    }

    /// District semester policy. Quarter grades are rounded before the 40/40/20
    /// calculation, matching posted report-card math. Without an exam, the two
    /// quarters are averaged; a single available quarter remains usable.
    static func semesterTotal(
        firstQuarter: Double?,
        secondQuarter: Double?,
        finalExamGrade: Double?
    ) -> Double? {
        let first = firstQuarter?.rounded()
        let second = secondQuarter?.rounded()
        if let first, let second {
            if let finalExamGrade {
                return first * 0.4 + second * 0.4 + finalExamGrade * 0.2
            }
            return (first + second) / 2
        }
        return first ?? second
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

            for course in courses where course.isPlanningOnly != true {
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
                let weighted = score + course.courseLevel.gpaBonus
                totalWeighted += min(weighted, 110)
                count += 1
            }

            if term == "SM1" || term == "SM2" {
                let keyPath = term == "SM1" ? \ManualClass.sm1 : \ManualClass.sm2
                for manualClass in manualClasses {
                    guard let grade = manualClass[keyPath: keyPath],
                          grade.isFinite, grade >= 0 else { continue }
                    // Manual entry permits legitimate extra-credit grades. Keep
                    // the unweighted contribution intact while bounding the
                    // weighted scale to the district maximum.
                    let score = max(grade, 0)
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
    /// Uses the district's Gregorian school day even when the device travels.
    static func currentTerm(for date: Date = Date()) -> TermLabel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)   // 1-based
        let day = calendar.component(.day, from: date)
        let dayOfYearKey = month * 100 + day

        // Eanes 2026–27 Student Calendar, specific to this school year:
        // https://resources.finalsite.net/images/v1772560663/eanesisdnet/upu1dn8wbinzko3qfhub/2026-27STUDENTCALENDAR.pdf
        // Q1 starts Aug 13 and ends Oct 8; Q2 starts Oct 13. Keep Q1 during
        // preseason and the intervening break, and Q3 through spring break.
        // Preserve semester review after each semester's final school day.
        switch year * 10_000 + dayOfYearKey {
        case 20260801...20261012: return .q1
        case 20261013...20261218: return .q2
        case 20261219...20270104: return .sm1
        case 20270105...20270321: return .q3
        case 20270322...20270521: return .q4
        case 20270522...20270731: return .sm2
        default: break
        }

        // Approximate legacy dates for other academic years. The dated district
        // schedule above is not assumed to repeat in past or future years.
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

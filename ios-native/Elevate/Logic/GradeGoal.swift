import Foundation

/// The caller must choose what happens to other ungraded work. Ignoring it
/// excludes it from this scenario; it never fabricates a zero or predicts it.
enum GradeGoalUngradedPolicy: Sendable {
    case ignoreUngraded
    case requireAllGraded
}

enum GradeGoalAssignmentChoice: Sendable {
    case new(category: String, possible: Double)
    case existingID(String)
    case existingIndex(Int)
}

struct GradeGoalResult: Equatable, Sendable {
    enum UnavailableReason: Equatable, Sendable {
        case invalidInput
        case missingQuarter
        case unresolvedAssignments
        case assignmentNotFound
        case excludedAssignment
        case noEffectiveCategory
        case invalidWeights
        case searchLimit
    }

    enum Status: Equatable, Sendable {
        case required
        case alreadyGuaranteed
        case aboveMaximum
        case fixedResult
        case unavailable(UnavailableReason)
    }

    var status: Status
    /// The minimum score at hundredth-point precision, forward-checked against
    /// the real calculator. Original scores are never rounded or mutated.
    var requiredEarned: Double?
    var requiredPercentage: Double?
    var resultingGrade: Double?
    /// Forward-calculated grade at the selected maximum; nil for an unbounded scenario.
    var maximumGrade: Double?
    var targetMet: Bool

    var aboveFullCredit: Bool { (requiredPercentage ?? 0) > 100 }

    fileprivate static func unavailable(_ reason: UnavailableReason) -> Self {
        Self(status: .unavailable(reason), targetMet: false)
    }
}

enum GradeGoalSolver {
    // Matches the local what-if score bound and keeps every search below 28
    // evaluations after bracketing. Finite but extreme source inputs fail closed.
    private static let scoreLimit = 1_000_000.0
    private static let maximumCents = 100_000_000

    /// Both quarter values are explicit end-of-quarter assumptions. A posted
    /// exam is fixed, so there is no remaining score to solve for.
    static func semesterExam(
        target: Double,
        firstQuarter: Double?,
        secondQuarter: Double?,
        postedExam: Double? = nil,
        maximumPercentage: Double? = 100
    ) -> GradeGoalResult {
        guard valid(target), validMaximum(maximumPercentage) else { return .unavailable(.invalidInput) }
        guard let firstQuarter, let secondQuarter else { return .unavailable(.missingQuarter) }
        guard valid(firstQuarter), valid(secondQuarter), postedExam.map(valid) ?? true else {
            return .unavailable(.invalidInput)
        }
        let evaluate: (Double) -> Double? = { exam in
            GradeCalculator.semesterTotal(
                firstQuarter: firstQuarter, secondQuarter: secondQuarter, finalExamGrade: exam
            )
        }
        if let postedExam, let result = evaluate(postedExam) {
            return GradeGoalResult(status: .fixedResult, resultingGrade: result, targetMet: result >= target)
        }
        return solve(target: target, possible: 100, maximumPercentage: maximumPercentage, evaluate: evaluate)
    }

    /// Solves one counted score, holding every other included score fixed.
    /// A new category participates even at zero earned points, so its weight
    /// activation and all category renormalization occur before searching.
    static func assignment(
        target: Double,
        assignments: [CalcAssignment],
        categories: [GradeCategory],
        choice: GradeGoalAssignmentChoice,
        ungradedPolicy: GradeGoalUngradedPolicy,
        maximumPercentage: Double? = 100
    ) -> GradeGoalResult {
        guard valid(target), validMaximum(maximumPercentage),
              assignments.count <= 10_000, categories.count <= 1_000 else {
            return .unavailable(.invalidInput)
        }
        var scenario = assignments
        let selected: Int
        switch choice {
        case let .new(category, possible):
            selected = scenario.count
            scenario.append(CalcAssignment(
                id: "grade-goal", className: "", name: "", term: "", category: category,
                grade: 0, outOf: possible, dueDate: "", artificial: true, meta: []
            ))
        case let .existingIndex(index):
            guard scenario.indices.contains(index) else { return .unavailable(.assignmentNotFound) }
            selected = index
        case let .existingID(id):
            let matches = scenario.indices.filter { scenario[$0].id == id }
            guard matches.count == 1, let index = matches.first else { return .unavailable(.assignmentNotFound) }
            selected = index
        }
        let subject = scenario[selected]
        guard !subject.isNoCount, subject.category != "Final Exam" else { return .unavailable(.excludedAssignment) }
        guard valid(subject.outOf), subject.outOf > 0, !subject.category.isEmpty,
              subject.grade.map(valid) ?? true else {
            return .unavailable(.invalidInput)
        }
        // Replace only the chosen score. Other ungraded values remain absent.
        scenario[selected].grade = 0
        let included = scenario.filter { !$0.isNoCount && $0.category != "Final Exam" }
        guard included.allSatisfy({ valid($0.outOf) && ($0.grade.map(valid) ?? true) }) else {
            return .unavailable(.invalidInput)
        }
        if ungradedPolicy == .requireAllGraded, included.contains(where: { $0.grade == nil }) {
            return .unavailable(.unresolvedAssignments)
        }
        guard Set(categories.map(\.category)).count == categories.count,
              categories.allSatisfy({ $0.weight.map(valid) ?? true }) else {
            return .unavailable(.invalidWeights)
        }
        let weighted = categories.contains { $0.weight != nil }
        if weighted {
            guard let weight = categories.first(where: { $0.category == subject.category })?.weight,
                  weight > 0 else { return .unavailable(.noEffectiveCategory) }
        }
        return solve(target: target, possible: subject.outOf, maximumPercentage: maximumPercentage) { earned in
            var evaluated = scenario
            evaluated[selected].grade = earned
            let countable = evaluated.filter { !$0.isNoCount && $0.category != "Final Exam" }
            if !weighted { return GradeCalculator.pointsTotal(assignments: countable) }
            let weights = GradeCalculator.normalizedWeights(categories: categories, assignments: countable)
            return GradeCalculator.summary(
                assignments: countable, categoryWeights: weights, sourceCategories: categories
            ).courseTotal
        }
    }

    private static func valid(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= scoreLimit
    }

    private static func validMaximum(_ value: Double?) -> Bool { value.map(valid) ?? true }

    private static func solve(
        target: Double,
        possible: Double,
        maximumPercentage: Double?,
        evaluate: (Double) -> Double?
    ) -> GradeGoalResult {
        guard let lowest = evaluate(0), lowest.isFinite else { return .unavailable(.noEffectiveCategory) }
        let maximumGrade = maximumPercentage.flatMap { evaluate(possible * ($0 / 100)) }
        if lowest >= target {
            return GradeGoalResult(
                status: .alreadyGuaranteed, requiredEarned: 0, requiredPercentage: 0,
                resultingGrade: lowest, maximumGrade: maximumGrade, targetMet: true
            )
        }
        // Search the representable score grid directly: this is equivalent to
        // rounding a mathematical threshold upward, without rounding a binary
        // approximation of an exact decimal boundary to an unnecessary cent.
        var lower = 0
        var upper = min(maximumCents, max(1, Int(ceil(possible * 100))))
        while true {
            guard let grade = evaluate(Double(upper) / 100), grade.isFinite else {
                return .unavailable(.invalidInput)
            }
            if grade >= target { break }
            guard upper < maximumCents else { return .unavailable(.searchLimit) }
            lower = upper
            upper = min(maximumCents, upper * 2)
        }
        while lower + 1 < upper {
            let middle = lower + (upper - lower) / 2
            guard let grade = evaluate(Double(middle) / 100), grade.isFinite else {
                return .unavailable(.invalidInput)
            }
            if grade >= target { upper = middle } else { lower = middle }
        }
        let earned = Double(upper) / 100
        guard let resultingGrade = evaluate(earned), resultingGrade.isFinite, resultingGrade >= target else {
            return .unavailable(.searchLimit)
        }
        let percentage = earned / possible * 100
        guard percentage.isFinite else { return .unavailable(.searchLimit) }
        let aboveMaximum = maximumPercentage.map { earned > possible * ($0 / 100) } ?? false
        return GradeGoalResult(
            status: aboveMaximum ? .aboveMaximum : .required,
            requiredEarned: earned, requiredPercentage: percentage,
            resultingGrade: resultingGrade, maximumGrade: maximumGrade, targetMet: true
        )
    }
}

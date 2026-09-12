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


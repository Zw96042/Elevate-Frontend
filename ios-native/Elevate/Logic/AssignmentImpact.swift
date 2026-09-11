import Foundation

struct AssignmentImpactResult: Equatable {
    enum UnavailableReason: Equatable {
        case invalidInput
        case differentTerm
        case unavailableGradebook
        case assignmentNotFound
        case excludedAssignment
        case unavailableCategory
        case calculation(WhatIfScenarioIssue)
    }

    var before: Double?
    var after: Double?
    var issue: UnavailableReason?
    /// Fixed-score sensitivity, not a prediction of remaining work or teacher policy.
    var assumptions: [String]

    var difference: Double? {
        guard let before, let after else { return nil }
        return after - before
    }
}

enum AssignmentImpactCalculator {
    /// Uses official assignments only. A named scenario is a separate local
    /// planning tool and never changes this official before/after baseline.
    static func calculate(
        assignmentID: String,
        quarter: TermLabel,
        earned: Double?,
        source: WhatIfScenarioSource
    ) -> AssignmentImpactResult {
        var assumptions = ["All other counted assignment scores stay fixed. Ungraded work stays ungraded."]
        if source.term.isSemester {
            assumptions.append("Untouched quarters keep their posted grades. Quarter grades are rounded before the district semester calculation.")
            assumptions.append(source.officialExamGrade == nil
                               ? "With no posted exam, the available quarter grades are averaged."
                               : "The posted exam score stays fixed; two quarters count 40% each and the exam counts 20%.")
        }
        func unavailable(_ reason: AssignmentImpactResult.UnavailableReason) -> AssignmentImpactResult {
            AssignmentImpactResult(before: source.officialGrade, after: nil, issue: reason, assumptions: assumptions)
        }
        guard earned.map(WhatIfScenarioEvaluator.validNumber) ?? true, !assignmentID.isEmpty else {
            return unavailable(.invalidInput)
        }
        guard !quarter.isSemester, source.term.whatIfQuarterTerms.contains(quarter) else {
            return unavailable(.differentTerm)
        }
        guard let info = source.quarterGradebooks[quarter.shortName] else { return unavailable(.unavailableGradebook) }
        let assignments = AssignmentGradeEdits.assignments(from: info, className: source.className, term: quarter)
        let matches = assignments.filter { $0.id == assignmentID }
        guard matches.count == 1, let selected = matches.first else { return unavailable(.assignmentNotFound) }
        guard !selected.isNoCount, selected.category != "Final Exam" else { return unavailable(.excludedAssignment) }
        guard WhatIfScenarioEvaluator.validNumber(selected.outOf), selected.outOf >= 0 else { return unavailable(.invalidInput) }
        let categories = info.gradebook.filter { $0.category != "Final Exam" }
        if categories.contains(where: { $0.weight != nil }) {
            guard let weight = categories.first(where: { $0.category == selected.category })?.weight,
                  weight.isFinite, weight > 0 else { return unavailable(.unavailableCategory) }
        }
        let snapshot = WhatIfScenarioSnapshot(overridesByQuarter: [quarter.shortName: [assignmentID: .init(grade: earned)]])
        let baseline = WhatIfScenarioEvaluator.evaluate(.init(), source: source)
        let result = WhatIfScenarioEvaluator.evaluate(snapshot, source: source)
        if let issue = result.issue { return unavailable(.calculation(issue)) }
        guard let before = baseline.value, let after = result.value, before.isFinite, after.isFinite else {
            return unavailable(.calculation(.unavailableCalculation(quarter: quarter.shortName)))
        }
        return AssignmentImpactResult(before: before, after: after, issue: nil, assumptions: assumptions)
    }
}

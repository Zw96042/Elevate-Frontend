import Testing
@testable import ElevateCore

@Suite("Official assignment impact")
struct AssignmentImpactTests {
    private func row(_ name: String = "Quiz", earned: Double? = 80, possible: Double = 100,
                     noCount: Bool = false) -> GradeInfoAssignment {
        .init(date: "", name: name, grade: nil, score: nil, pointsEarned: earned, pointsTotal: possible,
              meta: noCount ? [.init(type: "noCount", note: "Teacher exclusion")] : [])
    }

    private func book(_ rows: [GradeInfoAssignment], weight: Double? = 100, posted: Double? = 80) -> GradeInfoResult {
        .init(course: "Synthetic", instructor: "", period: nil, litName: "", litBegin: nil, litEnd: nil,
              gradebook: [.init(category: "Tests", weight: weight, adjustedWeight: nil, assignments: rows)], score: posted, grade: nil)
    }

    private func source(_ info: GradeInfoResult, term: TermLabel = .q1, official: Double? = 80,
                        posted: [String: Double] = [:], exam: Double? = nil) -> WhatIfScenarioSource {
        .init(classKey: "synthetic-course", className: "Synthetic", term: term,
              quarterGradebooks: ["Q1": info], postedQuarterGrades: posted, officialGrade: official, officialExamGrade: exam)
    }

    private func impact(_ info: GradeInfoResult, earned: Double?, index: Int = 0,
                        term: TermLabel = .q1, official: Double? = 80,
                        posted: [String: Double] = [:], exam: Double? = nil) -> AssignmentImpactResult {
        let id = AssignmentGradeEdits.assignments(from: info, className: "Synthetic", term: .q1)[index].id
        return AssignmentImpactCalculator.calculate(assignmentID: id, quarter: .q1, earned: earned,
                                                     source: source(info, term: term, official: official, posted: posted, exam: exam))
    }

    @Test("Before is official and after uses the exact weighted category calculator")
    func forwardMath() {
        var info = book([row(earned: 90.01)], weight: 1, posted: 15.34)
        info.gradebook.append(.init(category: "Other", weight: 5, adjustedWeight: nil,
                                   assignments: [row("Other", earned: 0)]))
        let result = impact(info, earned: 92.01, official: 15.34)
        #expect(result.before == 15.34)
        #expect(result.after == 15.34)
        #expect(result.difference == 0)
        #expect(result.issue == nil)
        #expect(!result.assumptions.isEmpty)
        let rounded = impact(book([row(earned: 80)]), earned: 95.123456789)
        #expect(rounded.after == 95.12)
        #expect(rounded.before == 80)
    }

    @Test("Zero and legitimate extra credit remain actual scores without clamping")
    func zeroAndBonus() {
        let info = book([row(earned: 80)])
        #expect(impact(info, earned: 0).after == 0)
        #expect(impact(info, earned: 105.123).after == 105.12)
        let bonus = book([row(earned: 10, possible: 10), row("Bonus", earned: nil, possible: 0)], posted: 100)
        let result = impact(bonus, earned: 0.003, index: 1, official: 100)
        #expect(result.after == 100.03)
        #expect(result.before == 100)
        #expect(result.issue == nil)
        #expect(impact(info, earned: -1.015).after == -1.02)
        let onlyBonus = impact(book([row(earned: nil, possible: 0)], posted: nil), earned: 2, official: nil)
        #expect(onlyBonus.after == nil)
        #expect(onlyBonus.issue == .calculation(.unavailableCalculation(quarter: "Q1")))
    }

    @Test("Points gradebooks and ungraded removal follow the existing calculator")
    func pointsAndNil() {
        let info = book([row(earned: 8, possible: 10), row("Second", earned: 17, possible: 20)], weight: nil, posted: nil)
        let result = impact(info, earned: 10, official: nil)
        #expect(result.before == GradeCalculator.pointsTotal(assignments: AssignmentGradeEdits.assignments(from: info, className: "Synthetic", term: .q1)))
        #expect(result.after == 90)
        #expect(impact(info, earned: nil, official: nil).after == 85)
        #expect(impact(book([row()]), earned: nil).after == nil)
    }

    @Test("Semester impact keeps the other posted quarter and applies RC rounding plus 40/40/20")
    func semester() {
        let info = book([row(earned: 80)], posted: 80)
        let result = impact(info, earned: 90.5, term: .sm1, official: 85, posted: ["Q2": 93.4999], exam: 70)
        #expect(result.before == 85)
        #expect(result.after == GradeCalculator.semesterTotal(firstQuarter: 90.5, secondQuarter: 93.4999, finalExamGrade: 70))
        #expect(result.assumptions.count == 3)
        let noExam = impact(info, earned: 90.4999, term: .sm1, official: 86, posted: ["Q2": 93.5])
        // The weighted contribution first rounds to 90.50, then RC math
        // rounds that quarter to 91; the untouched 93.5 rounds to 94.
        #expect(noExam.after == 92.5)
        #expect(noExam.assumptions.last?.contains("no posted exam") == true)
    }

    @Test("Unavailable and mismatched sources, unknown IDs, and exclusions give explicit reasons")
    func unavailableCases() {
        let info = book([row()])
        var missing = source(info)
        missing.quarterGradebooks = [:]
        #expect(AssignmentImpactCalculator.calculate(assignmentID: "id", quarter: .q1, earned: 90, source: missing).issue == .unavailableGradebook)
        #expect(AssignmentImpactCalculator.calculate(assignmentID: "id", quarter: .q2, earned: 90, source: source(info)).issue == .differentTerm)
        #expect(AssignmentImpactCalculator.calculate(assignmentID: "id", quarter: .sm1, earned: 90, source: source(info)).issue == .differentTerm)
        #expect(AssignmentImpactCalculator.calculate(assignmentID: "stale", quarter: .q1, earned: 90, source: source(info)).issue == .assignmentNotFound)
        #expect(impact(book([row(noCount: true)]), earned: 90).issue == .excludedAssignment)
        var examBook = info
        examBook.gradebook[0].category = "Final Exam"
        #expect(impact(examBook, earned: 90).issue == .excludedAssignment)
        #expect(impact(book([row()], weight: 0), earned: 90).issue == .unavailableCategory)
    }

    @Test("Nonfinite earned values and malformed category weights fail instead of producing a grade")
    func invalidNumbers() {
        for number in [Double.nan, Double.infinity, -Double.infinity, 1_000_001] {
            #expect(impact(book([row()]), earned: number).issue == .invalidInput)
        }
        #expect(impact(book([row(possible: .infinity)]), earned: 90).issue == .invalidInput)
        #expect(impact(book([row()], weight: .nan), earned: 90).issue == .unavailableCategory)
        var invalidCategories = book([row()])
        invalidCategories.gradebook.append(invalidCategories.gradebook[0])
        let result = impact(invalidCategories, earned: 90)
        #expect(result.after == nil)
        #expect(result.issue == .calculation(.invalidCategories))
    }
}

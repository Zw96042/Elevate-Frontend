import Testing
@testable import ElevateCore

@Suite("Bounded grade goals")
struct GradeGoalTests {
    private func row(_ id: String = "a", earned: Double? = 80, possible: Double = 100, category: String = "Tests", excluded: Bool = false) -> CalcAssignment {
        CalcAssignment(id: id, className: "Synthetic", name: "Synthetic", term: "Q1", category: category,
                       grade: earned, outOf: possible, dueDate: "", artificial: false,
                       meta: excluded ? [.init(type: "noCount", note: "Excluded")] : [])
    }

    private func category(_ name: String, _ weight: Double?) -> GradeCategory {
        GradeCategory(category: name, weight: weight, adjustedWeight: nil, assignments: [])
    }

    @Test("Semester exam uses both quarter assumptions and the existing RC rounding")
    func semesterPolicy() {
        let result = GradeGoalSolver.semesterExam(target: 90, firstQuarter: 91, secondQuarter: 93)
        #expect(result.status == .required)
        #expect(result.requiredEarned == 82)
        #expect(result.resultingGrade == 90)
        #expect(result.maximumGrade == 93.6)
        let below = GradeGoalSolver.semesterExam(target: 90, firstQuarter: 90.4999, secondQuarter: 92.4999)
        let above = GradeGoalSolver.semesterExam(target: 90, firstQuarter: 90.5, secondQuarter: 92.5)
        #expect(below.requiredEarned == 86)
        #expect(above.requiredEarned == 82)
    }

    @Test("Posted exams are fixed and absent quarters are not invented")
    func fixedAndMissing() {
        for exam in [40.0, 95] {
            let result = GradeGoalSolver.semesterExam(target: 90, firstQuarter: 91, secondQuarter: 93, postedExam: exam)
            #expect(result.status == .fixedResult)
            #expect(result.requiredEarned == nil)
            #expect(result.targetMet == (exam == 95))
            #expect(result.resultingGrade == GradeCalculator.semesterTotal(firstQuarter: 91, secondQuarter: 93, finalExamGrade: exam))
        }
        #expect(GradeGoalSolver.semesterExam(target: 90, firstQuarter: nil, secondQuarter: 93).status == .unavailable(.missingQuarter))
        #expect(GradeGoalSolver.semesterExam(target: 90, firstQuarter: 91, secondQuarter: nil).requiredEarned == nil)
    }

    @Test("Guaranteed means even a zero on remaining work meets the target")
    func lowestRemainingScore() {
        let guaranteed = GradeGoalSolver.semesterExam(target: 70, firstQuarter: 91, secondQuarter: 93)
        #expect(guaranteed.status == .alreadyGuaranteed)
        #expect(guaranteed.requiredEarned == 0)
        let future = GradeGoalSolver.assignment(target: 90, assignments: [row(earned: 100)], categories: [],
                                              choice: .new(category: "Tests", possible: 100), ungradedPolicy: .ignoreUngraded)
        #expect(future.status == .required)
        #expect(future.requiredEarned == 80)
        let low = GradeGoalSolver.assignment(target: 40, assignments: [row(earned: 100)], categories: [],
                                           choice: .new(category: "Tests", possible: 100), ungradedPolicy: .ignoreUngraded)
        #expect(low.status == .alreadyGuaranteed)
        #expect(low.resultingGrade == 50)
    }

    @Test("Bonus requirements preserve the mathematical score and selected maximum result")
    func bonus() {
        let bounded = GradeGoalSolver.semesterExam(target: 101, firstQuarter: 100, secondQuarter: 100)
        #expect(bounded.status == .aboveMaximum)
        #expect(bounded.requiredPercentage == 105)
        #expect(bounded.maximumGrade == 100)
        #expect(bounded.aboveFullCredit)
        let unbounded = GradeGoalSolver.semesterExam(target: 101, firstQuarter: 100, secondQuarter: 100, maximumPercentage: nil)
        #expect(unbounded.status == .required)
        #expect(unbounded.requiredEarned == 105)
        #expect(unbounded.maximumGrade == nil)
        let zeroBound = GradeGoalSolver.semesterExam(target: 90, firstQuarter: 91, secondQuarter: 93, maximumPercentage: 0)
        #expect(zeroBound.status == .aboveMaximum)
    }

    @Test("Display scores round upward and forward validation proves the target")
    func conservativePoints() throws {
        let existing = row(earned: 1.001, possible: 3)
        let result = GradeGoalSolver.assignment(target: 90, assignments: [existing], categories: [],
                                              choice: .new(category: "Tests", possible: 7), ungradedPolicy: .ignoreUngraded)
        let earned = try #require(result.requiredEarned)
        #expect(earned == 8)
        #expect(result.status == .aboveMaximum)
        #expect(try #require(result.resultingGrade) >= 90)
        let failed = GradeCalculator.pointsTotal(assignments: [existing, row("b", earned: earned - 0.01, possible: 7)])
        #expect(try #require(failed) < 90)
        #expect(existing.grade == 1.001)
    }

    @Test("Weighted thresholds round each contribution, not the total or category averages")
    func weightedContributions() throws {
        let assignments = [row("a", earned: nil, category: "A"), row("b", earned: 94.01, category: "B")]
        let categories = [category("A", 50), category("B", 50)]
        let result = GradeGoalSolver.assignment(target: 92.02, assignments: assignments, categories: categories,
                                              choice: .existingID("a"), ungradedPolicy: .requireAllGraded)
        #expect(result.requiredEarned == 90.01)
        #expect(result.resultingGrade == 92.02)
        var evaluated = assignments
        evaluated[0].grade = try #require(result.requiredEarned)
        #expect(GradeCalculator.summary(assignments: evaluated, categoryWeights: ["A": 50, "B": 50], sourceCategories: categories).courseTotal == 92.02)
        evaluated[0].grade = 90
        #expect(GradeCalculator.summary(assignments: evaluated, categoryWeights: ["A": 50, "B": 50], sourceCategories: categories).courseTotal == 92.01)
    }


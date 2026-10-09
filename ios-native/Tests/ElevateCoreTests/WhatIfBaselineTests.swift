import Testing
@testable import ElevateCore

@Suite("What-if authoritative baseline")
struct WhatIfBaselineTests {
    private func assignment(grade: Double? = 80, excluded: Bool = false) -> CalcAssignment {
        CalcAssignment(
            id: "synthetic-q1", className: "Synthetic course", name: "Quiz", term: "Q1",
            category: "Tests", grade: grade, outOf: 100, dueDate: "", artificial: false,
            meta: excluded ? [AssignmentMeta(type: "noCount", note: "Teacher exclusion")] : []
        )
    }

    @Test("Enabled editing without effective changes preserves the exact official value")
    func officialBaseline() {
        let original = assignment()
        for edits: [String: AssignmentGradeOverride] in [[:], [original.id: .init(grade: 80)]] {
            let changed = AssignmentGradeEdits.hasEffectiveChanges(edits, to: [original])
            let shown = WhatIfGradePresentation.resolve(official: 92.02, calculated: 92.01, hasEffectiveChanges: changed)
            #expect(shown.value == 92.02)
            #expect(shown.source == .official)
        }
        let precise = 92.021234567
        #expect(WhatIfGradePresentation.resolve(official: precise, calculated: 92.01, hasEffectiveChanges: false).value == precise)
    }

    @Test("Restored and refreshed scores stop being effective edits")
    func restoredAndRefreshed() {
        let original = assignment()
        let edits = [original.id: AssignmentGradeOverride(grade: 95)]
        #expect(AssignmentGradeEdits.hasEffectiveChanges(edits, to: [original]))
        #expect(!AssignmentGradeEdits.hasEffectiveChanges(edits, to: [assignment(grade: 95)]))
        #expect(!AssignmentGradeEdits.hasEffectiveChanges([original.id: .init(grade: 80)], to: [original]))
    }

    @Test("Counting choices remain independent of score edits and metadata wording")
    func countingChoices() {
        let original = assignment()
        let statusOnly = AssignmentGradeOverride(grade: nil, noCount: true, overridesGrade: false)
        #expect(AssignmentGradeEdits.hasEffectiveChanges([original.id: statusOnly], to: [original]))
        #expect(AssignmentGradeEdits.hasEffectiveChanges([original.id: statusOnly], to: [assignment(grade: 95)]))
        #expect(!AssignmentGradeEdits.hasEffectiveChanges([original.id: statusOnly], to: [assignment(excluded: true)]))
        let counted = AssignmentGradeOverride(grade: nil, noCount: false, overridesGrade: false)
        #expect(!AssignmentGradeEdits.hasEffectiveChanges([original.id: counted], to: [original]))
        #expect(AssignmentGradeEdits.hasEffectiveChanges([original.id: counted], to: [assignment(excluded: true)]))
        #expect(AssignmentGradeEdits.hasEffectiveChanges([original.id: .init(grade: 80, noCount: true)], to: [original]))
    }

    @Test("An explicit ungraded estimate differs only from a graded official score")
    func deliberatelyUngraded() {
        let original = assignment()
        let edits = [original.id: AssignmentGradeOverride(grade: nil)]
        #expect(AssignmentGradeEdits.hasEffectiveChanges(edits, to: [original]))
        #expect(!AssignmentGradeEdits.hasEffectiveChanges(edits, to: [assignment(grade: nil)]))
    }

    @Test("Invalid and orphaned overrides follow the application policy")
    func ignoredOverrides() {
        let original = assignment()
        for invalid in [Double.infinity, Double.nan, 1_000_001] {
            #expect(!AssignmentGradeEdits.hasEffectiveChanges([original.id: .init(grade: invalid, noCount: true)], to: [original]))
        }
        #expect(!AssignmentGradeEdits.hasEffectiveChanges(["other-quarter": .init(grade: 95)], to: [original]))
        #expect(!AssignmentGradeEdits.hasEffectiveChanges([original.id: .init(grade: 95)], to: []))
    }

    @Test("Estimates keep their source even when the value matches or becomes unavailable")
    func estimateSource() {
        let equal = WhatIfGradePresentation.resolve(official: 92.02, calculated: 92.02, hasEffectiveChanges: true)
        #expect(equal.value == 92.02)
        #expect(equal.source == .estimate)
        let unavailable = WhatIfGradePresentation.resolve(official: 92.02, calculated: nil, hasEffectiveChanges: true)
        #expect(unavailable.value == nil)
        #expect(unavailable.source == .estimate)
    }

    @Test("Missing official grades use an honestly labeled calculated fallback")
    func missingOfficial() {
        let shown = WhatIfGradePresentation.resolve(official: nil, calculated: 92.01, hasEffectiveChanges: false)
        #expect(shown.value == 92.01)
        #expect(shown.source == .calculated)
        #expect(WhatIfGradePresentation.resolve(official: nil, calculated: nil, hasEffectiveChanges: false).value == nil)
    }
    @Test("Weighted contributions round individually before their sum")
    func contributionRounding() {
        var first = assignment(grade: 90.01)
        var second = assignment(grade: 94.01)
        first.category = "A"
        second.category = "B"
        let result = GradeCalculator.summary(assignments: [first, second], categoryWeights: ["A": 50, "B": 50])
        // 45.005 + 47.005 becomes 45.01 + 47.01. Rounding category
        // averages or only the final total would incorrectly yield 92.01.
        #expect(result.courseTotal == 92.02)
        #expect(result.categories["A"]?.average == 90.01)
        #expect(result.categories["B"]?.average == 94.01)
        #expect(GradeCalculator.summary(assignments: [second, first], categoryWeights: ["B": 50, "A": 50]).courseTotal == 92.02)
        let changed = AssignmentGradeEdits.applying([first.id: .init(grade: 91.01)], to: [first]) + [second]
        #expect(GradeCalculator.summary(assignments: changed, categoryWeights: ["A": 50, "B": 50]).courseTotal == 92.52)
    }

    @Test("Original weights preserve decimal ties after display normalization")
    func originalWeights() {
        let source = [1.0, 2, 3].enumerated().map { index, weight in
            GradeCategory(category: "C\(index)", weight: weight, adjustedWeight: nil, assignments: [])
        }
        let assignments = source.enumerated().map { index, category in
            var value = assignment(grade: index == 0 ? 92.01 : 0)
            value.category = category.category
            return value
        }
        let normalized = GradeCalculator.normalizedWeights(categories: source, assignments: assignments)
        let result = GradeCalculator.summary(assignments: assignments, categoryWeights: normalized, sourceCategories: source)
        #expect(result.courseTotal == 15.34)
        #expect(result.categories["C0"]?.weight == normalized["C0"])
    }

    @Test("Contribution math retains decimal inputs, extra credit, exclusions, and negative scores")
    func decimalInputsAndStatuses() {
        var first = assignment(grade: 10.001)
        first.outOf = 10
        var bonus = assignment(grade: 0.002)
        bonus.outOf = 0
        let excluded = assignment(grade: 1000, excluded: true)
        let nilGrade = assignment(grade: nil)
        let result = GradeCalculator.summary(assignments: [first, bonus, excluded, nilGrade], categoryWeights: ["Tests": 100])
        #expect(result.courseTotal == 100.03)
        #expect(result.categories["Tests"]?.rawPoints == 10.003)
        #expect(first.grade == 10.001)
        #expect(GradeCalculator.summary(assignments: [assignment(grade: -1.015)], categoryWeights: ["Tests": 100]).courseTotal == -1.02)
        #expect(GradeCalculator.summary(assignments: [excluded, nilGrade], categoryWeights: ["Tests": 100]).courseTotal == nil)
    }

    @Test("An unavailable untouched quarter preserves its posted grade for semester predictions")
    func unavailableQuarterBaseline() {
        // Q2's fetch failed with no cached source; no Q2 edits are saved.
        let second = WhatIfGradePresentation.resolve(
            official: 80, calculated: nil, hasEffectiveChanges: false
        ).value
        #expect(GradeCalculator.semesterTotal(firstQuarter: 90, secondQuarter: second, finalExamGrade: 85) == 85)
        // An edit to Q1 must not erase the untouched Q2 component either.
        let editedFirst = WhatIfGradePresentation.resolve(
            official: 90, calculated: 95, hasEffectiveChanges: true
        ).value
        #expect(GradeCalculator.semesterTotal(firstQuarter: editedFirst, secondQuarter: second, finalExamGrade: 85) == 87)
        // Saved changes in the unavailable quarter cannot silently use its posted value.
        let unavailableEdited = WhatIfGradePresentation.resolve(
            official: 80, calculated: nil, hasEffectiveChanges: true
        )
        #expect(unavailableEdited.value == nil)
        #expect(unavailableEdited.source == .estimate)
    }

    @Test("Unavailable edited quarters cannot become a numeric single-quarter semester estimate")
    func unavailableEditedSemester() {
        let knownFirst = 90.0
        let unknownEditedSecond = WhatIfGradePresentation.resolve(
            official: 80, calculated: nil, hasEffectiveChanges: true
        ).value
        // The district calculator legitimately supports truly absent quarters.
        // Missing source data with saved edits is a different presentation state.
        let calculated = GradeCalculator.semesterTotal(
            firstQuarter: knownFirst, secondQuarter: unknownEditedSecond, finalExamGrade: 85
        )
        #expect(calculated == 90)
        let unknown = WhatIfGradePresentation.resolve(
            official: 85, calculated: calculated, hasEffectiveChanges: true,
            calculationUnavailable: true
        )
        #expect(unknown.value == nil)
        #expect(unknown.source == .estimate)
        let trulyAbsent = WhatIfGradePresentation.resolve(
            official: nil, calculated: calculated, hasEffectiveChanges: true,
            calculationUnavailable: false
        )
        #expect(trulyAbsent.value == 90)
        #expect(WhatIfGradePresentation.resolve(
            official: 85, calculated: calculated, hasEffectiveChanges: false,
            calculationUnavailable: true
        ).value == 85)
    }

    @Test("A sole unresolved quarter override is an unavailable estimate even without an exam edit")
    func soleUnavailableOverride() {
        let loadedAssignments: [CalcAssignment] = []
        let savedOverrides = ["unavailable-q2": AssignmentGradeOverride(grade: 95)]
        let knownChanges = AssignmentGradeEdits.hasEffectiveChanges(savedOverrides, to: loadedAssignments)
        #expect(!knownChanges)
        let unavailableEditedQuarter = !savedOverrides.isEmpty
        for editing in [true, false] {
            let changed = editing && (knownChanges || unavailableEditedQuarter)
            let shown = WhatIfGradePresentation.resolve(
                official: 85,
                calculated: GradeCalculator.semesterTotal(firstQuarter: 90, secondQuarter: nil, finalExamGrade: nil),
                hasEffectiveChanges: changed, calculationUnavailable: unavailableEditedQuarter
            )
            #expect(shown.value == (editing ? nil : 85))
            #expect(shown.source == (editing ? .estimate : .official))
        }
    }

}

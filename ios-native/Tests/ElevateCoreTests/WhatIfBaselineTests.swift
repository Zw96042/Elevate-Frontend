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


import Foundation
import Testing
@testable import ElevateCore

@Suite("Local edits to existing Skyward scores")
struct AssignmentOverrideTests {
    private func info(_ names: [String], earned: Double = 80) -> GradeInfoResult {
        let assignments = names.map { GradeInfoAssignment(date: "10/01/2026", name: $0, grade: Int(earned), score: earned, pointsEarned: earned, pointsTotal: 100, meta: []) }
        return GradeInfoResult(course: "Synthetic course", instructor: "Example teacher", period: 1, litName: "Quarter 1", litBegin: nil, litEnd: nil,
                               gradebook: [GradeCategory(category: "Tests", weight: 100, adjustedWeight: nil, assignments: assignments)], score: 80, grade: 80)
    }
    @Test("An edit replaces points without duplicating work or mutating the official result")
    func replacesExisting() {
        let original = info(["Quiz"])
        let real = AssignmentGradeEdits.assignments(from: original, className: original.course, term: .q1)
        let edited = AssignmentGradeEdits.applying([real[0].id: .init(grade: 95)], to: real)
        #expect(edited.count == 1)
        #expect(edited[0].grade == 95)
        #expect(!edited[0].artificial)
        #expect(edited[0].outOf == 100)
        #expect(original.gradebook[0].assignments[0].pointsEarned == 80)
        #expect(GradeCalculator.summary(assignments: edited, categoryWeights: ["Tests": 100]).courseTotal == 95)
        #expect(real[0].grade == 80)
    }
    @Test("Identity survives reorder and official grade updates; separate terms cannot share edits")
    func stableIdentity() {
        let first = AssignmentGradeEdits.assignments(from: info(["Quiz", "Exam"]), className: "Example", term: .q1)
        let reordered = AssignmentGradeEdits.assignments(from: info(["Exam", "Quiz"], earned: 85), className: "Example", term: .q1)
        #expect(first[0].id == reordered[1].id)
        #expect(first[1].id == reordered[0].id)
        let edited = AssignmentGradeEdits.applying([first[0].id: .init(grade: 100)], to: reordered)
        #expect(edited.map(\.grade) == [85, 100])
        let otherTerm = AssignmentGradeEdits.assignments(from: info(["Quiz", "Exam"]), className: "Example", term: .q2)
        #expect(Set(first.map(\.id)).isDisjoint(with: Set(otherTerm.map(\.id))))
    }
    @Test("Duplicate titles remain independently editable; nil estimates round trip")
    func duplicatesAndNil() throws {
        let real = AssignmentGradeEdits.assignments(from: info(["Quiz", "Quiz"]), className: "Example", term: .q1)
        #expect(real[0].id != real[1].id)
        let edits = [real[0].id: AssignmentGradeOverride(grade: nil)]
        let restored = try JSONDecoder().decode([String: AssignmentGradeOverride].self, from: JSONEncoder().encode(edits))
        let edited = AssignmentGradeEdits.applying(restored, to: real)
        #expect(edited[0].grade == nil)
        #expect(edited[1].grade == 80)
    }
    @Test("Invalid scores cannot affect calculation, metadata stays intact")
    func validatesScore() {
        var real = AssignmentGradeEdits.assignments(from: info(["Quiz"]), className: "Example", term: .q1)
        real[0].meta = [AssignmentMeta(type: "noCount", note: "Teacher exclusion")]
        let edited = AssignmentGradeEdits.applying([real[0].id: .init(grade: .infinity)], to: real)
        #expect(edited[0].grade == 80)
        #expect(edited[0].isNoCount)
    }
    @Test("An empty points-based quarter predicts newly added work")
    func emptyQuarterPrediction() {
        #expect(GradeCalculator.pointsTotal(assignments: []) == nil)
        let added = CalcAssignment(id: "local", className: "Example", name: "Quiz", term: "Q2",
                                   category: "Assignments", grade: 90, outOf: 100, dueDate: "", artificial: true, meta: [])
        #expect(GradeCalculator.pointsTotal(assignments: [added]) == 90)
        var excluded = added
        excluded.meta = [AssignmentMeta(type: "noCount", note: "Excluded")]
        #expect(GradeCalculator.pointsTotal(assignments: [excluded]) == nil)
    }

    @Test("No-count estimates exclude existing work while preserving its score and official metadata")
    func excludesExistingWork() throws {
        var real = AssignmentGradeEdits.assignments(from: info(["Quiz", "Exam"]), className: "Example", term: .q1)
        real[1].grade = 100
        real[0].meta = [AssignmentMeta(type: "missing", note: "Missing work")]
        let edit = AssignmentGradeOverride(grade: 80, noCount: true)
        let decoded = try JSONDecoder().decode(AssignmentGradeOverride.self, from: JSONEncoder().encode(edit))
        let edited = AssignmentGradeEdits.applying([real[0].id: decoded], to: real)
        #expect(edited[0].grade == 80)
        #expect(edited[0].isNoCount)
        #expect(edited[0].isMissing)
        #expect(!real[0].isNoCount)
        #expect(GradeCalculator.pointsTotal(assignments: edited) == 100)
        let counted = AssignmentGradeEdits.applying([real[0].id: .init(grade: 80, noCount: false)], to: edited)
        #expect(!counted[0].isNoCount)
        #expect(GradeCalculator.pointsTotal(assignments: counted) == 90)
        let legacy = try JSONDecoder().decode(AssignmentGradeOverride.self, from: Data("{\"grade\":85}".utf8))
        #expect(legacy.noCount == nil)
        #expect(AssignmentGradeEdits.applying([real[0].id: legacy], to: edited)[0].isNoCount)
        var refreshed = real
        refreshed[0].grade = 95
        let statusOnly = AssignmentGradeOverride(grade: nil, noCount: true, overridesGrade: false)
        let excludedFresh = AssignmentGradeEdits.applying([real[0].id: statusOnly], to: refreshed)
        #expect(excludedFresh[0].grade == 95)
        #expect(excludedFresh[0].isNoCount)
        let countedFresh = AssignmentGradeEdits.applying([real[0].id: .init(grade: nil, noCount: false, overridesGrade: false)], to: refreshed)
        #expect(countedFresh[0].grade == 95)
        #expect(!countedFresh[0].isNoCount)
        let nilScore = try JSONDecoder().decode(AssignmentGradeOverride.self, from: Data("{}".utf8))
        #expect(AssignmentGradeEdits.applying([real[0].id: nilScore], to: refreshed)[0].grade == nil)
    }

    @Test("Score-change presentation distinguishes exclusions and real score differences")
    func scoreChangesAreIndependent() {
        let official = AssignmentGradeEdits.assignments(from: info(["Quiz"]), className: "Example", term: .q1)[0]
        #expect(!AssignmentGradeOverride(grade: nil, noCount: true, overridesGrade: false).changesScore(of: official))
        #expect(!AssignmentGradeOverride(grade: 80, noCount: true).changesScore(of: official))
        #expect(AssignmentGradeOverride(grade: 90, noCount: true).changesScore(of: official))
        #expect(AssignmentGradeOverride(grade: nil).changesScore(of: official))
        #expect(!AssignmentGradeOverride(grade: .infinity).changesScore(of: official))
        var refreshed = official
        refreshed.grade = 90
        #expect(!AssignmentGradeOverride(grade: 90, noCount: true).changesScore(of: refreshed))
    }
}

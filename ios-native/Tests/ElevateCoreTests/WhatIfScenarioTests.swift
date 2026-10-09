import Foundation
import Testing
@testable import ElevateCore

@Suite("Named what-if scenarios")
struct WhatIfScenarioTests {
    private func book(earned: Double? = 80, posted: Double? = 80, possible: Double = 100,
                      weight: Double? = 100, category: String = "Tests") -> GradeInfoResult {
        GradeInfoResult(course: "Synthetic", instructor: "", period: nil, litName: "", litBegin: nil, litEnd: nil,
                        gradebook: [.init(category: category, weight: weight, adjustedWeight: nil,
                                          assignments: [.init(date: "2026-09-01", name: "Quiz", grade: nil,
                                                              score: nil, pointsEarned: earned, pointsTotal: possible, meta: [])])],
                        score: posted, grade: nil)
    }

    private func source(term: TermLabel = .q1, books: [String: GradeInfoResult]? = nil,
                        posted: [String: Double] = [:], official: Double? = 80, exam: Double? = nil) -> WhatIfScenarioSource {
        .init(classKey: "synthetic-course", className: "Synthetic", term: term,
              quarterGradebooks: books ?? ["Q1": book()], postedQuarterGrades: posted,
              officialGrade: official, officialExamGrade: exam)
    }

    private func id(_ book: GradeInfoResult, term: TermLabel = .q1, index: Int = 0) -> String {
        AssignmentGradeEdits.assignments(from: book, className: "Synthetic", term: term)[index].id
    }

    private func added(id: String = "local-a", term: String = "Q1", earned: Double? = 90,
                       status: WhatIfAssignmentStatus = .counted) -> WhatIfAssignment {
        .init(id: id, className: "Synthetic", name: "Hypothetical", term: term,
              category: "Tests", grade: earned, outOf: 100, dueDate: "", status: status)
    }

    @Test("Snapshots round-trip precision, explicit nil scores, and independent counting choices")
    func serialization() throws {
        let precise = 90.123456789012
        let snapshot = WhatIfScenarioSnapshot(
            assignmentsByQuarter: ["Q1": [added(earned: precise)], "Q2": [added(id: "local-b", term: "Q2", status: .noCount)]],
            overridesByQuarter: ["Q1": ["synthetic-id": .init(grade: nil, noCount: true, overridesGrade: true)],
                                 "Q2": ["synthetic-status": .init(grade: nil, noCount: false, overridesGrade: false)]],
            finalExamGrade: 103.123456789
        )
        let scenario = WhatIfScenario(name: "Exam plan", classKey: "synthetic-course", term: .sm1, snapshot: snapshot)
        let decoded = try JSONDecoder().decode(WhatIfScenario.self, from: JSONEncoder().encode(scenario))
        #expect(decoded == scenario)
        #expect(decoded.snapshot.assignmentsByQuarter["Q1"]?.first?.grade == precise)
        #expect(decoded.snapshot.overridesByQuarter["Q1"]?["synthetic-id"]?.overridesGrade == true)
        #expect(decoded.snapshot.overridesByQuarter["Q1"]?["synthetic-id"]?.grade == nil)
        #expect(decoded.snapshot.validationIssue(for: .sm1) == nil)
        #expect(snapshot.validationIssue(for: .q1) == .invalidTermOwnership)
    }

    @Test("Ownership rejects another quarter, misplaced assignment, or semester exam in a quarter")
    func termOwnership() {
        #expect(WhatIfScenarioSnapshot(assignmentsByQuarter: ["Q2": []]).validationIssue(for: .q1) == .invalidTermOwnership)
        #expect(WhatIfScenarioSnapshot(assignmentsByQuarter: ["Q1": [added(term: "Q2")]]).validationIssue(for: .q1) == .invalidTermOwnership)
        #expect(WhatIfScenarioSnapshot(finalExamGrade: 90).validationIssue(for: .q1) == .invalidTermOwnership)
        #expect(WhatIfScenarioSnapshot(overridesByQuarter: ["Q3": [:]]).validationIssue(for: .sm1) == .invalidTermOwnership)
    }

    @Test("Independent scenario comparisons preserve official baseline and do not mutate source")
    func comparisonIsolation() {
        let info = book()
        let baseline = source(books: ["Q1": info], official: 82.125)
        let first = WhatIfScenario(name: "Higher quiz", classKey: baseline.classKey, term: .q1,
                                  snapshot: .init(overridesByQuarter: ["Q1": [id(info): .init(grade: 95.123456789)]]))
        let second = WhatIfScenario(name: "Extra work", classKey: baseline.classKey, term: .q1,
                                   snapshot: .init(assignmentsByQuarter: ["Q1": [added(earned: 100)]]))
        let compared = WhatIfScenarioEvaluator.compare([first, second], source: baseline)
        #expect(compared.map(\.name) == ["Higher quiz", "Extra work"])
        #expect(compared[0].evaluation.value == 95.12)
        #expect(compared[1].evaluation.value == 90)
        #expect(compared.allSatisfy { $0.evaluation.officialValue == 82.125 })
        #expect(baseline.quarterGradebooks["Q1"] == info)
        #expect(WhatIfScenarioEvaluator.evaluate(.init(), source: baseline).value == 82.125)
        var wrongCourse = first
        wrongCourse.classKey = "another-course"
        #expect(WhatIfScenarioEvaluator.compare([wrongCourse], source: baseline)[0].evaluation.issue == .differentCourseOrTerm)
        var wrongTerm = first
        wrongTerm.term = .q2
        #expect(WhatIfScenarioEvaluator.compare([wrongTerm], source: baseline)[0].evaluation.issue == .differentCourseOrTerm)
    }

    @Test("Status-only overrides follow refreshed scores and explicit nil removes only the score")
    func statusAndNilScore() {
        var info = book()
        info.gradebook[0].assignments.append(.init(date: "", name: "Second", grade: nil, score: nil,
                                                  pointsEarned: 100, pointsTotal: 100, meta: []))
        let firstID = id(info)
        let nilScore = WhatIfScenarioSnapshot(overridesByQuarter: ["Q1": [firstID: .init(grade: nil, noCount: false, overridesGrade: true)]])
        #expect(WhatIfScenarioEvaluator.evaluate(nilScore, source: source(books: ["Q1": info])).value == 100)
        let exclude = WhatIfScenarioSnapshot(overridesByQuarter: ["Q1": [firstID: .init(grade: nil, noCount: true, overridesGrade: false)]])
        #expect(WhatIfScenarioEvaluator.evaluate(exclude, source: source(books: ["Q1": info])).value == 100)
        info.gradebook[0].assignments[0].pointsEarned = 97.987654321
        let current = AssignmentGradeEdits.assignments(from: info, className: "Synthetic", term: .q1)
        let edited = AssignmentGradeEdits.applying(exclude.overridesByQuarter["Q1"] ?? [:], to: current)
        #expect(edited[0].grade == 97.987654321)
        #expect(edited[0].isNoCount)
    }


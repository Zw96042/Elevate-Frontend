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

    @Test("Semester recalculates only changed quarters and preserves posted values in untouched quarters")
    func semesterPostedGrades() {
        let q1 = book(earned: 40, posted: 91.4999)
        let q2 = book(earned: 20, posted: 93.5)
        let baseline = source(term: .sm1, books: ["Q1": q1, "Q2": q2], official: 92.123, exam: 80)
        let snapshot = WhatIfScenarioSnapshot(overridesByQuarter: ["Q1": [id(q1): .init(grade: 92.5)]])
        let result = WhatIfScenarioEvaluator.evaluate(snapshot, source: baseline)
        #expect(result.quarterGrades["Q1"] == 92.5)
        #expect(result.quarterGrades["Q2"] == 93.5)
        #expect(result.value == GradeCalculator.semesterTotal(firstQuarter: 92.5, secondQuarter: 93.5, finalExamGrade: 80))
        #expect(result.officialValue == 92.123)
        let examOnly = WhatIfScenarioEvaluator.evaluate(.init(finalExamGrade: 100), source: baseline)
        #expect(examOnly.value == GradeCalculator.semesterTotal(firstQuarter: 91.4999, secondQuarter: 93.5, finalExamGrade: 100))
        #expect(WhatIfScenarioEvaluator.evaluate(.init(), source: baseline).value == 92.123)
    }

    @Test("Missing untouched gradebooks can use posted grades; edited missing sources fail closed")
    func missingGradebooks() {
        let q1 = book()
        let baseline = source(term: .sm1, books: ["Q1": q1], posted: ["Q2": 90], official: 85, exam: 80)
        let changed = WhatIfScenarioSnapshot(overridesByQuarter: ["Q1": [id(q1): .init(grade: 100)]])
        #expect(WhatIfScenarioEvaluator.evaluate(changed, source: baseline).value == 92)
        let missing = WhatIfScenarioSnapshot(overridesByQuarter: ["Q2": ["saved-q2": .init(grade: 95)]])
        let unavailable = WhatIfScenarioEvaluator.evaluate(missing, source: baseline)
        #expect(unavailable.value == nil)
        #expect(unavailable.issue == .unavailableGradebook(quarter: "Q2"))
        #expect(unavailable.officialValue == 85)
        #expect(unavailable.presentation.source == .estimate)
        let absent = source(term: .sm1, books: ["Q1": q1], official: nil)
        #expect(WhatIfScenarioEvaluator.evaluate(changed, source: absent).value == 100)
        let noQuarterGrades = source(term: .sm1, books: [:], official: 85)
        #expect(WhatIfScenarioEvaluator.evaluate(.init(finalExamGrade: 95), source: noQuarterGrades).issue
                == .unavailableCalculation(quarter: "SM1"))
    }

    @Test("Stale overrides and assignment collisions are visible rather than silently discarded")
    func staleAndCollidingIDs() {
        let info = book()
        let stale = WhatIfScenarioSnapshot(overridesByQuarter: ["Q1": ["gone": .init(grade: 95)]])
        #expect(WhatIfScenarioEvaluator.evaluate(stale, source: source()).issue == .staleAssignmentIDs(quarter: "Q1", count: 1))
        let collision = WhatIfScenarioSnapshot(assignmentsByQuarter: ["Q1": [added(id: id(info))]])
        #expect(WhatIfScenarioEvaluator.evaluate(collision, source: source()).issue == .assignmentIDCollision)
        let duplicate = WhatIfScenarioSnapshot(assignmentsByQuarter: ["Q1": [added(), added()]])
        #expect(duplicate.validationIssue(for: .q1) == .assignmentIDCollision)
        var twice = info
        twice.gradebook[0].assignments.append(info.gradebook[0].assignments[0])
        let ids = AssignmentGradeEdits.assignments(from: twice, className: "Synthetic", term: .q1).map(\.id)
        #expect(Set(ids).count == 2)
        let onlySecond = WhatIfScenarioSnapshot(overridesByQuarter: ["Q1": [ids[1]: .init(grade: 100)]])
        #expect(WhatIfScenarioEvaluator.evaluate(onlySecond, source: source(books: ["Q1": twice])).value == 90)
    }

    @Test("Nonfinite snapshots, invalid categories, and unavailable edited totals remain unavailable")
    func invalidInputs() {
        for number in [Double.nan, Double.infinity, -Double.infinity, 1_000_001] {
            #expect(WhatIfScenarioSnapshot(finalExamGrade: number).validationIssue(for: .sm1) == .invalidScore)
            #expect(WhatIfScenarioSnapshot(assignmentsByQuarter: ["Q1": [added(earned: number)]]).validationIssue(for: .q1) == .invalidScore)
        }
        var bad = book()
        bad.gradebook.append(bad.gradebook[0])
        let snapshot = WhatIfScenarioSnapshot(assignmentsByQuarter: ["Q1": [added()]])
        #expect(WhatIfScenarioEvaluator.evaluate(snapshot, source: source(books: ["Q1": bad])).issue == .invalidCategories)
        let info = book()
        let removed = WhatIfScenarioSnapshot(overridesByQuarter: ["Q1": [id(info): .init(grade: nil)]])
        #expect(WhatIfScenarioEvaluator.evaluate(removed, source: source()).issue == .unavailableCalculation(quarter: "Q1"))
        var wrongCategory = added()
        wrongCategory.category = "Removed category"
        #expect(WhatIfScenarioEvaluator.evaluate(.init(assignmentsByQuarter: ["Q1": [wrongCategory]]), source: source()).issue
                == .unavailableCategory(quarter: "Q1", category: "Removed category"))
    }

    @Test("Verified empty points quarters can receive hypothetical work while unavailable quarters cannot")
    func emptyQuarter() {
        var empty = book(posted: nil, weight: nil)
        empty.gradebook = []
        let addedWork = WhatIfScenarioSnapshot(assignmentsByQuarter: ["Q1": [added(earned: 104.123456789)]])
        let result = WhatIfScenarioEvaluator.evaluate(addedWork, source: source(books: ["Q1": empty], official: nil))
        #expect(result.value == GradeCalculator.pointsTotal(assignments: [WhatIfScenarioEvaluator.assignment(from: added(earned: 104.123456789))]))
        #expect(result.presentation.source == .estimate)
        #expect(WhatIfScenarioEvaluator.evaluate(addedWork, source: source(books: [:], official: nil)).issue == .unavailableGradebook(quarter: "Q1"))
    }

    @Test("Scenario library reloads, renames, and deletes without crossing account/course/term ownership")
    func libraryPersistenceAndIsolation() throws {
        let suite = "WhatIfScenarioTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let first = WhatIfScenarioLibrary(accountIdentifier: "synthetic-first", defaults: defaults,
                                          identifierGenerator: { "first-id" }, now: { fixedDate })
        let second = WhatIfScenarioLibrary(accountIdentifier: "synthetic-second", defaults: defaults,
                                           identifierGenerator: { "first-id" }, now: { fixedDate })
        let snapshot = WhatIfScenarioSnapshot(assignmentsByQuarter: ["Q1": [added()]])
        let saved = try first.save(name: "  Quiz plan  ", classKey: "course-a", term: .q1,
                                   snapshot: snapshot, expectedAccountIdentifier: "synthetic-first")
        let otherAccount = try second.save(name: "Account two", classKey: "course-a", term: .q1,
                                          snapshot: .init(), expectedAccountIdentifier: "synthetic-second")
        #expect(saved.name == "Quiz plan")
        #expect(saved.createdAt == fixedDate)
        #expect(otherAccount.id == saved.id) // Account libraries are independent.
        let reloaded = WhatIfScenarioLibrary(accountIdentifier: "synthetic-first", defaults: defaults)
        #expect(reloaded.scenarios(classKey: "course-a", term: .q1) == [saved])
        #expect(reloaded.scenarios(classKey: "course-a", term: .q2).isEmpty)
        #expect(reloaded.scenarios(classKey: "course-b", term: .q1).isEmpty)
        let renamed = try reloaded.rename(id: saved.id, name: "Revised plan", expectedAccountIdentifier: "synthetic-first")
        #expect(renamed.snapshot == snapshot)
        #expect(renamed.id == saved.id)
        #expect(renamed.createdAt == fixedDate)
        #expect(second.scenarios(classKey: "course-a", term: .q1) == [otherAccount])
        #expect(throws: WhatIfScenarioLibraryError.accountChanged) {
            try reloaded.rename(id: saved.id, name: "Wrong account", expectedAccountIdentifier: "synthetic-second")
        }
        #expect(throws: WhatIfScenarioLibraryError.accountChanged) {
            try reloaded.delete(id: saved.id, expectedAccountIdentifier: "synthetic-second")
        }
        #expect(throws: WhatIfScenarioLibraryError.accountChanged) {
            try reloaded.save(name: "Wrong account", classKey: "course-a", term: .q1,
                              snapshot: .init(), expectedAccountIdentifier: "synthetic-second")
        }
        #expect(reloaded.scenarios(classKey: "course-a", term: .q1) == [renamed])
        try reloaded.delete(id: saved.id, expectedAccountIdentifier: "synthetic-first")
        #expect(reloaded.scenarios(classKey: "course-a", term: .q1).isEmpty)
        #expect(second.scenarios(classKey: "course-a", term: .q1) == [otherAccount])
        #expect(throws: WhatIfScenarioLibraryError.scenarioNotFound) {
            try reloaded.delete(id: saved.id, expectedAccountIdentifier: "synthetic-first")
        }
    }

    @Test("Unreadable scenario storage survives reads and every mutation until explicit scoped recovery")
    func corruptLibraryRecovery() throws {
        let suite = "WhatIfScenarioTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "account.synthetic-first.namedWhatIfScenarios"
        let corrupt = Data("unreadable synthetic data".utf8)
        defaults.set(corrupt, forKey: key)
        defaults.set(Data("unrelated".utf8), forKey: "account.synthetic-second.namedWhatIfScenarios")
        let library = WhatIfScenarioLibrary(accountIdentifier: "synthetic-first", defaults: defaults)
        #expect(library.hasUnreadableScenarios)
        #expect(library.scenarios(classKey: "course", term: .q1).isEmpty)
        #expect(throws: WhatIfScenarioLibraryError.corruptStorage) {
            try library.save(name: "Plan", classKey: "course", term: .q1, snapshot: .init(), expectedAccountIdentifier: "synthetic-first")
        }
        #expect(throws: WhatIfScenarioLibraryError.corruptStorage) {
            try library.rename(id: "unknown", name: "Plan", expectedAccountIdentifier: "synthetic-first")
        }
        #expect(throws: WhatIfScenarioLibraryError.corruptStorage) {
            try library.delete(id: "unknown", expectedAccountIdentifier: "synthetic-first")
        }
        #expect(defaults.data(forKey: key) == corrupt)
        #expect(throws: WhatIfScenarioLibraryError.accountChanged) {
            try library.clearUnreadableScenarios(expectedAccountIdentifier: "synthetic-second")
        }
        #expect(defaults.data(forKey: key) == corrupt)
        try library.clearUnreadableScenarios(expectedAccountIdentifier: "synthetic-first")
        #expect(!library.hasUnreadableScenarios)
        #expect(defaults.data(forKey: key) == nil)
        #expect(defaults.data(forKey: "account.synthetic-second.namedWhatIfScenarios") == Data("unrelated".utf8))
        let saved = try library.save(name: "Recovered", classKey: "course", term: .q1, snapshot: .init(), expectedAccountIdentifier: "synthetic-first")
        try library.clearUnreadableScenarios(expectedAccountIdentifier: "synthetic-first")
        #expect(library.scenarios(classKey: "course", term: .q1) == [saved])
    }

    @Test("Scenario limits, invalid names, bad snapshots, and generated ID collisions preserve prior saves")
    func libraryBoundsAndValidation() throws {
        let suite = "WhatIfScenarioTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = WhatIfScenarioLibrary(accountIdentifier: "synthetic", defaults: defaults,
                                            identifierGenerator: { "fixed-id" })
        let saved = try library.save(name: "Plan", classKey: "course", term: .q1, snapshot: .init(), expectedAccountIdentifier: "synthetic")
        #expect(throws: WhatIfScenarioLibraryError.identifierCollision) {
            try library.save(name: "Plan two", classKey: "course", term: .q1, snapshot: .init(), expectedAccountIdentifier: "synthetic")
        }
        for name in ["  \n", String(repeating: "x", count: 101)] {
            #expect(throws: WhatIfScenarioLibraryError.invalidName) {
                try library.rename(id: saved.id, name: name, expectedAccountIdentifier: "synthetic")
            }
        }
        #expect(throws: WhatIfScenarioLibraryError.invalidSnapshot(.invalidTermOwnership)) {
            try library.save(name: "Wrong quarter", classKey: "course", term: .q1,
                             snapshot: .init(finalExamGrade: 90), expectedAccountIdentifier: "synthetic")
        }
        #expect(library.scenarios(classKey: "course", term: .q1) == [saved])
        let key = "account.synthetic.namedWhatIfScenarios"
        let fifty = (0..<50).map { index in
            WhatIfScenario(id: "id-\(index)", name: "Plan", classKey: "course", term: index.isMultiple(of: 2) ? .q1 : .q2, snapshot: .init())
        }
        defaults.set(try JSONEncoder().encode(fifty), forKey: key)
        #expect(!library.hasUnreadableScenarios)
        #expect(throws: WhatIfScenarioLibraryError.limitReached) {
            try library.save(name: "Over course limit", classKey: "course", term: .sm1, snapshot: .init(), expectedAccountIdentifier: "synthetic")
        }
        let fiveHundred = (0..<500).map { index in
            WhatIfScenario(id: "id-\(index)", name: "Plan", classKey: "course-\(index / 50)", term: .q1, snapshot: .init())
        }
        defaults.set(try JSONEncoder().encode(fiveHundred), forKey: key)
        #expect(!library.hasUnreadableScenarios)
        #expect(throws: WhatIfScenarioLibraryError.limitReached) {
            try library.save(name: "Over total limit", classKey: "new-course", term: .q1, snapshot: .init(), expectedAccountIdentifier: "synthetic")
        }
        var duplicateIDs = fifty
        duplicateIDs[1].id = duplicateIDs[0].id
        defaults.set(try JSONEncoder().encode(duplicateIDs), forKey: key)
        #expect(library.hasUnreadableScenarios)
    }

    @Test("One oversized nested snapshot cannot overwrite valid saves or bypass the read boundary")
    func libraryPayloadBoundary() throws {
        let suite = "WhatIfScenarioTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "account.synthetic.namedWhatIfScenarios"
        let library = WhatIfScenarioLibrary(accountIdentifier: "synthetic", defaults: defaults)
        let saved = try library.save(name: "Preserved", classKey: "course", term: .q1, snapshot: .init(), expectedAccountIdentifier: "synthetic")
        let originalBytes = try #require(defaults.data(forKey: key))
        var largeAssignment = added()
        largeAssignment.name = String(repeating: "x", count: 8 * 1024 * 1024)
        let oversizedSnapshot = WhatIfScenarioSnapshot(assignmentsByQuarter: ["Q1": [largeAssignment]])
        #expect(throws: WhatIfScenarioLibraryError.limitReached) {
            try library.save(name: "Too large", classKey: "course", term: .q1,
                             snapshot: oversizedSnapshot, expectedAccountIdentifier: "synthetic")
        }
        #expect(defaults.data(forKey: key) == originalBytes)
        #expect(library.scenarios(classKey: "course", term: .q1) == [saved])
        #expect(!library.hasUnreadableScenarios)
        let oversizedRecord = WhatIfScenario(name: "Too large", classKey: "course", term: .q1, snapshot: oversizedSnapshot)
        let oversizedBytes = try JSONEncoder().encode([oversizedRecord])
        defaults.set(oversizedBytes, forKey: key)
        #expect(library.hasUnreadableScenarios)
        #expect(library.scenarios(classKey: "course", term: .q1).isEmpty)
        #expect(throws: WhatIfScenarioLibraryError.corruptStorage) {
            try library.save(name: "Must not overwrite", classKey: "course", term: .q1,
                             snapshot: .init(), expectedAccountIdentifier: "synthetic")
        }
        #expect(defaults.data(forKey: key) == oversizedBytes)
    }


import Foundation

/// Only local edits are captured. Official assignments and posted grades remain
/// live source data; loading a scenario never replaces a Skyward gradebook.
struct WhatIfScenarioSnapshot: Codable, Hashable {
    var assignmentsByQuarter: [String: [WhatIfAssignment]] = [:]
    var overridesByQuarter: [String: [String: AssignmentGradeOverride]] = [:]
    /// Nil inherits the official exam. Quarter scenarios never own an exam.
    var finalExamGrade: Double? = nil

    func validationIssue(for term: TermLabel) -> WhatIfScenarioIssue? {
        let owned = Set(term.whatIfQuarterTerms.map(\.shortName))
        guard Set(assignmentsByQuarter.keys).isSubset(of: owned),
              Set(overridesByQuarter.keys).isSubset(of: owned),
              term.isSemester || finalExamGrade == nil else { return .invalidTermOwnership }
        guard finalExamGrade.map(WhatIfScenarioEvaluator.validNumber) ?? true else { return .invalidScore }
        var ids = Set<String>()
        for (quarter, assignments) in assignmentsByQuarter {
            for assignment in assignments {
                guard assignment.term == quarter else { return .invalidTermOwnership }
                guard !assignment.id.isEmpty, ids.insert(assignment.id).inserted else { return .assignmentIDCollision }
                guard WhatIfScenarioEvaluator.validNumber(assignment.outOf), assignment.outOf >= 0,
                      assignment.grade.map(WhatIfScenarioEvaluator.validNumber) ?? true else { return .invalidScore }
            }
        }
        for overrides in overridesByQuarter.values {
            for (id, override) in overrides {
                guard !id.isEmpty else { return .assignmentIDCollision }
                guard override.grade.map(WhatIfScenarioEvaluator.validNumber) ?? true else { return .invalidScore }
            }
        }
        return nil
    }
}

/// Account ownership is enforced by the account-scoped store. Course and term
/// ownership travel with the snapshot so a load can validate both before writing.
struct WhatIfScenario: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var classKey: String
    var term: TermLabel
    var createdAt: Date = Date()
    var snapshot: WhatIfScenarioSnapshot
}

enum WhatIfScenarioLibraryError: Error, Equatable {
    case accountChanged
    case corruptStorage
    case invalidName
    case invalidSnapshot(WhatIfScenarioIssue)
    case scenarioNotFound
    case limitReached
    case identifierCollision
}

/// All mutations read the current library before writing, preserve unrelated
/// courses/terms, and refuse to replace unreadable data. The caller supplies its
/// current account identity at mutation time, rather than trusting a sheet's
/// previously captured account context.
struct WhatIfScenarioLibrary {
    private static let maximumEncodedBytes = 8 * 1024 * 1024
    private let accountIdentifier: String
    private let defaults: UserDefaults
    private let identifierGenerator: () -> String
    private let now: () -> Date

    init(accountIdentifier: String, defaults: UserDefaults,
         identifierGenerator: @escaping () -> String = { UUID().uuidString },
         now: @escaping () -> Date = { Date() }) {
        self.accountIdentifier = accountIdentifier
        self.defaults = defaults
        self.identifierGenerator = identifierGenerator
        self.now = now
    }

    var hasUnreadableScenarios: Bool {
        do { _ = try readAll(); return false }
        catch { return true }
    }

    func scenarios(classKey: String, term: TermLabel) -> [WhatIfScenario] {
        guard let all = try? readAll() else { return [] }
        return all.filter { $0.classKey == classKey && $0.term == term }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func save(name: String, classKey: String, term: TermLabel, snapshot: WhatIfScenarioSnapshot,
              expectedAccountIdentifier: String) throws -> WhatIfScenario {
        try requireAccount(expectedAccountIdentifier)
        let name = try validatedName(name)
        guard !classKey.isEmpty else { throw WhatIfScenarioLibraryError.invalidSnapshot(.differentCourseOrTerm) }
        if let issue = snapshot.validationIssue(for: term) { throw WhatIfScenarioLibraryError.invalidSnapshot(issue) }
        var all = try readAll()
        guard all.count < 500, all.filter({ $0.classKey == classKey }).count < 50 else {
            throw WhatIfScenarioLibraryError.limitReached
        }
        let id = identifierGenerator()
        guard !id.isEmpty, !all.contains(where: { $0.id == id }) else { throw WhatIfScenarioLibraryError.identifierCollision }
        let createdAt = now()
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw WhatIfScenarioLibraryError.invalidSnapshot(.invalidScore)
        }
        let scenario = WhatIfScenario(id: id, name: name, classKey: classKey, term: term, createdAt: createdAt, snapshot: snapshot)
        all.append(scenario)
        try write(all)
        return scenario
    }

    @discardableResult
    func rename(id: String, name: String, expectedAccountIdentifier: String) throws -> WhatIfScenario {
        try requireAccount(expectedAccountIdentifier)
        let name = try validatedName(name)
        var all = try readAll()
        guard let index = all.firstIndex(where: { $0.id == id }) else { throw WhatIfScenarioLibraryError.scenarioNotFound }
        all[index].name = name
        try write(all)
        return all[index]
    }

    func delete(id: String, expectedAccountIdentifier: String) throws {
        try requireAccount(expectedAccountIdentifier)
        var all = try readAll()
        guard let index = all.firstIndex(where: { $0.id == id }) else { throw WhatIfScenarioLibraryError.scenarioNotFound }
        all.remove(at: index)
        try write(all)
    }

    /// Explicit recovery removes only unreadable scenario storage for this
    /// account. Valid saved scenarios and all active what-if edits stay intact.
    func clearUnreadableScenarios(expectedAccountIdentifier: String) throws {
        try requireAccount(expectedAccountIdentifier)
        guard hasUnreadableScenarios else { return }
        defaults.removeObject(forKey: storageKey)
    }

    private var storageKey: String { "account.\(accountIdentifier).namedWhatIfScenarios" }

    private func requireAccount(_ expected: String) throws {
        guard !accountIdentifier.isEmpty, expected == accountIdentifier else { throw WhatIfScenarioLibraryError.accountChanged }
    }

    private func validatedName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { throw WhatIfScenarioLibraryError.invalidName }
        return name
    }

    private func readAll() throws -> [WhatIfScenario] {
        guard defaults.object(forKey: storageKey) != nil else { return [] }
        guard let data = defaults.data(forKey: storageKey),
              data.count <= Self.maximumEncodedBytes,
              let all = try? JSONDecoder().decode([WhatIfScenario].self, from: data),
              all.count <= 500, Set(all.map(\.id)).count == all.count else {
            throw WhatIfScenarioLibraryError.corruptStorage
        }
        var courseCounts: [String: Int] = [:]
        for scenario in all {
            courseCounts[scenario.classKey, default: 0] += 1
            guard !scenario.id.isEmpty, !scenario.classKey.isEmpty,
                  scenario.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  (try? validatedName(scenario.name)) == scenario.name,
                  scenario.snapshot.validationIssue(for: scenario.term) == nil,
                  courseCounts[scenario.classKey, default: 0] <= 50 else {
                throw WhatIfScenarioLibraryError.corruptStorage
            }
        }
        return all
    }

    private func write(_ all: [WhatIfScenario]) throws {
        let data = try JSONEncoder().encode(all)
        guard data.count <= Self.maximumEncodedBytes else { throw WhatIfScenarioLibraryError.limitReached }
        defaults.set(data, forKey: storageKey)
    }
}

enum WhatIfScenarioIssue: Equatable {
    case invalidTermOwnership
    case differentCourseOrTerm
    case invalidScore
    case invalidCategories
    case assignmentIDCollision
    case staleAssignmentIDs(quarter: String, count: Int)
    case unavailableGradebook(quarter: String)
    case unavailableCategory(quarter: String, category: String)
    case unavailableCalculation(quarter: String)
}

/// A missing dictionary entry means source unavailable, while a present empty
/// gradebook is a verified empty quarter. Posted quarter values survive either
/// state until an effective edit actually requires recalculation.
struct WhatIfScenarioSource {
    var classKey: String
    var className: String
    var term: TermLabel
    var quarterGradebooks: [String: GradeInfoResult]
    var postedQuarterGrades: [String: Double] = [:]
    var officialGrade: Double? = nil
    var officialExamGrade: Double? = nil
}

struct WhatIfScenarioEvaluation: Equatable {
    var officialValue: Double?
    var presentation: WhatIfGradePresentation
    var quarterGrades: [String: Double]
    var issue: WhatIfScenarioIssue?

    var value: Double? { presentation.value }
    var difference: Double? {
        guard let value, let officialValue else { return nil }
        return value - officialValue
    }
}

struct WhatIfScenarioComparison: Identifiable {
    var id: String
    var name: String
    var evaluation: WhatIfScenarioEvaluation
}

enum WhatIfScenarioEvaluator {
    static func compare(_ scenarios: [WhatIfScenario], source: WhatIfScenarioSource) -> [WhatIfScenarioComparison] {
        scenarios.map { scenario in
            let result: WhatIfScenarioEvaluation
            if scenario.classKey != source.classKey || scenario.term != source.term {
                result = unavailable(.differentCourseOrTerm, official: source.officialGrade)
            } else {
                result = evaluate(scenario.snapshot, source: source)
            }
            return WhatIfScenarioComparison(id: scenario.id, name: scenario.name, evaluation: result)
        }
    }

    static func evaluate(_ snapshot: WhatIfScenarioSnapshot, source: WhatIfScenarioSource) -> WhatIfScenarioEvaluation {
        if let issue = snapshot.validationIssue(for: source.term) {
            return unavailable(issue, official: source.officialGrade)
        }
        guard source.officialGrade.map(validNumber) ?? true,
              source.officialExamGrade.map(validNumber) ?? true,
              source.postedQuarterGrades.values.allSatisfy(validNumber) else {
            return unavailable(.invalidScore, official: nil)
        }
        var baseline: [String: Double] = [:]
        var estimated: [String: Double] = [:]
        var changed = false
        var failure: WhatIfScenarioIssue?
        for quarter in source.term.whatIfQuarterTerms {
            let original = quarterValue(quarter, snapshot: .init(), source: source)
            let result = quarterValue(quarter, snapshot: snapshot, source: source)
            baseline[quarter.shortName] = original.value
            estimated[quarter.shortName] = result.value
            changed = changed || result.changed
            failure = failure ?? result.issue
        }
        if source.term.isSemester, let exam = snapshot.finalExamGrade,
           exam != source.officialExamGrade { changed = true }
        let official = source.officialGrade ?? selectedValue(baseline, exam: source.officialExamGrade, term: source.term)
        if let failure { return unavailable(failure, official: official, quarters: estimated) }
        let calculated = selectedValue(estimated, exam: snapshot.finalExamGrade ?? source.officialExamGrade, term: source.term)
        if changed, calculated == nil {
            return unavailable(.unavailableCalculation(quarter: source.term.shortName), official: official, quarters: estimated)
        }
        return WhatIfScenarioEvaluation(
            officialValue: official,
            presentation: .resolve(official: official, calculated: calculated, hasEffectiveChanges: changed),
            quarterGrades: estimated, issue: nil
        )
    }

    static func assignment(from assignment: WhatIfAssignment) -> CalcAssignment {
        let meta: [AssignmentMeta]
        switch assignment.resolvedStatus {
        case .counted: meta = []
        case .noCount: meta = [.init(type: "noCount", note: "Excluded from estimate")]
        case .missing: meta = [.init(type: "missing", note: "Missing")]
        case .absent: meta = [.init(type: "absent", note: "Absent")]
        }
        return CalcAssignment(id: assignment.id, className: assignment.className, name: assignment.name,
                              term: assignment.term, category: assignment.category, grade: assignment.grade,
                              outOf: assignment.outOf, dueDate: assignment.dueDate, artificial: true, meta: meta)
    }

    static func validNumber(_ value: Double) -> Bool { value.isFinite && abs(value) <= 1_000_000 }

    private struct QuarterResult {
        var value: Double?
        var changed: Bool = false
        var issue: WhatIfScenarioIssue? = nil
    }


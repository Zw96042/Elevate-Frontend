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


import Foundation

/// Persistence for hypothetical ("what-if") assignments, final-exam estimates,
/// the per-class "Show Calculated" toggle, and manual GPA classes.
enum WhatIfStore {
    private static let assignmentsKey = "artificialAssignments"
    private static let finalExamKey = "finalExamGrades"

    private static var currentScope: String {
        CredentialStore.currentAccountIdentifier ?? "sample"
    }

    private static func scopedKey(_ key: String, scope: String? = nil) -> String {
        "account.\(scope ?? currentScope).\(key)"
    }

    private static func storedData(for key: String) -> Data? {
        let defaults = UserDefaults.standard
        let scoped = scopedKey(key)
        if let data = defaults.data(forKey: scoped) { return data }

        // One-time migration from versions that did not namespace local data.
        guard let legacy = defaults.data(forKey: key) else { return nil }
        defaults.set(legacy, forKey: scoped)
        defaults.removeObject(forKey: key)
        return legacy
    }

    private static func preserveCorruptData(_ data: Data, for key: String) {
        let recoveryKey = scopedKey(key) + ".recovery"
        if UserDefaults.standard.data(forKey: recoveryKey) == nil {
            UserDefaults.standard.set(data, forKey: recoveryKey)
        }
    }

    // MARK: Keys

    static func classKey(
        studentID: String,
        className: String,
        corNumId: String,
        section: String,
        gbId: String
    ) -> String {
        "\(studentID)|\(className)_\(corNumId)_\(section)_\(gbId)"
    }

    // MARK: Artificial assignments, keyed by "<classKey>_<term>"

    private static func loadAllAssignments() -> [String: [WhatIfAssignment]] {
        guard let data = storedData(for: assignmentsKey) else {
            return [:]
        }
        do {
            let decoded = try JSONDecoder().decode([String: [WhatIfAssignment]].self, from: data)
            let migration = migrateLegacySemesterAssignments(decoded)
            if migration.didChange {
                saveAllAssignments(migration.assignments)
            }
            return migration.assignments
        } catch {
            preserveCorruptData(data, for: assignmentsKey)
            return [:]
        }
    }

    /// Older builds saved assignments created from a semester screen under an
    /// SM1/SM2 key. Those buckets do not identify which 40% quarter component
    /// should change, so migrate them once to the semester's second quarter.
    /// New UI requires an explicit quarter choice and never writes SM keys.
    private static func migrateLegacySemesterAssignments(
        _ assignments: [String: [WhatIfAssignment]]
    ) -> (assignments: [String: [WhatIfAssignment]], didChange: Bool) {
        var migrated = assignments
        var didChange = false

        for semester in [TermLabel.sm1, .sm2] {
            guard let quarter = semester.legacyWhatIfQuarter else { continue }
            let legacySuffix = "_\(semester.shortName)"
            for key in migrated.keys.filter({ $0.hasSuffix(legacySuffix) }) {
                let targetKey = String(key.dropLast(legacySuffix.count)) + "_\(quarter.shortName)"
                var target = migrated[targetKey] ?? []
                for var assignment in migrated[key] ?? [] {
                    assignment.term = quarter.shortName
                    if !target.contains(where: { $0.id == assignment.id }) {
                        target.append(assignment)
                    }
                }
                migrated[targetKey] = target
                migrated.removeValue(forKey: key)
                didChange = true
            }
        }
        return (migrated, didChange)
    }

    private static func saveAllAssignments(_ all: [String: [WhatIfAssignment]]) {
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: scopedKey(assignmentsKey))
        }
    }

    /// Terms whose stored assignments are relevant when viewing `term`
    /// (a semester view includes both of its quarters).
    static func relevantTerms(for term: TermLabel) -> [String] {
        term.whatIfQuarterTerms.map(\.shortName)
    }

    static func assignments(classKey: String, term: TermLabel) -> [WhatIfAssignment] {
        let all = loadAllAssignments()
        return relevantTerms(for: term).flatMap { all["\(classKey)_\($0)"] ?? [] }
    }

    static func add(_ assignment: WhatIfAssignment, classKey: String) {
        var all = loadAllAssignments()
        all["\(classKey)_\(assignment.term)", default: []].append(assignment)
        saveAllAssignments(all)
    }

    static func update(_ assignment: WhatIfAssignment, classKey: String) {
        var all = loadAllAssignments()
        let key = "\(classKey)_\(assignment.term)"
        var list = all[key] ?? []
        if let index = list.firstIndex(where: { $0.id == assignment.id }) {
            list[index] = assignment
            all[key] = list
            saveAllAssignments(all)
        }
    }

    static func remove(id: String, classKey: String, term: TermLabel) {
        var all = loadAllAssignments()
        for t in relevantTerms(for: term) {
            let key = "\(classKey)_\(t)"
            if var list = all[key] {
                list.removeAll { $0.id == id }
                all[key] = list
            }
        }
        saveAllAssignments(all)
    }

    static func reset(classKey: String, term: TermLabel) {
        var all = loadAllAssignments()
        for t in relevantTerms(for: term) {
            all.removeValue(forKey: "\(classKey)_\(t)")
        }
        // Defensive cleanup for a legacy value if migration could not persist.
        if term.isSemester {
            all.removeValue(forKey: "\(classKey)_\(term.shortName)")
        }
        saveAllAssignments(all)
        switch term {
        case .sm1: clearFinalExamGrade("EX1", classKey: classKey)
        case .sm2: clearFinalExamGrade("EX2", classKey: classKey)
        default: break
        }
    }

    // MARK: Final-exam estimates ("EX1"/"EX2" per class)

    static func finalExamGrades(classKey: String) -> [String: Double] {
        guard let data = storedData(for: finalExamKey) else {
            return [:]
        }
        guard let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data) else {
            preserveCorruptData(data, for: finalExamKey)
            return [:]
        }
        return decoded[classKey] ?? [:]
    }

    static func setFinalExamGrade(_ grade: Double?, examType: String, classKey: String) {
        if let grade, !grade.isFinite || abs(grade) > 1_000_000 { return }
        var decoded: [String: [String: Double]] = [:]
        if let data = storedData(for: finalExamKey),
           let existing = try? JSONDecoder().decode([String: [String: Double]].self, from: data) {
            decoded = existing
        }
        var perClass = decoded[classKey] ?? [:]
        if let grade {
            perClass[examType] = grade
        } else {
            perClass.removeValue(forKey: examType)
        }
        decoded[classKey] = perClass
        if let data = try? JSONEncoder().encode(decoded) {
            UserDefaults.standard.set(data, forKey: scopedKey(finalExamKey))
        }
    }

    static func clearFinalExamGrades(classKey: String) {
        guard let data = storedData(for: finalExamKey),
              var decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data) else {
            return
        }
        decoded.removeValue(forKey: classKey)
        if let encoded = try? JSONEncoder().encode(decoded) {
            UserDefaults.standard.set(encoded, forKey: scopedKey(finalExamKey))
        }
    }

    private static func clearFinalExamGrade(_ examType: String, classKey: String) {
        guard let data = storedData(for: finalExamKey),
              var decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data) else {
            return
        }
        var perClass = decoded[classKey] ?? [:]
        perClass.removeValue(forKey: examType)
        if perClass.isEmpty {
            decoded.removeValue(forKey: classKey)
        } else {
            decoded[classKey] = perClass
        }
        if let encoded = try? JSONEncoder().encode(decoded) {
            UserDefaults.standard.set(encoded, forKey: scopedKey(finalExamKey))
        }
    }

    // MARK: Show-calculated toggle

    static func showCalculated(classKey: String) -> Bool {
        let defaults = UserDefaults.standard
        let baseKey = "showCalculated_\(classKey)"
        let key = scopedKey(baseKey)
        if defaults.object(forKey: key) != nil { return defaults.bool(forKey: key) }
        if defaults.object(forKey: baseKey) != nil {
            let value = defaults.bool(forKey: baseKey)
            defaults.set(value, forKey: key)
            defaults.removeObject(forKey: baseKey)
            return value
        }
        return false
    }

    static func setShowCalculated(_ value: Bool, classKey: String) {
        UserDefaults.standard.set(value, forKey: scopedKey("showCalculated_\(classKey)"))
    }

    // MARK: Manual GPA classes

    static func manualClasses(gradeLevel: GradeLevel) -> [ManualClass] {
        let storageKey = "savedClasses-\(gradeLevel.rawValue)"
        guard let data = storedData(for: storageKey),
              let decoded = try? JSONDecoder().decode([ManualClass].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveManualClasses(_ classes: [ManualClass], gradeLevel: GradeLevel) {
        if let data = try? JSONEncoder().encode(classes) {
            UserDefaults.standard.set(data, forKey: scopedKey("savedClasses-\(gradeLevel.rawValue)"))
        }
    }

    static func clearAccountData(scope: String?) {
        let defaults = UserDefaults.standard
        if let scope {
            let prefix = "account.\(scope)."
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                defaults.removeObject(forKey: key)
            }
        }

        // Also remove values left by pre-namespacing releases.
        defaults.removeObject(forKey: assignmentsKey)
        defaults.removeObject(forKey: finalExamKey)
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("showCalculated_") || key.hasPrefix("savedClasses-") {
            defaults.removeObject(forKey: key)
        }
    }
}

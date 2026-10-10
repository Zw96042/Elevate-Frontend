import Foundation

/// A local estimate for a real assignment. A nil score means deliberately
/// ungraded; absence of the record means use the official Skyward score.
struct AssignmentGradeOverride: Codable, Hashable {
    var grade: Double?
    var noCount: Bool? = nil
    /// Missing in legacy records, which always represented explicit scores,
    /// including an intentionally empty score. Status-only edits follow Skyward.
    var overridesGrade: Bool? = nil

    func changesScore(of official: CalcAssignment) -> Bool {
        guard overridesGrade != false else { return false }
        if let grade, !grade.isFinite || abs(grade) > 1_000_000 { return false }
        return grade != official.grade
    }
}

enum AssignmentGradeEdits {
    /// Saved records may already match refreshed Skyward values. Compare the
    /// applied score and counting choice, not persistence or metadata wording.
    static func hasEffectiveChanges(
        _ overrides: [String: AssignmentGradeOverride],
        to assignments: [CalcAssignment]
    ) -> Bool {
        zip(assignments, applying(overrides, to: assignments)).contains { original, edited in
            original.grade != edited.grade || original.isNoCount != edited.isNoCount
        }
    }

    /// Identity excludes the score and row position so refreshing official
    /// grades or reordering the gradebook does not move a local edit.
    /// Identical assignments use an occurrence suffix to remain independent.
    static func assignments(from info: GradeInfoResult, className: String, term: TermLabel) -> [CalcAssignment] {
        var occurrences: [String: Int] = [:]
        return info.gradebook.flatMap { category in
            category.assignments.map { assignment in
                let possible = assignment.pointsTotal ?? 100
                let parts = [term.shortName, category.category, assignment.name, assignment.date, String(possible)]
                let identity = parts.map { "\($0.utf8.count):\($0)" }.joined()
                let occurrence = occurrences[identity, default: 0]
                occurrences[identity] = occurrence + 1
                return CalcAssignment(
                    id: "skyward:\(identity):\(occurrence)", className: className,
                    name: assignment.name, term: term.shortName, category: category.category,
                    grade: assignment.pointsEarned, outOf: possible, dueDate: assignment.date,
                    artificial: false, meta: assignment.meta
                )
            }
        }
    }

    static func applying(_ overrides: [String: AssignmentGradeOverride], to assignments: [CalcAssignment]) -> [CalcAssignment] {
        assignments.map { assignment in
            guard let override = overrides[assignment.id] else { return assignment }
            if override.overridesGrade != false, let grade = override.grade, !grade.isFinite || abs(grade) > 1_000_000 {
                return assignment
            }
            var edited = assignment
            if override.overridesGrade != false { edited.grade = override.grade }
            if let noCount = override.noCount {
                edited.meta.removeAll { $0.type == "noCount" }
                if noCount {
                    edited.meta.append(AssignmentMeta(type: "noCount", note: "Excluded from estimate"))
                }
            }
            return edited
        }
    }
}

/// Choosing a displayed grade is separate from enabling the what-if editor.
/// An unavailable edited result must not silently become the official grade.
struct WhatIfGradePresentation: Equatable {
    enum Source: Equatable { case official, calculated, estimate }

    var value: Double?
    var source: Source

    static func resolve(
        official: Double?,
        calculated: Double?,
        hasEffectiveChanges: Bool,
        calculationUnavailable: Bool = false
    ) -> Self {
        if hasEffectiveChanges {
            return Self(value: calculationUnavailable ? nil : calculated, source: .estimate)
        }
        if let official { return Self(value: official, source: .official) }
        return Self(value: calculated, source: .calculated)
    }
}

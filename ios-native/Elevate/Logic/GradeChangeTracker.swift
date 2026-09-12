import Foundation

/// Tracks grades actually presented to the student, never network arrivals.
/// A session compares against its initial saved values (or its first finite
/// observation) while saving each viewed value for the next session.
struct GradeChangeTracker {
    private struct SeenGrade: Codable, Equatable {
        var score: Double?
    }

    private typealias Grades = [String: [String: SeenGrade]]
    private let defaults: UserDefaults
    private let storageKey: String
    private var lastSeen: Grades
    private var baseline: Grades

    init(scope: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storageKey = "account.\(scope).lastViewedCourseGrades.v1"
        let saved = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(Grades.self, from: $0) } ?? [:]
        lastSeen = saved
        baseline = saved
    }

    /// Call only for courses whose grades are being displayed in this term.
    /// Missing/nonfinite scores clear the numeric comparison, including when a
    /// grade disappears and reappears within the same session.
    mutating func observe(_ scores: [String: Double?], term: TermLabel) -> [String: Double] {
        let termKey = term.shortName
        var deltas: [String: Double] = [:]
        let previous = lastSeen
        for (courseID, score) in scores {
            let finiteScore = score.flatMap { $0.isFinite ? $0 : nil }
            if let finiteScore, let old = baseline[termKey]?[courseID]?.score {
                let delta = finiteScore - old
                if delta.isFinite, delta != 0 { deltas[courseID] = delta }
            } else {
                // First observations and reappearances are silent, then become
                // this session's baseline for subsequent visible changes.
                baseline[termKey, default: [:]][courseID] = SeenGrade(score: finiteScore)
            }
            lastSeen[termKey, default: [:]][courseID] = SeenGrade(score: finiteScore)
        }
        if lastSeen != previous, let data = try? JSONEncoder().encode(lastSeen) {
            defaults.set(data, forKey: storageKey)
        }
        return deltas
    }

    /// Official current bucket, then historical posted value. No what-if data.
    static func officialScore(for course: UnifiedCourseData, term: TermLabel) -> Double? {
        let bucket: String
        switch term {
        case .q1: bucket = "Q1"; case .q2: bucket = "Q2"; case .sm1: bucket = "S1"
        case .q3: bucket = "Q3"; case .q4: bucket = "Q4"; case .sm2: bucket = "S2"
        }
        let score = course.currentScores.first { $0.bucket == bucket }?.score
            ?? AcademicScoreValue.finiteDouble(course.historicalGrades[term.historicalKey])
        return score.flatMap { $0.isFinite ? $0 : nil }
    }
}

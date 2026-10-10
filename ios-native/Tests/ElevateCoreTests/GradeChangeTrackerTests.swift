import Foundation
import Testing
@testable import ElevateCore

@Suite("Last viewed official grades")
struct GradeChangeTrackerTests {
    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let suite = "GradeChangeTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        test(defaults)
    }

    @Test("Relaunch compares with last viewed score and session refreshes retain the delta")
    func persistedSessions() {
        withDefaults { defaults in
            var first = GradeChangeTracker(scope: "a", defaults: defaults)
            #expect(first.observe(["course": 95], term: .q1).isEmpty)
            var reopened = GradeChangeTracker(scope: "a", defaults: defaults)
            #expect(reopened.observe(["course": 96], term: .q1)["course"] == 1)
            #expect(reopened.observe(["course": 96], term: .q1)["course"] == 1)
            #expect(reopened.observe(["course": 97], term: .q1)["course"] == 2)
            var nextSession = GradeChangeTracker(scope: "a", defaults: defaults)
            #expect(nextSession.observe(["course": 97], term: .q1).isEmpty)
            #expect(nextSession.observe(["course": 96.75], term: .q1)["course"] == -0.25)
        }
    }

    @Test("Unobserved fetches and terms do not advance saved baselines")
    func unseenData() {
        withDefaults { defaults in
            var first = GradeChangeTracker(scope: "a", defaults: defaults)
            _ = first.observe(["course": 95], term: .q1)
            // A hidden fetch has no observe call. Even constructing a tracker
            // while hidden must not rewrite any persisted score.
            _ = GradeChangeTracker(scope: "a", defaults: defaults)
            var later = GradeChangeTracker(scope: "a", defaults: defaults)
            _ = later.observe(["course": 84], term: .q2)
            #expect(later.observe(["course": 96], term: .q1)["course"] == 1)
            #expect(later.observe(["course": 85], term: .q2)["course"] == 1)
        }
    }

    @Test("Accounts, courses and terms have independent baselines")
    func isolation() {
        withDefaults { defaults in
            var first = GradeChangeTracker(scope: "a", defaults: defaults)
            _ = first.observe(["one": 95, "two": 82], term: .q1)
            _ = first.observe(["one": 74], term: .q2)
            var second = GradeChangeTracker(scope: "b", defaults: defaults)
            #expect(second.observe(["one": 96], term: .q1).isEmpty)
            var reopened = GradeChangeTracker(scope: "a", defaults: defaults)
            #expect(reopened.observe(["one": 96, "two": 80], term: .q1) == ["one": 1, "two": -2])
            #expect(reopened.observe(["one": 76], term: .q2)["one"] == 2)
        }
    }

    @Test("Missing and invalid grades do not invent numeric changes")
    func missingValues() {
        withDefaults { defaults in
            var first = GradeChangeTracker(scope: "a", defaults: defaults)
            #expect(first.observe(["nil": nil, "nan": .nan, "infinity": .infinity], term: .q1).isEmpty)
            var reopened = GradeChangeTracker(scope: "a", defaults: defaults)
            #expect(reopened.observe(["nil": 90, "nan": 90, "infinity": 90], term: .q1).isEmpty)
            #expect(reopened.observe(["nil": 91], term: .q1)["nil"] == 1)
            var third = GradeChangeTracker(scope: "a", defaults: defaults)
            #expect(third.observe(["nil": nil], term: .q1).isEmpty)
            #expect(third.observe(["nil": 91], term: .q1).isEmpty)
            #expect(third.observe(["nil": 92], term: .q1)["nil"] == 1)
        }
    }

    @Test("First-ever viewing stays silent, then tracks refreshes against that score")
    func firstSessionRefresh() {
        withDefaults { defaults in
            var first = GradeChangeTracker(scope: "a", defaults: defaults)
            #expect(first.observe(["course": 95], term: .q1).isEmpty)
            #expect(first.observe(["course": 96], term: .q1)["course"] == 1)
            #expect(first.observe(["course": 96], term: .q1)["course"] == 1)
            #expect(first.observe(["course": 94.5], term: .q1)["course"] == -0.5)
        }
    }

    @Test("Extra-credit grades and fractional negative changes are retained")
    func extraCredit() {
        withDefaults { defaults in
            var first = GradeChangeTracker(scope: "a", defaults: defaults)
            _ = first.observe(["one": 105.5], term: .q1)
            var reopened = GradeChangeTracker(scope: "a", defaults: defaults)
            #expect(reopened.observe(["one": 105.25], term: .q1)["one"] == -0.25)
        }
    }

    @Test("Existing account-prefix reset removes seen grades")
    func reset() {
        withDefaults { defaults in
            var first = GradeChangeTracker(scope: "a", defaults: defaults)
            _ = first.observe(["course": 95], term: .q1)
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("account.a.") {
                defaults.removeObject(forKey: key)
            }
            var reset = GradeChangeTracker(scope: "a", defaults: defaults)
            #expect(reset.observe(["course": 96], term: .q1).isEmpty)
        }
    }

    @Test("Official score uses the displayed term bucket and historical fallback")
    func officialScores() {
        var course = UnifiedCourseData(
            corNumId: "course", stuId: "student", section: "1", gbId: "book",
            courseName: "Synthetic", semester: .both, termLength: "1 - 4",
            currentScores: [], historicalGrades: HistoricalGrades(rc1: "95", sm1: "96")
        )
        #expect(GradeChangeTracker.officialScore(for: course, term: .q1) == 95)
        #expect(GradeChangeTracker.officialScore(for: course, term: .sm1) == 96)
        let buckets: [(TermLabel, String)] = [(.q1, "Q1"), (.q2, "Q2"), (.sm1, "S1"), (.q3, "Q3"), (.q4, "Q4"), (.sm2, "S2")]
        for (term, bucket) in buckets {
            course.currentScores = [BucketScore(bucket: bucket, score: 105.25)]
            #expect(GradeChangeTracker.officialScore(for: course, term: term) == 105.25)
        }
        course.currentScores = [BucketScore(bucket: "Q1", score: .nan)]
        #expect(GradeChangeTracker.officialScore(for: course, term: .q1) == nil)
    }
}

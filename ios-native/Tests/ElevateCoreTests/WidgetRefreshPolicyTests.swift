import Foundation
import Testing
@testable import ElevateCore

@Suite("Widget assignment refresh recovery")
struct WidgetRefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test("Skipped or failed assignments retry even when the course cache is unchanged")
    func incompleteCoverage() {
        for updatedAt in [nil, now] {
            #expect(isDue(updatedAt: updatedAt, complete: false))
        }
    }

    @Test("A successful retry reuses fresh assignments until their own source expires")
    func recoveredCoverage() {
        #expect(!isDue(updatedAt: now, complete: true))
        #expect(!isDue(updatedAt: now.addingTimeInterval(-299), complete: true))
        #expect(isDue(updatedAt: now.addingTimeInterval(-300), complete: true))
        #expect(isDue(updatedAt: nil, complete: true))
    }

    @Test("A new widget snapshot or academic term fetches assignments with unchanged courses")
    func termChanges() {
        for previousTerm in [nil, "Q2", "SM1"] {
            #expect(WidgetAssignmentRefreshPolicy.isDue(
                term: .q1, previousTerm: previousTerm,
                coursesUpdatedAt: now, previousCoursesUpdatedAt: now,
                assignmentsUpdatedAt: now, assignmentsAreComplete: true, now: now
            ))
        }
    }

    @Test("A changed course source refreshes coverage even when assignments are fresh")
    func newCourseSource() {
        #expect(WidgetAssignmentRefreshPolicy.isDue(
            term: .q1, previousTerm: "Q1",
            coursesUpdatedAt: now, previousCoursesUpdatedAt: now.addingTimeInterval(-1),
            assignmentsUpdatedAt: now, assignmentsAreComplete: true, now: now
        ))
    }

    @Test("Foreground retries use a bounded cadence independent of a fresh course cache")
    func retryCadence() {
        #expect(AutomaticRefreshPolicy.isDue(lastUpdated: nil, lastAttempt: nil, now: now))
        #expect(!AutomaticRefreshPolicy.isDue(lastUpdated: nil, lastAttempt: now, now: now.addingTimeInterval(15)))
        #expect(AutomaticRefreshPolicy.isDue(lastUpdated: nil, lastAttempt: now, now: now.addingTimeInterval(300)))
    }

    @Test("Semester review uses the ending quarter's assignment bucket")
    func semesterAssignmentBuckets() {
        #expect(SchoolCalendar.quarter(for: .sm1).bucket == TermLabel.q2.bucket)
        #expect(SchoolCalendar.quarter(for: .sm2).bucket == TermLabel.q4.bucket)
        #expect(SchoolCalendar.quarter(for: .q1).bucket == TermLabel.q1.bucket)
        #expect(SchoolCalendar.quarter(for: .q3).bucket == TermLabel.q3.bucket)
    }

    private func isDue(updatedAt: Date?, complete: Bool) -> Bool {
        WidgetAssignmentRefreshPolicy.isDue(
            term: .q1, previousTerm: "Q1",
            coursesUpdatedAt: now, previousCoursesUpdatedAt: now,
            assignmentsUpdatedAt: updatedAt, assignmentsAreComplete: complete, now: now
        )
    }
}

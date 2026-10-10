import Foundation
import Testing
@testable import ElevateCore

@Suite("Foreground refresh cadence")
struct AutomaticRefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test("Fresh saved data waits, stale data refreshes at five minutes")
    func savedDataAge() {
        #expect(!AutomaticRefreshPolicy.isDue(lastUpdated: now.addingTimeInterval(-299), lastAttempt: nil, now: now))
        #expect(AutomaticRefreshPolicy.isDue(lastUpdated: now.addingTimeInterval(-300), lastAttempt: nil, now: now))
        #expect(AutomaticRefreshPolicy.isDue(lastUpdated: nil, lastAttempt: nil, now: now))
    }

    @Test("Failed attempts cool down even with missing or expired saved data")
    func failureCooldown() {
        for updated in [nil, now.addingTimeInterval(-900)] {
            #expect(!AutomaticRefreshPolicy.isDue(lastUpdated: updated, lastAttempt: now.addingTimeInterval(-299), now: now))
            #expect(AutomaticRefreshPolicy.isDue(lastUpdated: updated, lastAttempt: now.addingTimeInterval(-300), now: now))
        }
    }

    @Test("Manual successes postpone the next automatic request")
    func manualRefresh() {
        #expect(!AutomaticRefreshPolicy.isDue(lastUpdated: now, lastAttempt: now.addingTimeInterval(-600), now: now))
    }
}

@Suite("Background refresh eligibility")
struct BackgroundRefreshPolicyTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test("A missing check becomes eligible in fifteen minutes")
    func missingRequest() {
        #expect(BackgroundRefreshPolicy.interval == 900)
        #expect(BackgroundRefreshPolicy.shouldSubmit(hasPendingRequest: false, pendingDate: nil, now: now))
    }

    @Test("Repeated app transitions preserve an earlier or already eligible check")
    func preservesEarlierCheck() {
        let original = now.addingTimeInterval(900)
        for elapsed: TimeInterval in [0, 60, 899, 900, 1800] {
            #expect(!BackgroundRefreshPolicy.shouldSubmit(hasPendingRequest: true,
                pendingDate: original, now: now.addingTimeInterval(elapsed)))
        }
        #expect(!BackgroundRefreshPolicy.shouldSubmit(hasPendingRequest: true, pendingDate: nil, now: now))
    }

    @Test("A later legacy request can move earlier")
    func replacesLaterRequest() {
        #expect(BackgroundRefreshPolicy.shouldSubmit(hasPendingRequest: true,
            pendingDate: now.addingTimeInterval(1800), now: now))
    }
}

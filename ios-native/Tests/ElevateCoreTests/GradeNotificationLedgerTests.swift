import Foundation
import Testing
@testable import ElevateCore

@Suite("Official grade notification ledger")
struct GradeNotificationLedgerTests {
    @Test func firstObservationSeedsAndIndependentScopesStaySilent() {
        var ledger = GradeNotificationLedger()
        #expect(ledger.observe(["course-year1": 95], term: .q1).isEmpty)
        #expect(ledger.observe(["course-year1": 50], term: .q2).isEmpty)
        #expect(ledger.observe(["course-year2": 20], term: .q1).isEmpty)
        var anotherAccount = GradeNotificationLedger()
        #expect(anotherAccount.observe(["course-year1": 10], term: .q1).isEmpty)
        #expect(ledger.observe(["course-year1": 95], term: .q1).isEmpty)
    }

    @Test func cumulativeChangesAndBonusGrades() throws {
        var ledger = GradeNotificationLedger(threshold: 0.5)
        ledger.observe(["course": 100], term: .q1)
        #expect(ledger.observe(["course": 100.2], term: .q1).isEmpty)
        #expect(ledger.observe(["course": 100.4], term: .q1).isEmpty)
        let event = try #require(ledger.observe(["course": 100.6], term: .q1).first)
        #expect(event.previousScore == 100)
        #expect(event.currentScore == 100.6)
        #expect(event.kind == .averageChanged)
        #expect(ledger.latestObservedScore(courseID: "course", term: .q1) == 100.6)
        ledger.markSchedulingAccepted(eventID: event.id)
        #expect(ledger.observe(["course": 100.6], term: .q1).isEmpty)
        let fall = try #require(ledger.observe(["course": 100.1], term: .q1).first)
        #expect(fall.previousScore == 100.6)
        #expect(fall.currentScore == 100.1)
    }


    @Test func suppressedAcceptedRequestRetriesOnlyCurrentUnseenValues() throws {
        var ledger = GradeNotificationLedger()
        let old = Date(timeIntervalSince1970: 100), fresh = old.addingTimeInterval(10)
        ledger.observe(["seen": 90, "unseen": 80, "obsolete": 70], term: .q1, at: old)
        let events = ledger.observe(["seen": 91, "unseen": 81, "obsolete": 71], term: .q1, at: fresh)
        ledger.associateRequest("request", eventIDs: Set(events.map(\.id)))
        for event in events { ledger.markSchedulingAccepted(eventID: event.id, at: fresh) }
        ledger.markViewed(courseID: "seen", term: .q1, score: 91, sourceDate: fresh)
        ledger.observe(["obsolete": 72], term: .q1, at: fresh.addingTimeInterval(1))
        ledger.deferSuppressedRequest("request")
        #expect(ledger.pendingEvents.filter { $0.courseID == "unseen" }.count == 1)
        #expect(ledger.pendingEvents.filter { $0.courseID == "seen" }.isEmpty)
        #expect(ledger.pendingEvents.filter { $0.courseID == "obsolete" }.map(\.currentScore) == [72])
        var restored = try JSONDecoder().decode(GradeNotificationLedger.self, from: JSONEncoder().encode(ledger))
        restored.deferSuppressedRequest("request")
        #expect(restored.pendingEvents.count == 2)
        #expect(restored.observe(["unseen": 81], term: .q1, at: fresh.addingTimeInterval(2)).first?.currentScore == 81)
        #expect(restored.observe(["unseen": 80], term: .q1, at: fresh.addingTimeInterval(3)).isEmpty)
    }

    @Test func postedHundredthChangesAlertWithoutFloatingPointGaps() throws {
        var ledger = GradeNotificationLedger()
        ledger.observe(["course": 95], term: .q1)
        let rise = try #require(ledger.observe(["course": 95.01], term: .q1).first)
        ledger.markSchedulingAccepted(eventID: rise.id)
        #expect(ledger.observe(["course": 95.014], term: .q1).isEmpty)
        #expect(ledger.observe(["course": 95], term: .q1).first?.currentScore == 95)
    }

    @Test func persistedHalfPointPolicyUpgradesWithoutDiscardingHistory() throws {
        var legacy = GradeNotificationLedger(threshold: 0.5)
        legacy.observe(["course": 95, "retry": 80], term: .q1)
        let retry = try #require(legacy.observe(["retry": 90], term: .q1).first)
        legacy.markSchedulingFailed(eventID: retry.id)
        var restored = try JSONDecoder().decode(GradeNotificationLedger.self, from: JSONEncoder().encode(legacy))
        #expect(restored.delivery(for: retry.id) == .retry)
        #expect(restored.observe(["course": 95.01], term: .q1).first?.currentScore == 95.01)
    }

    @Test func visibleGradeSuppressesOnlyItsCourseTermAndRevision() throws {
        var ledger = GradeNotificationLedger()
        let old = Date(timeIntervalSince1970: 100), fresh = old.addingTimeInterval(10)
        ledger.observe(["a": 95, "b": 90], term: .q1, at: old)
        ledger.observe(["a": 80], term: .q2, at: old)
        let events = ledger.observe(["a": 96, "b": 91], term: .q1, at: fresh)
        ledger.observe(["a": 81], term: .q2, at: fresh)
        ledger.associateRequest("request", eventIDs: Set(ledger.pendingEvents.map(\.id)))
        ledger.markViewed(courseID: "a", term: .q1, score: 95, sourceDate: old)
        #expect(ledger.pendingEvents.count == 3)
        ledger.markViewed(courseID: "a", term: .q1, score: 96, sourceDate: fresh)
        #expect(ledger.pendingEvents.count == 2)
        #expect(ledger.unseenEvents(forRequest: "request").count == 2)
        #expect(ledger.delivery(for: try #require(events.first { $0.courseID == "a" }).id) == .consumed)
        ledger.markViewed(courseID: "b", term: .q1, score: 91, sourceDate: fresh)
        #expect(ledger.pendingEvents.map(\.term) == [.q2])
    }


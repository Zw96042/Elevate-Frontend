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

    @Test func viewingBeforeObservationDoesNotCreateAnAfterViewingAlert() throws {
        var ledger = GradeNotificationLedger()
        let old = Date(timeIntervalSince1970: 100), fresh = old.addingTimeInterval(10)
        ledger.observe(["course": 95], term: .q1, at: old)
        ledger.markViewed(courseID: "course", term: .q1, score: 95.01, sourceDate: fresh)
        #expect(ledger.observe(["course": 95.01], term: .q1, at: fresh).isEmpty)
        let unseen = try #require(ledger.observe(["course": 94], term: .q1, at: fresh.addingTimeInterval(1)).first)
        ledger.markSchedulingAccepted(eventID: unseen.id)
        #expect(ledger.observe(["course": 95.01], term: .q1, at: fresh.addingTimeInterval(2)).count == 1)
    }

    @Test func viewedRequestSurvivesRelaunchWithoutForegroundPresentation() throws {
        var ledger = GradeNotificationLedger()
        ledger.observe(["course": 90], term: .q1)
        let event = try #require(ledger.observe(["course": 91], term: .q1).first)
        ledger.associateRequest("request", eventIDs: [event.id])
        ledger.markSchedulingAccepted(eventID: event.id)
        #expect(ledger.unseenEvents(forRequest: "request").count == 1)
        ledger.markViewed(courseID: "course", term: .q1, score: 91, sourceDate: Date())
        let restored = try JSONDecoder().decode(GradeNotificationLedger.self, from: JSONEncoder().encode(ledger))
        #expect(restored.unseenEvents(forRequest: "request").isEmpty)
        #expect(restored.delivery(for: event.id) != .consumed)
    }

    @Test func newerDisplayedValueSuppressesAnObsoleteRequestButOldCacheDoesNot() throws {
        var ledger = GradeNotificationLedger()
        let old = Date(timeIntervalSince1970: 100), fresh = old.addingTimeInterval(10)
        ledger.observe(["course": 90], term: .q1, at: old)
        let event = try #require(ledger.observe(["course": 91], term: .q1, at: fresh).first)
        ledger.associateRequest("request", eventIDs: [event.id])
        ledger.markViewed(courseID: "course", term: .q1, score: 90, sourceDate: old)
        #expect(ledger.unseenEvents(forRequest: "request").count == 1)
        ledger.markViewed(courseID: "course", term: .q1, score: 92, sourceDate: fresh.addingTimeInterval(1))
        #expect(ledger.unseenEvents(forRequest: "request").isEmpty)
        #expect(ledger.observe(["course": 92], term: .q1, at: fresh.addingTimeInterval(1)).isEmpty)
    }

    @Test func legacyThresholdMigrationDoesNotBackfillOldSmallChanges() throws {
        var ledger = GradeNotificationLedger(threshold: 0.5)
        ledger.observe(["course": 95], term: .q1)
        ledger.observe(["course": 95.4], term: .q1)
        var restored = try JSONDecoder().decode(GradeNotificationLedger.self, from: JSONEncoder().encode(ledger))
        #expect(restored.observe(["course": 95.4], term: .q1).isEmpty)
        #expect(restored.observe(["course": 95.41], term: .q1).count == 1)
    }

    @Test func nilIsNeverZeroAndInvalidNumbersAreIgnored() throws {
        var ledger = GradeNotificationLedger()
        #expect(ledger.observe(["course": nil], term: .q1).isEmpty)
        #expect(ledger.observe(["course": .nan], term: .q1).isEmpty)
        let available = try #require(ledger.observe(["course": 0], term: .q1).first)
        #expect(available.kind == .gradeAvailable)
        #expect(available.previousScore == nil)
        #expect(available.currentScore == 0)
        ledger.markSchedulingAccepted(eventID: available.id)
        #expect(ledger.observe(["course": nil], term: .q1).isEmpty)
        #expect(ledger.observe(["course": 99], term: .q1).first?.kind == .gradeAvailable)
    }

    @Test func invalidSourcesAndOlderObservationsDoNotChangeHistory() {
        var ledger = GradeNotificationLedger()
        let now = Date(timeIntervalSince1970: 100)
        ledger.observe(["course": 95], term: .q1, at: now)
        for source: GradeObservationSource in [.cached, .failed, .staleAccount, .cancelled, .incomplete] {
            #expect(ledger.observe(["course": 10], term: .q1, source: source, at: now).isEmpty)
        }
        #expect(ledger.observe(["course": 10], term: .q1, at: now.addingTimeInterval(-1)).isEmpty)
        #expect(ledger.latestObservedScore(courseID: "course", term: .q1) == 95)
    }

    @Test func retriesKeepTheirIDAndAdvanceOnlyOnAcceptedScheduling() throws {
        var ledger = GradeNotificationLedger()
        ledger.observe(["course": 95], term: .q1)
        let event = try #require(ledger.observe(["course": 96], term: .q1).first)
        ledger.markSchedulingFailed(eventID: event.id)
        #expect(ledger.delivery(for: event.id) == .retry)
        #expect(ledger.observe(["course": 97], term: .q1).map(\.id) == [event.id])
        #expect(ledger.pendingEvents.count == 1)
        #expect(ledger.pendingEvents.first?.currentScore == 97)
        ledger.markSchedulingAccepted(eventID: event.id)
        #expect(ledger.pendingEvents.isEmpty)
        #expect(ledger.observe(["course": 97], term: .q1).isEmpty)
        let next = try #require(ledger.observe(["course": 98], term: .q1).first)
        #expect(next.previousScore == 97)
        #expect(next.currentScore == 98)
        ledger.consumeWithoutAlert(eventID: next.id)
        #expect(ledger.observe(["course": 98], term: .q1).isEmpty)
    }

    @Test func persistedRetrySurvivesRelaunchAndStorageIsBounded() throws {
        var ledger = GradeNotificationLedger(maximumEntries: 2)
        ledger.observe(["a": 90, "b": 90], term: .q1)
        let events = ledger.observe(["a": 91, "b": 91], term: .q1)
        ledger.markSchedulingFailed(eventID: try #require(events.first).id)
        let data = try JSONEncoder().encode(ledger)
        var restored = try JSONDecoder().decode(GradeNotificationLedger.self, from: data)
        #expect(restored.pendingEvents == ledger.pendingEvents)
        restored.observe(["c": 90], term: .q1)
        restored.observe(["c": 91], term: .q1)
        #expect(restored.pendingEvents.count == 2)
        restored.markSchedulingAccepted(eventID: events[0].id)
        #expect(restored.observe(["a": 92], term: .q1).count == 1)
        #expect(restored.delivery(for: events[0].id) == nil)
    }

    @Test func recoveredGradesDropObsoleteRetriesAndRetainCumulativeBaseline() throws {
        var ledger = GradeNotificationLedger(threshold: 0.5)
        ledger.observe(["course": 95], term: .q1)
        let dip = try #require(ledger.observe(["course": 85], term: .q1).first)
        ledger.markSchedulingFailed(eventID: dip.id)
        #expect(ledger.observe(["course": 95.2], term: .q1).isEmpty)
        #expect(ledger.pendingEvents.isEmpty)
        #expect(ledger.delivery(for: dip.id) == nil)
        let rise = try #require(ledger.observe(["course": 95.6], term: .q1).first)
        #expect(rise.previousScore == 95)
        #expect(rise.currentScore == 95.6)
        #expect(rise.id != dip.id)
    }

    @Test func pendingDirectionReversalsKeepIDWithLatestOfficialPayload() throws {
        var ledger = GradeNotificationLedger()
        ledger.observe(["course": 95], term: .q1)
        let rise = try #require(ledger.observe(["course": 96], term: .q1).first)
        ledger.markSchedulingFailed(eventID: rise.id)
        let fall = try #require(ledger.observe(["course": 94], term: .q1).first)
        #expect(fall.id == rise.id)
        #expect(fall.previousScore == 95 && fall.currentScore == 94)
        #expect(ledger.delivery(for: fall.id) == .retry)
        ledger.markSchedulingAccepted(eventID: fall.id)
        #expect(ledger.observe(["course": 94], term: .q1).isEmpty)
        #expect(ledger.observe(["course": 95], term: .q1).first?.previousScore == 94)
    }

    @Test func realTransformationKeepsMergedLiveEnrollmentEligible() throws {
        let gradebook = GradebookCourse(course: 100, courseName: "Physics", instructor: "Teacher", period: 1,
                                       time: nil, scores: [("TERM 3", 95)], stuId: "synthetic-student",
                                       corNumId: 100, section: "01", gbId: "synthetic-book")
        let history: AcademicHistory = [
            "2026-2027": AcademicYear(grade: 11, courses: [
                "Physics": HistoryCourse(courseName: "Physics", terms: "1 - 4", isTranscriptRecord: true),
                "Recorded": HistoryCourse(courseName: "Recorded", terms: "1 - 4", rc1: "99", isTranscriptRecord: true),
            ]),
            "2025-2026": AcademicYear(grade: 10, courses: ["Earlier": HistoryCourse(courseName: "Earlier", rc1: "85")]),
        ]
        let courses = UnifiedCourseTransformer.transform(history: SkywardHistoryAPI.combine(history: history, gradebook: [gradebook]))
        let live = try #require(courses.first { $0.courseId == 100 })
        #expect(live.currentAcademicYearIsVerified == nil)
        #expect(live.isTranscriptRecord == true)
        #expect(live.currentScores.first { $0.bucket == "Q1" }?.score == 95)
        #expect(GradeNotificationLedger.eligibleCourses(in: courses).map(\.id) == [live.id])
        var olderLive = live
        olderLive.gradeYear = 10
        olderLive.gbId = "older-book"
        #expect(GradeNotificationLedger.eligibleCourses(in: [olderLive, live]).map(\.id) == [live.id])
        var unknownYear = live
        unknownYear.gradeYear = nil
        #expect(GradeNotificationLedger.eligibleCourses(in: [unknownYear]).count == 1)
        #expect(GradeNotificationLedger.eligibleCourses(in: [unknownYear, live]).map(\.id) == [live.id])
    }

    @Test func preferencesAndReminderRoundTrip() throws {
        let preferences = NotificationPreferences()
        #expect(!preferences.gradeChanges && preferences.reminders)
        let reminder = LocalReminder(courseID: "synthetic", term: .q2, title: "Review notes", courseName: "Course", fireDate: Date(timeIntervalSince1970: 100))
        #expect(try JSONDecoder().decode(LocalReminder.self, from: JSONEncoder().encode(reminder)) == reminder)
    }

    @Test func retiredContentFlagsDoNotAlterSavedAlertChoices() throws {
        for oldConsent in [true, false] {
            let legacy = Data("{\"gradeChanges\":true,\"reminders\":false,\"showGradePreviews\":\(oldConsent),\"showNames\":\(oldConsent)}".utf8)
            let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: legacy)
            #expect(decoded.gradeChanges && !decoded.reminders)
            let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Bool])
            #expect(Set(encoded.keys) == ["gradeChanges", "reminders"])
        }
        #expect(try JSONDecoder().decode(NotificationPreferences.self, from: Data("{}".utf8)) == NotificationPreferences())
    }

    @Test func notificationBodiesAlwaysIncludeAvailableNamesAndNeverRequireConsent() {
        #expect(NotificationText.contentVersion == 3)
        #expect(NotificationText.gradeChanges(courseNames: ["Synthetic biology"])
                == "Grades updated in Synthetic biology. Open Elevate to review them.")
        #expect(NotificationText.gradeChanges(courseNames: ["", " \n"]) == "Your grades changed. Open Elevate to review them.")
        #expect(NotificationText.reminder(courseName: " Synthetic biology ", title: " Lab report\n") == "Synthetic biology: Lab report")
        #expect(NotificationText.reminder(courseName: " ", title: "\n") == "You have a school reminder. Open Elevate to view it.")
        #expect(NotificationText.reminder(courseName: "", title: "Essay") == "Essay")
        #expect(NotificationText.reminder(courseName: "Biology", title: "") == "Biology: School reminder")
    }

    @Test func gradeBodiesDeduplicateNamesAndBoundDisclosureWithAnHonestRemainingCount() {
        let names = [" Biology ", "", "Biology", "History", "Physics", "English", "Spanish", "History"]
        #expect(NotificationText.gradeChanges(courseNames: names)
                == "Grades updated in Biology, History, Physics, and 2 other classes. Open Elevate to review them.")
        #expect(NotificationText.gradeChanges(courseNames: ["Biology", "History", "Physics", "English"])
                == "Grades updated in Biology, History, Physics, and 1 other class. Open Elevate to review them.")
        #expect(NotificationText.gradeChanges(courseNames: ["Biology", "History"])
                == "Grades updated in Biology and History. Open Elevate to review them.")
        #expect(NotificationText.gradeChanges(courseNames: ["Biology", "History", "Physics"])
                == "Grades updated in Biology, History, and Physics. Open Elevate to review them.")
    }

    @Test func officialScoresCannotEnterTheNamesOnlyBodyBuilder() throws {
        var ledger = GradeNotificationLedger()
        ledger.observe(["synthetic": 97.1234], term: .q1)
        let event = try #require(ledger.observe(["synthetic": 82.5678], term: .q1).first)
        do {
            let body = NotificationText.gradeChanges(courseNames: ["Synthetic course"])
            #expect(!body.contains(String(event.currentScore)))
            #expect(!body.contains("82.57"))
            #expect(!body.contains("97.12"))
            #expect(!body.contains("%"))
            let reminder = NotificationText.reminder(courseName: "Synthetic course", title: "Synthetic assignment")
            #expect(!reminder.contains("82.57"))
            #expect(!reminder.contains("97.12"))
        }
    }
}

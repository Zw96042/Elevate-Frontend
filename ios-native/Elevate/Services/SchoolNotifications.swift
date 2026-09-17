import CryptoKit
import Foundation
import Observation
import UserNotifications
import UIKit

enum GradeCheckOrigin: Sendable { case foreground, background }

struct NotificationDestination: Equatable, Sendable {
    var scope: String
    var courseID: String?
    var term: TermLabel?
    var reminderID: String? = nil
    var assignmentID: String? = nil
}

@Observable @MainActor
final class SchoolNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SchoolNotifications()
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var reminders: [LocalReminder] = []
    private(set) var accountScope: String?
    var pendingDestination: NotificationDestination?
    var error: String?
    private(set) var isRequestingPermission = false
    private(set) var lastGradeCheck: Date?
    private(set) var lastBackgroundGradeCheck: Date?
    var backgroundStatus: String?
    var gradeChangesEnabled: Bool { preferences.gradeChanges }
    var remindersEnabled: Bool { preferences.reminders }
    private var preferences = NotificationPreferences()
    private var ledger = GradeNotificationLedger()
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var gradeRevision = UUID()
    @ObservationIgnored private var reminderRevision = UUID()
    @ObservationIgnored private var gradeObservationTask: Task<Void, Never>?
    @ObservationIgnored private var gradeObservationID: UUID?

    override private init() { super.init(); center.delegate = self }

    static func notificationCourseID(for course: UnifiedCourseData) -> String {
        SHA256.hash(data: Data(course.id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func refreshAuthorization() async {
        await refreshAuthorization(reconcileReminders: true)
    }

    private func refreshAuthorization(reconcileReminders: Bool) async {
        let token = generation
        let settings = await center.notificationSettings()
        guard generation == token else { return }
        let previouslyAllowed = canSchedule
        authorization = settings.authorizationStatus
        guard reconcileReminders, !previouslyAllowed, canSchedule,
              let scope = accountScope, preferences.reminders else { return }
        let revision = reminderRevision
        // Saved, unscheduled reminders become eligible after an iOS Settings
        // permission change. This never requests permission or calls refresh again.
        error = nil
        for reminder in reminders where reminder.fireDate > Date() {
            guard generation == token, reminderRevision == revision,
                  accountScope == scope, preferences.reminders, canSchedule else { return }
            _ = await scheduleReminder(reminder, scope: scope, token: token)
        }
    }

    func activateAccount(scope: String?) async {
        guard scope != accountScope else { await refreshAuthorization(); return }
        let previous = accountScope
        generation = UUID(); gradeRevision = UUID()
        let token = generation
        accountScope = scope
        if pendingDestination?.scope != scope { pendingDestination = nil }
        error = nil
        backgroundStatus = scope.flatMap { defaults.string(forKey: key($0, "backgroundStatus")) }
        gradeObservationTask?.cancel(); gradeObservationTask = nil; gradeObservationID = nil
        preferences = load(NotificationPreferences.self, scope: scope, suffix: "preferences") ?? NotificationPreferences()
        ledger = load(GradeNotificationLedger.self, scope: scope, suffix: "ledger") ?? GradeNotificationLedger()
        reminders = (load([LocalReminder].self, scope: scope, suffix: "reminders") ?? [])
            .filter { $0.fireDate > Date() }.sorted { $0.fireDate < $1.fireDate }
        lastGradeCheck = scope.flatMap { defaults.object(forKey: key($0, "lastCheck")) as? Date }
        lastBackgroundGradeCheck = scope.flatMap { defaults.object(forKey: key($0, "lastBackgroundCheck")) as? Date }
        persist()
        if let previous { await removeOwnedRequests(scope: previous) }
        guard generation == token else { return }
        // Activation restores all saved requests below, including already-authorized
        // accounts, so suppress the permission-transition restoration here.
        await refreshAuthorization(reconcileReminders: false)
        guard generation == token, let scope else { return }
        // Replace legacy payloads on activation, including alerts scheduled by
        // earlier builds that could include numeric grades.
        await removeOwnedRequests(scope: scope, legacyOnly: true)
        guard generation == token, preferences.reminders, canSchedule else { return }
        for reminder in reminders {
            guard generation == token else { return }
            _ = await scheduleReminder(reminder, scope: scope, token: token)
        }
    }
    func clearAccount(scope: String?) async {
        guard let scope else { return }
        for suffix in ["preferences", "ledger", "reminders", "lastCheck", "lastBackgroundCheck", "backgroundStatus"] { defaults.removeObject(forKey: key(scope, suffix)) }
        if accountScope == scope {
            generation = UUID(); gradeRevision = UUID(); accountScope = nil
            reminders = []; preferences = NotificationPreferences(); ledger = GradeNotificationLedger()
            lastGradeCheck = nil; pendingDestination = nil; error = nil; backgroundStatus = nil
            lastBackgroundGradeCheck = nil
            gradeObservationTask?.cancel(); gradeObservationTask = nil; gradeObservationID = nil
        }
        await removeOwnedRequests(scope: scope)
    }
    func setGradeChangesEnabled(_ enabled: Bool) async {
        guard let scope = accountScope else { return }
        preferences.gradeChanges = enabled; gradeRevision = UUID(); persist()
        let token = generation
        if enabled { _ = await requestPermission(token: token) }
        else {
            for event in ledger.pendingEvents { ledger.consumeWithoutAlert(eventID: event.id) }
            persist(); await removeOwnedRequests(scope: scope, kind: "grade")
        }
    }
    func setRemindersEnabled(_ enabled: Bool) async {
        guard let scope = accountScope else { return }
        preferences.reminders = enabled; reminderRevision = UUID(); persist()
        let token = generation
        if !enabled { await removeOwnedRequests(scope: scope, kind: "reminder"); return }
        guard await requestPermission(token: token), generation == token, preferences.reminders else { return }
        for reminder in reminders where reminder.fireDate > Date() {
            guard generation == token, preferences.reminders else { return }
            _ = await scheduleReminder(reminder, scope: scope, token: token)
        }
    }
    @discardableResult
    func saveReminder(course: UnifiedCourseData, term: TermLabel, assignmentID: String?, title: String,
                      fireDate: Date, expectedAccountScope: String) async -> Bool {
        // A sheet can outlive its originating account. Reject it before changing
        // the new account's state or asking that account for notification permission.
        guard let scope = accountScope, scope == expectedAccountScope else { return false }
        error = nil
        guard course.availableTerms.contains(term) else {
            error = "This term isn't available for the selected course."; return false
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 250 else { error = "Enter a reminder title of 250 characters or fewer."; return false }
        guard fireDate.timeIntervalSinceNow > 1, fireDate.timeIntervalSince1970.isFinite else { error = "Choose a future time for the reminder."; return false }
        reminders.removeAll { $0.fireDate <= Date() }
        guard reminders.count < 40 else { error = "You can save up to 40 upcoming reminders."; return false }
        let reminder = LocalReminder(courseID: Self.notificationCourseID(for: course), term: term, assignmentID: assignmentID,
                                     title: title, courseName: course.courseName, fireDate: fireDate)
        reminders.append(reminder); reminders.sort { $0.fireDate < $1.fireDate }; persist()
        let token = generation
        guard preferences.reminders else { error = "Reminder saved. Turn on reminders to receive an alert."; return true }
        guard await requestPermission(token: token), generation == token else {
            if generation == token { error = "Reminder saved, but notifications are off in iOS Settings." }
            return generation == token
        }
        _ = await scheduleReminder(reminder, scope: scope, token: token)
        return generation == token
    }
    func removeReminder(id: String) async {
        guard let scope = accountScope else { return }
        reminders.removeAll { $0.id == id }; persist()
        let identifier = reminderIdentifier(scope: scope, id: id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier]); center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }


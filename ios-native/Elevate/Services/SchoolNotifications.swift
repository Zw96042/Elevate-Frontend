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


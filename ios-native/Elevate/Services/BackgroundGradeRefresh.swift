import BackgroundTasks
import UIKit

/// iOS chooses when to run this; the requested date is never a polling promise.
@MainActor
enum BackgroundGradeRefresh {
    static let identifier = "com.zachwilson.elevate.grade-refresh"
    private static let enabledHintKey = "elevate.backgroundGrades.enabled"
    private static var schedulingRevision = UUID()

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                let notifications = SchoolNotifications.shared
                guard let account = CredentialStore.currentAccountIdentifier,
                      CredentialStore.load() != nil else {
                    // AfterFirstUnlock still requires one unlock after a restart.
                    notifications.updateBackgroundStatus("Background sign-in is unavailable. Open Elevate to check your connection.")
                    await scheduleIfEnabled()
                    refresh.setTaskCompleted(success: false)
                    return
                }
                await notifications.activateAccount(scope: account)
                guard !Task.isCancelled, CredentialStore.currentAccountIdentifier == account,
                      notifications.accountScope == account else {
                    refresh.setTaskCompleted(success: false)
                    return
                }
                guard notifications.gradeChangesEnabled else {
                    refresh.setTaskCompleted(success: true)
                    return
                }
                notifications.updateBackgroundStatus(nil)
                await scheduleIfEnabled()
                guard notifications.gradeChangesEnabled else {
                    refresh.setTaskCompleted(success: true)
                    return
                }
                do {
                    try Task.checkCancellation()
                    guard CredentialStore.currentAccountIdentifier == account,
                          notifications.accountScope == account else { throw CancellationError() }
                    let result = try await withTaskCancellationHandler {
                        try await DataService.shared.combinedCoursesObservation(forceRefresh: true)
                    } onCancel: {
                        Task { await DataService.shared.cancelCourseRefresh(accountScope: account) }
                    }
                    try Task.checkCancellation()
                    guard CredentialStore.currentAccountIdentifier == account,
                          notifications.accountScope == account else { throw CancellationError() }
                    if notifications.backgroundStatus == nil {
                        notifications.updateBackgroundStatus("Background grade check completed.")
                    }
                    if result.freshValidated {
                        await notifications.observeFreshGrades(courses: result.courses.filter { $0.isPlanningOnly != true }, accountScope: account, origin: .background, observedAt: result.updatedAt)
                    }
                    try Task.checkCancellation()
                    refresh.setTaskCompleted(success: true)
                } catch {
                    // Keep valid cache/ledger; no alert from failures or expired work.
                    if notifications.accountScope == account {
                        notifications.updateBackgroundStatus(Task.isCancelled
                            ? "iOS ended the last background check before it finished."
                            : "The last background check could not reach Skyward.")
                    }
                    refresh.setTaskCompleted(success: false)
                }
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleIfEnabled() async {
        schedulingRevision = UUID()
        let revision = schedulingRevision
        guard schedulingEnabled else { cancel(); return }
        let pending = await BGTaskScheduler.shared.pendingTaskRequests()
        guard schedulingRevision == revision else { return }
        guard schedulingEnabled else { cancel(); return }
        let existing = pending.first { $0.identifier == identifier }
        let now = Date()
        guard BackgroundRefreshPolicy.shouldSubmit(hasPendingRequest: existing != nil,
            pendingDate: existing?.earliestBeginDate, now: now) else { return }
        let requestDate = now.addingTimeInterval(BackgroundRefreshPolicy.interval)
        do {
            // Xcode 26 does not expose the iOS 27 submission API.
            #if compiler(>=6.4)
            if #available(iOS 27, *) {
                let taskIdentifier = identifier
                try await Task.detached {
                    let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
                    request.earliestBeginDate = requestDate
                    try await BGTaskScheduler.shared.submitTaskRequest(request)
                }.value
            } else {
                try submitLegacyRequest(at: requestDate)
            }
            #else
            try submitLegacyRequest(at: requestDate)
            #endif
            // On iOS 27 submission can finish after logout or a newer schedule.
            // Reconcile current intent instead of cancelling a newer account's task.
            if schedulingRevision != revision { await scheduleIfEnabled() }
        } catch {
            guard schedulingRevision == revision else { return }
            SchoolNotifications.shared.updateBackgroundStatus("Background checks are unavailable. Grades still refresh when you open Elevate.")
        }
    }

    @available(iOS, introduced: 17, obsoleted: 27)
    private static func submitLegacyRequest(at date: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        try BGTaskScheduler.shared.submit(request)
    }

    private static var schedulingEnabled: Bool {
        // The hint permits resubmission before first unlock only, never fetching.
        if let account = CredentialStore.currentAccountIdentifier {
            let enabled = SchoolNotifications.shared.accountScope == account && SchoolNotifications.shared.gradeChangesEnabled
            UserDefaults.standard.set(enabled, forKey: enabledHintKey)
            return enabled
        }
        return UIApplication.shared.applicationState != .active && UserDefaults.standard.bool(forKey: enabledHintKey)
    }

    static func cancel() {
        schedulingRevision = UUID()
        UserDefaults.standard.set(false, forKey: enabledHintKey)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

final class ElevateAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundGradeRefresh.register()
        _ = SchoolNotifications.shared
        return true
    }
}

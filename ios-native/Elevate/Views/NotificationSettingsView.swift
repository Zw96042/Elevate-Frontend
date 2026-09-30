import SwiftUI
import UIKit
import UserNotifications

/// The account's alert choices: grade changes (off until chosen), personal
/// reminders (on). Alerts include names and never grades. Elevate
/// has no server; grade checks run when the app is open and when iOS grants
/// background time, which iOS may delay or skip.
struct NotificationSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var notifications: SchoolNotifications { store.notifications }

    /// Changes are saved per account; without one there is nothing to change.
    private var canChange: Bool {
        notifications.accountScope != nil && !notifications.isRequestingPermission
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                if let error = notifications.error {
                    Label {
                        Text(error)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Color.gradeAttention)
                    }
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("notifications.error")
                }
                permissionSection
                gradesSection
                remindersSection
            }
            .padding(.horizontal, Metrics.page)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .softScrollEdges()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("notifications.screen")
        .task(id: scenePhase) {
            // Returning from iOS Settings may have changed permission.
            guard scenePhase == .active else { return }
            await notifications.refreshAuthorization()
        }
    }

    // MARK: - Permission

    private var permissionStatus: String {
        switch notifications.authorization {
        case .notDetermined: return "Not asked yet"
        case .denied: return "Off"
        case .authorized: return "Allowed"
        case .provisional: return "Delivered quietly"
        case .ephemeral: return "Allowed for now"
        @unknown default: return "Unknown"
        }
    }

    private var permissionExplanation: String {
        switch notifications.authorization {
        case .notDetermined:
            return "Elevate asks iOS for permission only when you turn on an alert or save a reminder."
        case .denied:
            return "iOS won't show Elevate's alerts. Your choices below are kept, and reminders stay saved, but nothing alerts until you allow notifications."
        default:
            return "iOS controls banners, sounds, and Lock Screen display for Elevate in Settings."
        }
    }

    private var permissionSection: some View {
        SettingsGroup(title: "iOS permission") {
            SettingsRow {
                Text("Notifications")
            } accessory: {
                Text(permissionStatus)
                    .foregroundStyle(notifications.authorization == .denied ? Color.gradeWarning : Color.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("notifications.permission")

            if notifications.authorization == .denied {
                InsetDivider()
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    SettingsRow {
                        Text("Open iOS Settings")
                    } accessory: {
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.muted)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("notifications.openSettings")
            }
        } footer: {
            Text(permissionExplanation)
                .foregroundStyle(Color.muted)
        }
    }

    // MARK: - Grades

    private var gradesSection: some View {
        SettingsGroup(title: "Grades") {
            toggleRow(
                "Grade changes",
                detail: "Alerts for unseen grade changes found while you're away.",
                isOn: Binding(
                    get: { notifications.gradeChangesEnabled },
                    set: { enabled in Task { await notifications.setGradeChangesEnabled(enabled) } }
                ),
                identifier: "notifications.gradeChanges"
            )
            InsetDivider()
            SettingsRow {
                Text("Last grade check")
            } accessory: {
                Text(notifications.lastGradeCheck.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                } ?? "Not yet")
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("notifications.lastCheck")
            InsetDivider()
            SettingsRow {
                Text("Last background check")
            } accessory: {
                Text(notifications.lastBackgroundGradeCheck.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                } ?? "Not recorded")
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("notifications.lastBackgroundCheck")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Alerts include class and assignment names, never grades. iOS controls notification previews.")
                    .foregroundStyle(Color.muted)
                if let status = notifications.backgroundStatus {
                    Text(status)
                        .foregroundStyle(Color.ink)
                }
                Text("Grade checks stay silent while Elevate is open. Unseen changes can alert after a background check. iOS decides when those checks run; reminders are scheduled separately. What-if estimates never trigger alerts.")
                    .foregroundStyle(Color.muted)
            }
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        let reminders = notifications.reminders.filter { $0.fireDate > Date() }
        return SettingsGroup(title: "Reminders") {
            toggleRow(
                "Reminders",
                detail: "Alerts at the times you choose for assignments and exams.",
                isOn: Binding(
                    get: { notifications.remindersEnabled },
                    set: { enabled in Task { await notifications.setRemindersEnabled(enabled) } }
                ),
                identifier: "notifications.reminders"
            )
            InsetDivider()
            if reminders.isEmpty {
                Text("No upcoming reminders.")
                    .font(.body)
                    .foregroundStyle(Color.muted)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .accessibilityIdentifier("notifications.reminders.empty")
            } else {
                ForEach(Array(reminders.enumerated()), id: \.element.id) { index, reminder in
                    if index > 0 { InsetDivider() }
                    reminderRow(reminder)
                }
            }
        } footer: {
            Text("Add one from an assignment's options in a class, from a Calendar assignment, or from Missing work. Reminders are saved on this iPhone for this account only.")
                .foregroundStyle(Color.muted)
        }
    }

    private func reminderRow(_ reminder: LocalReminder) -> some View {
        let course = ClassNameFormatter.format(reminder.courseName.replacingOccurrences(of: " ", with: "_"))
        let time = reminder.fireDate.formatted(date: .abbreviated, time: .shortened)
        let details = VStack(alignment: .leading, spacing: 2) {
            Text(reminder.title)
                .font(.body)
                .foregroundStyle(Color.ink)
            Text(course)
                .font(.subheadline)
                .foregroundStyle(Color.muted)
            Text(time)
                .font(.subheadline)
                .foregroundStyle(Color.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        let remove = Button("Remove") {
            Task { await notifications.removeReminder(id: reminder.id) }
        }
        .buttonStyle(ActionTextButtonStyle())
        .accessibilityLabel("Remove reminder \(reminder.title), \(time)")
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    details
                    remove
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    details
                    remove
                }
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 52)
    }

    // MARK: - Rows

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>, identifier: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.themeAccent)
        .disabled(!canChange)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .accessibilityIdentifier(identifier)
    }
}

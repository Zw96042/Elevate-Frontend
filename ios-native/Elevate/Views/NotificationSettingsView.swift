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


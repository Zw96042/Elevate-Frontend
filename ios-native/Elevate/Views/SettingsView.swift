import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    /// Owns the School records path when presented from the root.
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var themeManager = ThemeManager.shared
    @State private var showingDisconnectConfirmation = false
    @State private var isReloading = false
    @State private var isDisconnecting = false
    @State private var cacheStatus: String?
    @State private var dataError: String?
    @AccessibilityFocusState private var dataStatusFocused: Bool
    @State private var localRecordsPath: [RecordsRoute] = []
    /// Checks only on an explicit tap in Updates; never on open.
    @State private var appUpdates = AppUpdateService()
    @State private var appLock = AppLockStore.shared
    @State private var isEnablingAppLock = false
    /// Shown when turning the lock on fails without the store's own error.
    @State private var appLockMessage: String?
    @AccessibilityFocusState private var appLockStatusFocused: Bool

    /// The router's path, so `://history` can open Past courses; a local
    /// path wherever Settings is presented without a router.
    private var recordsPath: Binding<[RecordsRoute]> {
        Binding(
            get: { router?.recordsPath ?? localRecordsPath },
            set: { path in
                if let router { router.recordsPath = path } else { localRecordsPath = path }
            }
        )
    }

    var body: some View {
        NavigationStack(path: recordsPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                    accountSection
                    recordsSection
                    appearanceSection
                    notificationsSection
                    appLockSection
                    dataSection
                    updatesSection
                    aboutSection
                }
                .padding(.horizontal, Metrics.page)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .softScrollEdges()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings.screen")
            .navigationDestination(for: RecordsRoute.self) { route in
                // Each page loads its own data, read-only, when opened.
                Group {
                    switch route {
                    case .pastCourses:
                        PastCoursesView()
                    case .pastCourse(let course):
                        HistoricalCourseDetailView(course: course)
                    case .documents:
                        DocumentsView()
                    case .studentInfo:
                        StudentInfoView()
                    case .fees:
                        FeesView()
                    }
                }
                .toolbar(.visible, for: .navigationBar)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                        .accessibilityLabel("Close Settings")
                        .accessibilityIdentifier("settings.done")
                }
            }
            .alert("Disconnect Skyward?", isPresented: $showingDisconnectConfirmation) {
                Button("Disconnect", role: .destructive) {
                    Task {
                        isDisconnecting = true
                        dataError = nil
                        do {
                            try await store.disconnect()
                            setCacheStatus("Skyward disconnected")
                        } catch {
                            dataError = error.localizedDescription
                            focusDataStatus()
                        }
                        isDisconnecting = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your saved login, session, cached school data, what-if work, manual GPA classes, and widget data from this iPhone.")
            }
            .presentationDragIndicator(.visible)
        }
        // Whichever screen presented Settings, it reopens on its first page.
        .onDisappear {
            if !recordsPath.wrappedValue.isEmpty { recordsPath.wrappedValue = [] }
        }
        .foregroundStyle(Color.ink)
        .preferredColorScheme(themeManager.appearance.colorScheme)
        .tint(Color.themeAccent)
    }

    // MARK: - Account

    /// "Skyward" with the district beneath it, and the connection state as
    /// the row's value. The state joins the text at accessibility sizes.
    private var accountSection: some View {
        SettingsGroup(title: "Account") {
            NavigationLink {
                SkywardAccountView()
            } label: {
                SettingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skyward")
                        Text(CredentialStore.districtName)
                            .font(.subheadline)
                            .foregroundStyle(Color.muted)
                        if dynamicTypeSize.isAccessibilitySize {
                            accountStatus
                        }
                    }
                } accessory: {
                    HStack(spacing: 10) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            accountStatus
                        }
                        RowChevron()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("settings.account")

            if !store.hasCredentials {
                Text("Credentials are verified before they are stored on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }

            InsetDivider()

            Link(
                destination: URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSdqtqDEwLQY03KHS_LZDpjOjTcP_j8MCIizaMRMHTS6T5tOzQ/viewform?usp=dialog")!
            ) {
                externalLinkLabel("Request another district")
            }
            .buttonStyle(RowPressStyle())
        } footer: {
            EmptyView()
        }
    }

    private var accountStatusText: String {
        if store.hasCredentials { return "Connected" }
        if store.isUsingSampleData { return "Sample data" }
        return "Login required"
    }

    private var accountStatus: some View {
        Text(accountStatusText)
            .font(.body)
            .foregroundStyle(store.hasCredentials ? Color.muted : Color.gradeWarning)
    }

    // MARK: - School records

    private struct RecordDestination {
        var route: RecordsRoute
        var title: String
        var note: String
        var identifier: String
    }

    /// Titles match the screens they open. Identifiers are unchanged from
    /// the former Records tab.
    private static let recordDestinations: [RecordDestination] = [
        RecordDestination(route: .pastCourses, title: "Past courses",
                          note: "Grades from earlier years", identifier: "records.pastCourses"),
        RecordDestination(route: .documents, title: "Documents",
                          note: "Report cards and files", identifier: "records.documents"),
        RecordDestination(route: .studentInfo, title: "Student Info",
                          note: "Enrollment and contacts", identifier: "records.studentInfo"),
        RecordDestination(route: .fees, title: "Fees",
                          note: "Charges and payments", identifier: "records.fees"),
    ]

    private var recordsSection: some View {
        SettingsGroup(title: "School records") {
            ForEach(Array(Self.recordDestinations.enumerated()), id: \.element.identifier) { index, destination in
                if index > 0 { InsetDivider() }
                NavigationLink(value: destination.route) {
                    SettingsRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.title)
                            Text(destination.note)
                                .font(.subheadline)
                                .foregroundStyle(Color.muted)
                        }
                    } accessory: {
                        RowChevron()
                    }
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier(destination.identifier)
            }
        } footer: {
            EmptyView()
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        @Bindable var theme = themeManager
        return SettingsGroup(title: "Appearance") {
            NavigationLink {
                AppearanceSettingsView(
                    palette: Binding(
                        get: { theme.palette },
                        set: { palette in updateTheme { theme.palette = palette } }
                    ),
                    appearance: Binding(
                        get: { theme.appearance },
                        set: { appearance in updateTheme { theme.appearance = appearance } }
                    )
                )
            } label: {
                SettingsRow {
                    Text("Theme")
                } accessory: {
                    HStack(spacing: 10) {
                        Text(theme.palette.name)
                            .foregroundStyle(Color.muted)
                        RowChevron()
                    }
                }
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("settings.appearance")
        } footer: {
            EmptyView()
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        SettingsGroup(title: "Notifications") {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                SettingsRow {
                    Text("Notification settings")
                } accessory: {
                    HStack(spacing: 10) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text(notificationSummary)
                                .foregroundStyle(Color.muted)
                        }
                        RowChevron()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(RowPressStyle())
            .disabled(!store.canShowData)
            .accessibilityIdentifier("settings.notifications")
        } footer: {
            EmptyView()
        }
    }

    /// Which of the two kinds of alert is on, from the account's saved choice.
    private var notificationSummary: String {
        let notifications = store.notifications
        switch (notifications.gradeChangesEnabled, notifications.remindersEnabled) {
        case (true, true): return "Grades, reminders"
        case (true, false): return "Grades"
        case (false, true): return "Reminders"
        case (false, false): return "Off"
        }
    }

    // MARK: - App lock

    /// Off unless chosen. Turning it on waits for iOS to confirm Face ID,
    /// Touch ID, or the passcode, and only that confirmation saves it; the
    /// switch stays off meanwhile. Turning it off is immediate, since Settings
    /// is reachable only while Elevate is unlocked.
    private var appLockSection: some View {
        let isBusy = isEnablingAppLock || appLock.isAuthenticating
        return SettingsGroup(title: "App lock") {
            Toggle(isOn: Binding(
                get: { appLock.isEnabled },
                set: { enabled in setAppLock(enabled) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Require \(appLock.authenticationName)")
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    Text(isBusy
                         ? "Waiting for \(appLock.authenticationName)…"
                         : "Ask for \(AppLockCopy.method(for: appLock)) when opening Elevate.")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.themeAccent)
            .disabled(isBusy || appLock.isLocked)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .accessibilityIdentifier("settings.appLock")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let message = appLock.error ?? appLockMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color.gradeAttention)
                        .accessibilityFocused($appLockStatusFocused)
                        .accessibilityIdentifier("settings.appLock.error")
                }
                Text("This locks Elevate's screens. Notifications and widgets stay visible, as iOS shows them.")
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private func setAppLock(_ enabled: Bool) {
        appLockMessage = nil
        appLock.clearError()
        guard enabled else {
            if !appLock.isLocked { appLock.disable() }
            return
        }
        guard !isEnablingAppLock, !appLock.isAuthenticating else { return }
        isEnablingAppLock = true
        Task {
            let didEnable = await appLock.enable()
            isEnablingAppLock = false
            guard !didEnable else { return }
            if appLock.error == nil { appLockMessage = "App lock wasn't turned on." }
            focusAppLockStatus()
        }
    }

    private func focusAppLockStatus() {
        appLockStatusFocused = false
        Task { @MainActor in
            await Task.yield()
            appLockStatusFocused = true
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        SettingsGroup(title: "Data") {
            Button {
                Task {
                    isReloading = true
                    dataError = nil
                    cacheStatus = nil
                    await store.clearAllCaches()
                    if store.coursesError != nil || store.messagesError != nil || store.calendarError ?? store.attendanceError ?? store.feesError ?? store.studentInfoError ?? store.documentsError != nil {
                        dataError = "Some data couldn't be refreshed. Saved data remains visible where available."
                        focusDataStatus()
                    } else {
                        setCacheStatus("Data reloaded")
                    }
                    isReloading = false
                }
            } label: {
                SettingsRow {
                    Text(isReloading ? "Reloading data…" : "Reload all data")
                } accessory: {
                    if isReloading {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(RowPressStyle())
            .disabled(isReloading || isDisconnecting || !store.canShowData)
            .accessibilityIdentifier("settings.reload")

            if store.hasCredentials {
                InsetDivider()
                Button(role: .destructive) {
                    showingDisconnectConfirmation = true
                } label: {
                    SettingsRow {
                        Text(isDisconnecting ? "Disconnecting…" : "Disconnect Skyward")
                            .foregroundStyle(Color.gradeAttention)
                    } accessory: {
                        if isDisconnecting {
                            ProgressView()
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(RowPressStyle())
                .disabled(isReloading || isDisconnecting)
                .accessibilityIdentifier("settings.disconnect")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let dataError {
                    Label(dataError, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color.gradeAttention)
                        .accessibilityFocused($dataStatusFocused)
                } else if let cacheStatus {
                    Label(cacheStatus, systemImage: "checkmark")
                        .foregroundStyle(Color.ink)
                        .transition(.opacity)
                        .accessibilityFocused($dataStatusFocused)
                }
                Text(dataExplanation)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private var dataExplanation: String {
        let automatic = "Checks for updates every five minutes while Elevate is open."
        if store.hasCredentials {
            return automatic + " Reloading keeps your login and local what-if work. Disconnecting removes all account data from this iPhone."
        }
        return automatic + " Reloading keeps your local what-if work."
    }

    // MARK: - Updates

    /// The installed version with the last App Store result, and the school
    /// dates built into this version. Neither row fetches anything on open.
    private var updatesSection: some View {
        SettingsGroup(title: "Updates") {
            NavigationLink {
                AppUpdatesView(service: appUpdates)
            } label: {
                SettingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(InstalledAppInfo.displayName)
                        Text(AppUpdateStatus(service: appUpdates).summary)
                            .font(.subheadline)
                            .foregroundStyle(Color.muted)
                    }
                } accessory: {
                    if appUpdates.isChecking {
                        ProgressView()
                            .accessibilityHidden(true)
                    } else {
                        RowChevron()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("updates.navigation")

            InsetDivider()

            NavigationLink {
                SchoolCalendarSourceView()
            } label: {
                SettingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("School calendar")
                        Text(SchoolCalendarSourceView.summary())
                            .font(.subheadline)
                            .foregroundStyle(Color.muted)
                    }
                } accessory: {
                    RowChevron()
                }
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("schoolCalendar.navigation")
        } footer: {
            Text("Elevate checks Apple's App Store listing only when you tap Check. No Skyward information is sent.")
                .foregroundStyle(Color.muted)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsGroup(title: "About") {
            Link(destination: URL(string: "https://elevate.wilsonzach.com/privacy")!) {
                externalLinkLabel("Privacy Policy")
            }
            .buttonStyle(RowPressStyle())
            InsetDivider()
            Link(destination: URL(string: "mailto:zach.wilson.atx@gmail.com")!) {
                externalLinkLabel("Contact Support")
            }
            .buttonStyle(RowPressStyle())
        } footer: {
            Text("Elevate is independent and is not affiliated with Skyward, Inc. or Eanes ISD.")
                .foregroundStyle(Color.muted)
        }
    }

    private func externalLinkLabel(_ title: String) -> some View {
        SettingsRow {
            Text(title)
        } accessory: {
            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
        }
    }

    private func updateTheme(_ change: () -> Void) {
        Motion.perform(reduceMotion ? nil : .easeInOut(duration: 0.25), change)
    }

    private func setCacheStatus(_ status: String) {
        Motion.perform(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            cacheStatus = status
        }
        focusDataStatus()
    }

    private func focusDataStatus() {
        dataStatusFocused = false
        Task { @MainActor in
            await Task.yield()
            dataStatusFocused = true
        }
    }
}

// MARK: - Settings layout

/// A group of open settings rows under a quiet label, with an optional note
/// beneath it. The navigation title is the only heading on the screen; group
/// labels name the groups and rows carry the content at body size.
struct SettingsGroup<Content: View, Footer: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel(title)
            VStack(spacing: 0) {
                content()
            }
            if Footer.self != EmptyView.self {
                footer()
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }
}

private extension Color {
    var rgbHex: UInt32? {
        let resolved = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: nil) else { return nil }
        return (UInt32((red * 255).rounded()) << 16)
            | (UInt32((green * 255).rounded()) << 8)
            | UInt32((blue * 255).rounded())
    }
}

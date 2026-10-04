import SwiftUI

/// Navigation bars use the system SF Pro titles, matching the content type.
@main
struct ElevateApp: App {
    @UIApplicationDelegateAdaptor(ElevateAppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootTabView().environment(store)
        }
    }
}

/// DEBUG-only launch arguments used for screenshots and UI testing.
private enum LaunchArguments {
    /// `-SampleData` skips first-run onboarding so screenshots open on data.
    static var usesSampleData: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-SampleData")
        #else
        return false
        #endif
    }

    /// `-ShowOnboarding` forces the introduction without reading or writing
    /// the persisted completion flag.
    static var forcesOnboarding: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ShowOnboarding")
        #else
        return false
        #endif
    }
    /// Synthetic verification of the update replay policy. These arguments
    /// have no effect without SampleData and never exist in Release.
    static var seedsLegacyOnboarding: Bool {
        #if DEBUG
        return usesSampleData && ProcessInfo.processInfo.arguments.contains("-OnboardingMigrationPreview")
        #else
        return false
        #endif
    }

    static var evaluatesSampleOnboarding: Bool {
        #if DEBUG
        return usesSampleData && (seedsLegacyOnboarding
            || ProcessInfo.processInfo.arguments.contains("-EvaluateSampleOnboarding"))
        #else
        return false
        #endif
    }

}

/// Courses holds GPA and assignments; Calendar, Inbox and Search have their
/// own roots. Pushed screens keep the tab bar. School records live in the
/// one Settings sheet, presented here for every root.
struct RootTabView: View {
    private enum OnboardingPresentation: String, Identifiable {
        case firstRun
        case preview

        var id: String { rawValue }
    }

    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OnboardingState.completedKey) private var onboardingCompleted = false
    @State private var appLock = AppLockStore.shared
    @State private var theme = ThemeManager.shared
    @State private var router = AppRouter()
    @State private var onboarding: OnboardingPresentation?
    @State private var didEvaluateOnboarding = false
    @State private var pendingURL: URL?

    /// Students whose data is loaded. A different set means another account.
    private var studentIDs: Set<String> {
        Set(store.courses?.map(\.stuId) ?? [])
    }

    var body: some View {
        tabs
        // Cover the first frame too, before the scene's UIKit cover attaches.
        .opacity(appLock.isContentCovered ? 0 : 1)
        .allowsHitTesting(!appLock.isContentCovered)
        .accessibilityHidden(appLock.isContentCovered)
        // Inside the router's environment, so Settings can push records.
        // Reopening Settings starts at its first page.
        .sheet(isPresented: $router.isShowingSettings, onDismiss: {
            if !router.recordsPath.isEmpty { router.recordsPath = [] }
        }) {
            SettingsView()
        }
        .environment(router)
        .environment(appLock)
        .environment(\.isMainContentVisible, onboarding == nil && !appLock.isContentCovered)
        .fullScreenCover(item: $onboarding) { presentation in
            OnboardingView(mode: presentation == .firstRun ? .firstRun : .preview) {
                finishOnboarding(presentation)
            }
            .interactiveDismissDisabled()
            .tint(Color.themeAccent)
            .foregroundStyle(Color.ink)
            .preferredColorScheme(theme.appearance.colorScheme)
        }
        .tint(Color.themeAccent)
        .foregroundStyle(Color.ink)
        .preferredColorScheme(theme.appearance.colorScheme)
        .softScrollEdges()
        .background(Color.appBackground.ignoresSafeArea())
        .background {
            AppLockPresentation(store: appLock) {
                AppLockScreenView(store: appLock)
                    .preferredColorScheme(theme.appearance.colorScheme)
            }
            .frame(width: 0, height: 0)
        }
        .onAppear(perform: evaluateOnboarding)
        .onOpenURL { url in
            pendingURL = url
            openPendingURL()
        }
        // Pushed classes belong to one account; drop them when it changes.
        .onChange(of: store.hasCredentials) { _, _ in
            if pendingURL.flatMap({ AssignmentLink(url: $0) }) == nil { pendingURL = nil }
            router.resetForAccountChange()
        }
        .onChange(of: store.accountRevision) { _, _ in
            // Scoped assignment links can arrive before cold-launch account
            // activation. Validate their scope after activation, not before.
            if pendingURL.flatMap({ AssignmentLink(url: $0) }) == nil { pendingURL = nil }
            router.resetForAccountChange()
        }
        .onChange(of: studentIDs) { old, new in
            // Loading an account's first data is not a change of account.
            if !old.isEmpty, old != new { router.resetForAccountChange() }
        }
        // Search's field closes when another tab or Settings takes over,
        // including opening a result, links and notifications.
        .onChange(of: router.selectedTab) { _, tab in
            if tab != .search { router.dismissSearch() }
        }
        .onChange(of: router.isShowingSettings) { _, showing in
            if showing { router.dismissSearch() }
        }
        .task(id: store.accountRevision) {
            let scope = store.isUsingSampleData ? "sample" : (store.hasCredentials ? CredentialStore.currentAccountIdentifier : nil)
            #if DEBUG
            if LaunchArguments.usesSampleData,
               let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-PendingAssignmentPreview=") }),
               let url = URL(string: String(argument.dropFirst("-PendingAssignmentPreview=".count))),
               AssignmentLink(url: url)?.scope == "sample" {
                pendingURL = url
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
            }
            #endif
            await store.notifications.activateAccount(scope: scope)
            await store.notifications.refreshAuthorization()
            await BackgroundGradeRefresh.scheduleIfEnabled()
            openPendingURL()
            openNotificationDestination()
            #if DEBUG
            await SampleData.scheduleNotificationTapPreview(courses: store.courses ?? [])
            #endif
        }
        .onChange(of: store.notifications.pendingDestination) { _, _ in openNotificationDestination() }
        .onChange(of: store.notifications.accountScope) { _, _ in
            // Account activation can finish after the scene becomes active.
            // React from the current view instead of a task's earlier phase.
            openPendingURL()
            openNotificationDestination()
        }
        .onChange(of: store.coursesRefreshRevision) { _, _ in
            openPendingURL()
            openNotificationDestination()
        }
        .onChange(of: appLock.isContentCovered) { _, covered in
            if !covered {
                openPendingURL()
                openNotificationDestination()
            }
        }
        .onChange(of: store.notifications.gradeChangesEnabled) { _, _ in
            Task { await BackgroundGradeRefresh.scheduleIfEnabled() }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.notifications.refreshAuthorization()
            await store.runForegroundRefreshLoop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                store.endCourseGradeViewingSession()
                Task { await BackgroundGradeRefresh.scheduleIfEnabled() }
            } else if phase == .active {
                openPendingURL()
                openNotificationDestination()
            }
        }
    }

    /// The active domain's query as the system search field edits it, cut to
    /// the router's limit. Lowering the field from another tab or under
    /// Settings may empty it; that query is kept for the next visit. Clearing
    /// it on Search, and account changes, still empty it.
    private var searchText: Binding<String> {
        Binding(get: { router.activeSearchQuery }, set: { text in
            if text.isEmpty, router.selectedTab != .search || router.isShowingSettings { return }
            router.setActiveSearchQuery(text)
        })
    }

    /// Taps go through the router, so entering Search picks its domain from
    /// the screen being left before that screen is hidden.
    private var tabSelection: Binding<AppRouter.Tab> {
        Binding(get: { router.selectedTab }, set: { router.select($0) })
    }

    private var searchPrompt: Text {
        router.activeSearchDomain == .colleges ? Text("Search colleges") : Text("Search assignments")
    }

    /// Colleges when Search was entered from College profiles or a college;
    /// assignments otherwise.
    @ViewBuilder
    private var searchContent: some View {
        switch router.searchDomain {
        case .colleges: CollegeSearchView()
        case .assignments: AssignmentSearchView()
        }
    }

    /// iOS 26 draws Search as the system's separate search tab beside the
    /// Liquid Glass bar. Tapping it widens the field across the bar and
    /// focuses it, above the keyboard. Earlier releases keep the standard
    /// bar, with Search as its fourth item and its field on the page.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: tabSelection) {
                Tab("Courses", systemImage: "graduationcap", value: AppRouter.Tab.courses) {
                    CoursesView()
                }
                Tab("Calendar", systemImage: "calendar", value: AppRouter.Tab.calendar) {
                    CalendarView()
                }
                Tab("Inbox", systemImage: "envelope", value: AppRouter.Tab.inbox) {
                    InboxView()
                }
                Tab(value: AppRouter.Tab.search, role: .search) {
                    searchContent
                }
            }
            .searchable(text: searchText, isPresented: $router.isSearchPresented, prompt: searchPrompt)
            .tabViewSearchActivation(.searchTabSelection)
        } else {
            TabView(selection: tabSelection) {
                CoursesView()
                    .tabItem { Label("Courses", systemImage: "graduationcap") }
                    .tag(AppRouter.Tab.courses)
                CalendarView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(AppRouter.Tab.calendar)
                InboxView()
                    .tabItem { Label("Inbox", systemImage: "envelope") }
                    .tag(AppRouter.Tab.inbox)
                searchContent
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(AppRouter.Tab.search)
            }
        }
    }

    private func openPendingURL() {
        guard scenePhase == .active, !appLock.isContentCovered, let url = pendingURL else { return }
        if let link = AssignmentLink(url: url) {
            guard let activeScope = store.notifications.accountScope else { return }
            guard link.scope == activeScope else { pendingURL = nil; return }
            guard let courses = store.courses else { return }
            pendingURL = nil
            guard let course = courses.first(where: {
                SchoolNotifications.notificationCourseID(for: $0) == link.courseID
            }), course.availableTerms.contains(link.term) else { return }
            store.selectedTerm = link.term
            router.showAssignment(course: course, term: link.term, assignmentID: link.assignmentID)
            return
        }
        pendingURL = nil
        if router.open(url) {
            // The GPA widgets show the current school year.
            store.selectedGradeLevel = store.currentGradeLevel
        }
    }

        }
    }
}

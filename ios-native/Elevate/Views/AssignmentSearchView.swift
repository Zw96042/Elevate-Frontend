import SwiftUI

/// Finds assignments in the selected quarter's official Calendar snapshot.
/// The quarter's assignments load once per quarter and account; every query
/// is matched locally as it is typed, and nothing typed is saved. A result
/// opens its class in Courses on the assignment's quarter, as Calendar does.
/// Only Skyward's titles, categories, dates and statuses are shown.
struct AssignmentSearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isMainContentVisible) private var isMainContentVisible
    @State private var showingConnect = false
    @FocusState private var fieldFocused: Bool

    /// The query is not part of this: typing never starts a request.
    private struct LoadIdentity: Hashable {
        var accountRevision: Int
        var coursesRevision: Int
        var canShowData: Bool
        var term: TermLabel
        var isSelected: Bool
        var isActive: Bool
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(
            accountRevision: store.accountRevision,
            coursesRevision: store.coursesRefreshRevision,
            canShowData: store.canShowData,
            term: store.calendarTerm,
            isSelected: router.selectedTab == .search,
            isActive: scenePhase == .active
        )
    }

    /// iOS 26 types into the system field in the tab bar, which the root
    /// attaches and the system focuses. Earlier releases use this page's own
    /// field below the title.
    private var usesOwnField: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    private var query: Binding<String> {
        Binding(get: { router.searchQuery }, set: { router.searchQuery = String($0.prefix(AppRouter.searchQueryLimit)) })
    }

    private var trimmedQuery: String {
        router.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.canShowData {
                    LoginPromptView(message: "Connect your Skyward account to search assignments from your classes.") {
                        showingConnect = true
                    }
                } else {
                    page
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if usesOwnField, store.canShowData { searchField }
            }
            .screenTitle("Search") {
                fieldFocused = false
                router.isShowingSettings = true
            }
            .background(Color.appBackground.ignoresSafeArea())
            .sheet(isPresented: $showingConnect) { SkywardConnectSheet() }
            .task(id: loadIdentity) {
                let identity = loadIdentity
                guard identity.isSelected, identity.isActive, identity.canShowData else { return }
                await store.refreshCalendar()
            }
            .onAppear(perform: focusFieldIfStarting)
            .onChange(of: router.selectedTab) { _, tab in
                if tab == .search { focusFieldIfStarting() } else { fieldFocused = false }
            }
            .onChange(of: isMainContentVisible) { _, _ in focusFieldIfStarting() }
            .onChange(of: store.accountRevision) { _, _ in
                fieldFocused = false
                if !router.searchQuery.isEmpty { router.searchQuery = "" }
            }
        }
    }

    /// Before iOS 26, opening Search to an empty query starts typing;
    /// returning to a query keeps its results in view without raising the
    /// keyboard. On iOS 26 the system focuses its own field.
    private func focusFieldIfStarting() {
        guard usesOwnField, router.selectedTab == .search, isMainContentVisible, store.canShowData,
              !router.isShowingSettings, router.searchQuery.isEmpty else { return }
        Task { @MainActor in
            await Task.yield()
            guard router.selectedTab == .search, isMainContentVisible, store.canShowData,
                  !router.isShowingSettings, router.searchQuery.isEmpty else { return }
            fieldFocused = true
        }
    }


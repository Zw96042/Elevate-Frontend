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

    // MARK: - Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
            TextField("Titles, classes, categories", text: query)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { fieldFocused = false }
                .accessibilityLabel("Search assignments in \(store.calendarTerm.displayName)")
                .accessibilityIdentifier("search.field")
            if !router.searchQuery.isEmpty {
                Button {
                    router.searchQuery = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ScopePressStyle())
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("search.clear")
            }
        }
        .padding(.leading, 10)
        .frame(minHeight: 44)
        .background(Color.well, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        .padding(.horizontal, Metrics.page)
        .padding(.bottom, 8)
        .background(Color.appBackground)
    }

    // MARK: - Source

    private enum SourceState: Equatable {
        case loading
        case failed(String)
        case loaded
    }

    /// The selected quarter's saved assignments only; another quarter's
    /// entries are never searched under this quarter's name.
    private var calendarData: SchoolCalendarData? {
        guard let data = store.calendarData, data.term == store.calendarTerm else { return nil }
        return data
    }

    /// As in Calendar: data in which no class resolved is a failure, not an
    /// empty quarter. Nothing saved and no failure yet counts as loading.
    private var assignmentState: SourceState {
        guard let data = calendarData,
              data.resolvedCourseCount > 0 || data.failedCourseNames.isEmpty else {
            if let error = store.calendarError, !store.calendarLoading { return .failed(error) }
            return .loading
        }
        return .loaded
    }

    /// Classes with nothing saved, which aren't searched, and classes whose
    /// saved assignments are searched after a failed refresh.
    private struct Coverage {
        var missing: [String] = []
        var saved: [String] = []
        var isComplete: Bool { missing.isEmpty && saved.isEmpty }
    }

    private func coverage(_ data: SchoolCalendarData) -> Coverage {
        let missing = SchoolCalendar.eligibleCourses(store.courses ?? [], term: data.term)
            .filter { !data.resolvedCourseIDs.contains($0.id) }
            .map(\.courseName)
        let missingNames = Set(missing)
        return Coverage(missing: missing, saved: data.failedCourseNames.filter { !missingNames.contains($0) })
    }

    // MARK: - Page

    private var page: some View {
        let state = assignmentState
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                    .padding(.horizontal, Metrics.page)


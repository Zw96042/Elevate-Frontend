import SwiftUI

/// Search's college domain, chosen when Search is entered from College
/// profiles or a college. Matches the offline catalog by name and alias as
/// it is typed: no request, no account needed, and no assignment refresh.
/// A result opens in Courses above College profiles, so Back returns to the
/// catalog; the query stays for the next visit from there.
struct CollegeSearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.isMainContentVisible) private var isMainContentVisible
    @FocusState private var fieldFocused: Bool

    /// iOS 26 types into the system field in the tab bar, which the root
    /// attaches and the system focuses. Earlier releases use this page's own
    /// field below the title.
    private var usesOwnField: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }

    private var query: Binding<String> {
        Binding(get: { router.collegeQuery }, set: { text in
            let clamped = String(text.prefix(AppRouter.searchQueryLimit))
            if router.collegeQuery != clamped { router.collegeQuery = clamped }
        })
    }

    private var trimmedQuery: String {
        router.collegeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            page
                .safeAreaInset(edge: .top, spacing: 0) {
                    if usesOwnField { searchField }
                }
                .screenTitle("Search Colleges") {
                    fieldFocused = false
                    router.isShowingSettings = true
                }
                .background(Color.appBackground.ignoresSafeArea())
                .onAppear(perform: focusFieldIfStarting)
                .onChange(of: router.collegeFocusRequest) { _, _ in
                    if usesOwnField { fieldFocused = true }
                }
                .onChange(of: router.selectedTab) { _, tab in
                    if tab == .search { focusFieldIfStarting() } else { fieldFocused = false }
                }
                .onChange(of: isMainContentVisible) { _, _ in focusFieldIfStarting() }
        }
        .accessibilityIdentifier("collegeSearch.screen")
    }

    /// Before iOS 26, entering Search with no college query starts typing;
    /// returning to a query keeps its results in view without the keyboard.
    private func focusFieldIfStarting() {
        guard usesOwnField, router.selectedTab == .search, isMainContentVisible,
              !router.isShowingSettings, (router.collegeQuery.isEmpty || router.isSearchPresented) else { return }
        Task { @MainActor in
            await Task.yield()
            guard router.selectedTab == .search, router.searchDomain == .colleges, isMainContentVisible,
                  !router.isShowingSettings, (router.collegeQuery.isEmpty || router.isSearchPresented) else { return }
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
            TextField("College name or abbreviation", text: query)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { fieldFocused = false }
                .accessibilityLabel("Search colleges")
                .accessibilityIdentifier("colleges.search.field")
            if !router.collegeQuery.isEmpty {
                Button {
                    router.collegeQuery = ""
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
                .accessibilityIdentifier("colleges.search.field.clear")
            }
        }
        .padding(.leading, 10)
        .frame(minHeight: 44)
        .background(Color.well, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        .padding(.horizontal, Metrics.page)
        .padding(.bottom, 8)
        .background(Color.appBackground)
    }


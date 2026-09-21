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

                switch state {
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                        Text("Loading \(store.calendarTerm.displayName) assignments")
                            .font(.footnote)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 32, alignment: .leading)
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("search.loading")
                case .failed(let error):
                    InlineErrorState(title: "Couldn't load assignments", message: error) {
                        await store.refreshCalendar(force: true)
                    }
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 8)
                    .accessibilityIdentifier("search.error")
                case .loaded:
                    if let data = calendarData {
                        loaded(data)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .visibleRefreshable { await store.refreshCalendar(force: true) }
    }

    private var statusStrip: some View {
        let isLoaded = assignmentState == .loaded
        return StatusStrip(
            lastUpdated: isLoaded ? store.calendarLastUpdated : nil,
            isRefreshing: store.calendarLoading && isLoaded,
            error: isLoaded ? store.calendarError : nil
        ) {
            await store.refreshCalendar(force: true)
        } control: {
            ScopePicker(
                title: "Assignment quarter",
                valueName: store.calendarTerm.displayName,
                hint: "Selects the quarter searched. Calendar shows the same quarter.",
                identifier: "search.quarter",
                groups: [
                    ChoiceGroup(title: "Fall semester", options: [TermLabel.q1, .q2].map { quarterOption($0) }),
                    ChoiceGroup(title: "Spring semester", options: [TermLabel.q3, .q4].map { quarterOption($0) }),
                ],
                selection: Binding(get: { store.calendarTerm }, set: { term in
                    guard term != store.calendarTerm else { return }
                    store.calendarTerm = term
                })
            )
        }
    }

    private func quarterOption(_ term: TermLabel) -> ChoiceOption<TermLabel> {
        ChoiceOption(value: term, title: term.displayName, identifier: "search.quarter.\(term.shortName)")
    }

    @ViewBuilder
    private func loaded(_ data: SchoolCalendarData) -> some View {
        let classCoverage = coverage(data)
        let quarter = data.term.displayName
        if trimmedQuery.isEmpty {
            EmptyStateView(title: "Search \(quarter) assignments", message: scopeText(data))
                .padding(.horizontal, Metrics.page)
                .accessibilityIdentifier("search.prompt")
        } else {
            let results = AssignmentSearch.results(in: data.assignments, query: router.searchQuery)
            if results.isEmpty {
                EmptyStateView(
                    title: "No matches in \(quarter)",
                    message: "No assignment title, class, or category matches “\(trimmedQuery)”."
                        + (classCoverage.missing.isEmpty ? "" : " Classes that couldn't load weren't searched.")
                )
                .padding(.horizontal, Metrics.page)
                .accessibilityIdentifier("search.empty")
            } else {
                GroupLabel("\(results.count) \(results.count == 1 ? "result" : "results") in \(quarter)")
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 8)
                    .accessibilityIdentifier("search.count")
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, assignment in
                        if index > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                        AssignmentSearchRow(
                            assignment: assignment,
                            onOpen: assignment.course.hasGradebookParams ? { open(assignment) } : nil,
                            identifier: "search.result.\(index)"
                        )
                    }
                }
            }
        }
        if !classCoverage.isComplete {
            coverageNote(classCoverage)
                .padding(.horizontal, Metrics.page)
                .padding(.top, 12)
        }
    }

    /// What a search covers: the assignment count, how many classes loaded,
    /// and that other quarters aren't included.
    private func scopeText(_ data: SchoolCalendarData) -> String {
        let count = data.assignments.count
        let assignments = "\(count) \(count == 1 ? "assignment" : "assignments")"
        let classes: String
        if data.eligibleCourseCount > 0, data.resolvedCourseCount < data.eligibleCourseCount {
            classes = " from \(data.resolvedCourseCount) of \(data.eligibleCourseCount) classes"
        } else if data.resolvedCourseCount > 0 {
            classes = " from \(data.resolvedCourseCount) \(data.resolvedCourseCount == 1 ? "class" : "classes")"
        } else {
            classes = ""
        }
        guard count > 0 else {
            return "Skyward lists no assignments for \(data.term.displayName)\(classes.isEmpty ? "" : " in the classes that loaded"). Other quarters aren't searched."
        }
        return "Titles, classes, and categories across \(assignments)\(classes). Other quarters aren't searched."
    }

    private func coverageNote(_ coverage: Coverage) -> some View {
        func names(_ list: [String]) -> String {
            ListFormatter.localizedString(byJoining: list.map(GPAConversionInputs.courseName))
        }
        return VStack(alignment: .leading, spacing: 0) {
            if !coverage.missing.isEmpty {
                note("Assignments couldn't load for \(names(coverage.missing)). They aren't searched.")
            }
            if !coverage.saved.isEmpty {
                note("Couldn't refresh \(names(coverage.saved)). Their saved assignments are searched.")
            }
            Button("Retry") {
                Task { await store.refreshCalendar(force: true) }
            }
            .buttonStyle(ActionTextButtonStyle())
            .disabled(store.calendarLoading)
            .accessibilityLabel("Retry loading assignments")
            .accessibilityIdentifier("search.coverage.retry")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.coverage")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    /// Opens the exact assignment in Courses on its quarter, exactly as
    /// Calendar does; the row's hint names that quarter. What-if work stays
    /// in the class.
    private func open(_ assignment: CalendarAssignment) {
        fieldFocused = false
        guard let course = SchoolCalendar.eligibleCourses(store.courses ?? [], term: assignment.term)
            .first(where: { $0.id == assignment.course.id }) else { return }
        store.selectedTerm = assignment.term
        router.showAssignment(course: course, term: assignment.term, assignmentID: assignment.routeID)
    }
}

// MARK: - Row

/// A matching assignment as an open row: title, class, then its school date,
/// category and Skyward's own Missing, Absent or No count flags.
private struct AssignmentSearchRow: View {
    var assignment: CalendarAssignment
    var onOpen: (() -> Void)?
    var identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Status: Hashable {
        var text: String
        var isMissing = false
        var isAbsent = false
    }

    private var title: String {
        let text = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Untitled assignment" : text
    }

    private var courseName: String { GPAConversionInputs.courseName(assignment.course.courseName) }

    private var category: String? {
        let text = assignment.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Skyward's school date; an unreadable one is shown as written.
    private var dateText: String {
        if let iso = assignment.date,
           let parts = AttendanceSchoolDate.components(iso),
           let date = Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month,
                                                                 day: parts.day, hour: 12)) {
            if parts.year == Calendar.current.component(.year, from: Date()) {
                return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            }
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        let source = assignment.sourceDate.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? "No date in Skyward" : "Date in Skyward: \(source)"
    }

    /// Only Skyward's own flags; nothing is inferred from attendance.
    private var statuses: [Status] {
        let types = Set(assignment.meta.map(\.type))
        var result: [Status] = []
        if types.contains("missing") { result.append(Status(text: "Missing", isMissing: true)) }
        if types.contains("absent") { result.append(Status(text: "Absent", isAbsent: true)) }
        if types.contains("noCount") { result.append(Status(text: "No count")) }
        return result
    }

    private var spokenLabel: String {
        ([title, courseName, dateText] + [category].compactMap { $0 } + statuses.map(\.text)).joined(separator: ", ")
    }

    var body: some View {
        if let onOpen {
            Button(action: onOpen) {
                content(showsChevron: true)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(spokenLabel)
            .accessibilityHint("Opens this assignment in Courses for \(assignment.term.displayName)")
            .accessibilityIdentifier(identifier)
        } else {
            content(showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
                .accessibilityIdentifier(identifier)
        }
    }

    private func content(showsChevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                Text(courseName)
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                detailLine
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron { RowChevron() }
        }
        .padding(.horizontal, Metrics.page)
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var detailLine: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) { detailParts }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) { detailParts }
        }
    }

    /// Status as plain words, colored as in Calendar: only Missing and
    /// Absent take a color.
    @ViewBuilder
    private var detailParts: some View {
        Text(dateText)
            .font(.footnote)
            .foregroundStyle(Color.muted)
        if let category {
            Text(category)
                .font(.footnote)
                .foregroundStyle(Color.muted)
        }
        ForEach(statuses, id: \.self) { status in
            Text(status.text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(
                    status.isMissing ? Color.gradeAttention : (status.isAbsent ? Color.gradeWarning : Color.ink)
                )
        }
    }
}

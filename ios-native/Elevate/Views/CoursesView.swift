import SwiftUI

struct CoursesView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isMainContentVisible) private var isMainContentVisible
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var periodGutter: CGFloat = 28
    @State private var showingConnect = false
    @State private var showingTermSelector = false
    @State private var manualClasses: [ManualClass] = []
    @State private var displayedCourseIDs: Set<String> = []

    var body: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.coursesPath) {
            Group {
                if !store.canShowData {
                    LoginPromptView(message: "Connect your Skyward account to see your classes, grades, and assignments.") {
                        showingConnect = true
                    }
                } else if let error = store.coursesError, store.courses == nil {
                    ErrorStateView(title: "Couldn't load courses", message: error) {
                        await store.refreshCourses(force: true)
                    }
                } else {
                    courseList
                }
            }
            .screenTitle("Courses") { router.isShowingSettings = true }
            .background(Color.appBackground.ignoresSafeArea())
            .accessibilityIdentifier("courses.screen")
            .sheet(isPresented: $showingConnect) {
                SkywardConnectSheet()
            }
            .navigationDestination(for: CoursesRoute.self) { route in
                // The root hides the bar for its own header; pushed screens
                // keep their centered inline titles and Back.
                Group {
                    switch route {
                    case .course(let course):
                        ClassDetailView(course: course)
                    case .assignment(let course, let term, let token, let requestID):
                        ClassDetailView(course: course, targetAssignmentID: token, targetTerm: term)
                            .task(id: assignmentNavigationTrigger) {
                                guard assignmentNavigationTrigger.canNavigate, router.coursesPath.last == route else { return }
                                router.acknowledgeAssignment(route)
                            }
                            .id(requestID)
                    case .gpa:
                        GPAView()
                    case .gradeGoal(let course, let term):
                        GradeGoalView(course: course, term: term)
                    case .missingWork:
                        MissingWorkView()
                    case .gpaConverter:
                        GPAConversionView()
                    case .gpaConverterYear(let year, let policy):
                        GPAConversionYearView(year: year, policy: policy)
                    case .collegeProfiles:
                        CollegeComparisonView()
                    case .collegeProfile(let id):
                        if let profile = CollegeProfileCatalog.profiles.first(where: { $0.id == id }) {
                            CollegeProfileDetailView(profile: profile)
                        } else {
                            CollegeComparisonView()
                        }
                    case .gradeChanges:
                        GradeChangesView()
                    }
                }
                .toolbar(.visible, for: .navigationBar)
            }
            .onAppear(perform: observeDisplayedGrades)
            .onChange(of: store.courses) { _, _ in observeDisplayedGrades() }
            .onChange(of: store.selectedTerm) { _, _ in observeDisplayedGrades() }
            .onChange(of: router.coursesPath.isEmpty) { _, isEmpty in
                observeDisplayedGrades()
                // A class may have recorded assignment changes while open.
                if isEmpty, store.planning.accountScope == store.localAccountScope {
                    store.planning.reloadHistory()
                }
            }
            .onChange(of: router.selectedTab) { _, _ in observeDisplayedGrades() }
            .onChange(of: scenePhase) { _, _ in observeDisplayedGrades() }
            .onChange(of: router.isShowingSettings) { _, _ in observeDisplayedGrades() }
            .onChange(of: showingConnect) { _, _ in observeDisplayedGrades() }
            .onChange(of: showingTermSelector) { _, _ in observeDisplayedGrades() }
            .onChange(of: isMainContentVisible) { _, _ in observeDisplayedGrades() }
            .onChange(of: store.notifications.accountScope) { _, _ in observeDisplayedGrades() }
        }
        .task(id: assignmentNavigationTrigger) {
            let trigger = assignmentNavigationTrigger
            guard trigger.canNavigate, let id = trigger.requestID else { return }
            await Task.yield()
            guard !Task.isCancelled, assignmentNavigationTrigger == trigger else { return }
            router.applyPendingAssignment(id)
        }
    }

    private struct AssignmentNavigationTrigger: Hashable {
        let requestID: UUID?
        let accountRevision: Int
        let pathIsEmpty: Bool
        let canNavigate: Bool
    }

    private var assignmentNavigationTrigger: AssignmentNavigationTrigger {
        AssignmentNavigationTrigger(requestID: router.pendingAssignment?.id,
            accountRevision: store.accountRevision, pathIsEmpty: router.coursesPath.isEmpty,
            canNavigate: router.selectedTab == .courses && scenePhase == .active && isMainContentVisible
                && store.canShowData && !router.isShowingSettings && !showingConnect && !showingTermSelector)
    }

    /// Background hydration and hidden navigation destinations are not views
    /// of the Courses list. Only presented official grades advance history;
    /// the shared Settings sheet covers the list like any other sheet.
    private func observeDisplayedGrades() {
        guard scenePhase == .active, router.selectedTab == .courses,
              router.coursesPath.isEmpty, isMainContentVisible,
              !router.isShowingSettings, !showingConnect, !showingTermSelector else { return }
        store.observeVisibleCourseGrades(displayedCourseIDs: displayedCourseIDs)
    }

    private var isFirstLoad: Bool {
        #if DEBUG
        if store.isUsingSampleData, ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-PreviewCourseLoading") { return true }
        #endif
        return store.coursesLoading && store.courses == nil
    }

    /// Divider inset: hairlines start where the class names start.
    private var rowDividerInset: CGFloat {
        Metrics.page + (dynamicTypeSize.isAccessibilitySize ? 0 : periodGutter)
    }

    /// Space between the last class and the tab bar when the list fills the
    /// screen.
    private static let bottomGap: CGFloat = 16

    /// The height the class list fills: the scroll view's visible height,
    /// already inside the root header and tab bar. At accessibility sizes
    /// rows keep their natural heights and the list scrolls.
    private func fillHeight(_ viewportHeight: CGFloat) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 0 : max(0, viewportHeight - Self.bottomGap)
    }

    private var courseList: some View {
        @Bindable var store = store
        return GeometryReader { viewport in
            ScrollView {
                // The control line and GPA line keep their heights; a full
                // schedule's rows share what is left of the screen, so the
                // list ends just above the tab bar rather than partway down.
                ViewportFillStack(minHeight: fillHeight(viewport.size.height)) {
                    StatusStrip(
                        lastUpdated: store.coursesLastUpdated,
                        isRefreshing: store.coursesLoading && store.courses != nil,
                        error: store.courses != nil ? store.coursesError : nil
                    ) {
                        await store.refreshCourses(force: true)
                    } control: {
                        TermSelector(selection: $store.selectedTerm) { showingTermSelector = $0 }
                    }
                    .padding(.horizontal, Metrics.page)

                    Group {
                        if isFirstLoad { gpaPlaceholder } else { gpaSummary }
                    }
                    .padding(.top, 4)
                    InsetDivider()
                        .padding(.horizontal, Metrics.page)
                    missingWorkLine
                    Rule()
                        .padding(.horizontal, Metrics.page)
                        .padding(.bottom, 4)

                    courseRows(in: viewport.frame(in: .global))
                }
                .padding(.bottom, Self.bottomGap)
            }
            .visibleRefreshable {
                await store.refreshCourses(force: true)
            }
            .onAppear(perform: loadManualClasses)
            .onChange(of: store.currentGradeLevel) { _, _ in loadManualClasses() }
        }
    }

    /// Each class is its own child of the fill layout, so every row receives
    /// the same share of spare height on top of its natural height.
    @ViewBuilder
    private func courseRows(in viewport: CGRect) -> some View {
        let courses = store.visibleCourses
        if isFirstLoad {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 0) {
                    if index > 0 { InsetDivider(leading: rowDividerInset).padding(.trailing, Metrics.page) }
                    CourseRowPlaceholder(index: index, periodGutter: periodGutter)
                }
                .fillsViewport()
            }
        } else if courses.isEmpty {
            EmptyStateView(
                title: "No classes",
                message: "Skyward has no classes for \(store.selectedTerm.displayName)."
            )
            .padding(.horizontal, Metrics.page)
        } else {
            ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                VStack(spacing: 0) {
                    if index > 0 { InsetDivider(leading: rowDividerInset).padding(.trailing, Metrics.page) }
                    NavigationLink(value: CoursesRoute.course(course)) {
                        CourseRow(course: course, term: store.selectedTerm, periodGutter: periodGutter,
                                  gradeChange: store.courseGradeDelta(for: course.id), gradeViewport: viewport) { visible in
                            if visible { displayedCourseIDs.insert(course.id) }
                            else { displayedCourseIDs.remove(course.id) }
                            observeDisplayedGrades()
                        }
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("course.row.\(course.corNumId)")
                }
                .fillsViewport()
            }
        }
    }

    // MARK: - GPA summary

    private func loadManualClasses() {
        let level = store.currentGradeLevel
        manualClasses = level.gradeYear == nil ? [] : WhatIfStore.manualClasses(gradeLevel: level)
    }

    /// The current year's GPA for the selected term, read from the same table
    /// as the GPA screen. When that term has no GPA yet, the latest posted
    /// term is shown and named.
    private var summary: (label: String, data: GPAData, isSelectedTerm: Bool)? {
        let level = store.currentGradeLevel
        let data = GPAReport.termGPAs(
            level: level,
            courses: store.courses(for: level),
            manualClasses: manualClasses
        )
        let key = GPAReport.key(for: store.selectedTerm)
        if let value = data[key] {
            return (key, value, true)
        }
        if let latest = GPAReport.latest(in: data) {
            return (latest.label, latest.data, false)
        }
        return nil
    }

    private var gpaSummary: some View {
        let shown = summary
        let caption: String
        if let shown {
            caption = shown.isSelectedTerm
                ? GPAReport.termName(shown.label)
                : "Latest posted: \(GPAReport.termName(shown.label))"
        } else {
            caption = "Not posted yet"
        }

        return Button {
            // The GPA screen opens on the same year this line summarizes.
            store.selectedGradeLevel = store.currentGradeLevel
            router.coursesPath.append(.gpa)
        } label: {
            gpaLine {
                if shown?.isSelectedTerm != true {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } values: { alignment in
                if let data = shown?.data {
                    summaryValues(data, alignment: alignment)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GPA, \(caption)")
        .accessibilityValue(shown.map {
            "Weighted \(GradeFormat.gpa($0.data.weighted)), unweighted \(GradeFormat.gpa($0.data.unweighted))"
        } ?? "")
        .accessibilityHint("Opens GPA history")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("courses.gpa")
    }

}

struct ClassCardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var course: UnifiedCourseData
    var term: TermLabel
    var rowHeight: CGFloat = 70

    private var usesStackedLayout: Bool { dynamicTypeSize >= .xxxLarge }

    private var termScore: Double? {
        course.currentScores.first { $0.bucket == bucketLabel }?.score
            ?? AcademicScoreValue.finiteDouble(course.historicalGrades[term.historicalKey])
    }

    private var bucketLabel: String {
        switch term {
        case .q1: return "Q1"; case .q2: return "Q2"; case .sm1: return "S1"
        case .q3: return "Q3"; case .q4: return "Q4"; case .sm2: return "S2"
        }
    }

    var body: some View {
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: 10) {
                    courseDetails
                    HStack {
                        Spacer()
                        gradeIndicator
                        chevron
                    }
                }
            } else {
                HStack(spacing: 12) {
                    courseDetails
                    Spacer(minLength: 8)
                    gradeIndicator
                    chevron
                }
            }
        }
        .frame(minHeight: rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityValue(termScore.map { String(format: "%.0f percent", $0) } ?? "No grade")
    }

    private var courseDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ClassNameFormatter.format(course.courseName.replacingOccurrences(of: " ", with: "_")))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(usesStackedLayout ? nil : 1)
            if let instructor = course.instructor, !instructor.isEmpty {
                Text(ClassNameFormatter.format(instructor.replacingOccurrences(of: " ", with: "_")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(usesStackedLayout ? nil : 1)
            }
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var gradeIndicator: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(termScore.map { String(format: "%.0f%%", $0) } ?? "No grade")
                .font(.headline.monospacedDigit())
                .foregroundStyle(termScore == nil ? .secondary : Color.highlightText)
        } else {
            GradeProgressRing(score: termScore)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 16)
            .accessibilityHidden(true)
    }

}

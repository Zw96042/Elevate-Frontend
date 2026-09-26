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

    /// The line's fixed heading is real text; the caption and figures, which
    /// depend on the response, are bars on their own type styles. This is the
    /// screen's one loading announcement; the placeholder rows are hidden.
    private var gpaPlaceholder: some View {
        gpaLine(showsChevron: false) {
            EmptyView()
        } values: { alignment in
            VStack(alignment: alignment, spacing: 2) {
                SkeletonText(.figure(.title3), length: 4)
                SkeletonText(.figure(.footnote, weight: .regular), length: 12, tone: .secondary)
            }
        }
        .loadingPlaceholder("Loading courses")
        .accessibilityIdentifier("courses.loading")
    }

    /// Shared geometry prevents the loading summary from shifting the list.
    private func gpaLine<Caption: View, Values: View>(
        showsChevron: Bool = true,
        @ViewBuilder caption: () -> Caption,
        @ViewBuilder values: (HorizontalAlignment) -> Values
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weighted GPA")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink)
                caption()
                if dynamicTypeSize.isAccessibilitySize {
                    values(.leading)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize {
                values(.trailing)
            }
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.faint)
                .opacity(showsChevron ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Metrics.page)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
    }

    // MARK: - Missing work

    /// Opens Skyward's missing flags for the selected term's quarter. A count
    /// shows only when Calendar's saved data already covers every class in
    /// that quarter; otherwise the line names the quarter and loads nothing.
    private var missingWorkLine: some View {
        let quarter = SchoolCalendar.quarter(for: store.selectedTerm)
        let count = knownMissingCount(quarter)
        let countText = count.map { $0 == 0 ? "None" : "\($0)" }
        return Button {
            router.coursesPath.append(.missingWork)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Missing work")
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    if quarter != store.selectedTerm {
                        Text(quarter.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Color.muted)
                    }
                    if dynamicTypeSize.isAccessibilitySize, let countText {
                        Text(countText)
                            .font(.figure(.body))
                            .foregroundStyle(count == 0 ? Color.muted : Color.gradeAttention)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                if !dynamicTypeSize.isAccessibilitySize, let countText {
                    Text(countText)
                        .font(.figure(.body))
                        .foregroundStyle(count == 0 ? Color.muted : Color.gradeAttention)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.faint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Metrics.page)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Missing work, \(quarter.displayName)")
        .accessibilityValue(count.map { $0 == 0 ? "None marked" : "\($0) marked missing" } ?? "")
        .accessibilityHint("Lists assignments Skyward marks missing")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("courses.missingWork")
    }

    /// Counts only Skyward's missing flags, and only from saved Calendar data
    /// for this quarter that resolved every eligible class without a failure.
    private func knownMissingCount(_ quarter: TermLabel) -> Int? {
        guard let data = store.calendarQuarter(quarter).data, data.term == quarter, data.failedCourseNames.isEmpty,
              let courses = store.courses else { return nil }
        let eligible = Set(SchoolCalendar.eligibleCourses(courses, term: quarter).map(\.id))
        guard !eligible.isEmpty, eligible.isSubset(of: data.resolvedCourseIDs) else { return nil }
        return data.assignments.filter { assignment in
            eligible.contains(assignment.course.id) && assignment.meta.contains { $0.type == "missing" }
        }.count
    }

    private func summaryValues(_ data: GPAData, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(GradeFormat.gpa(data.weighted))
                .font(.figure(.title3))
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText(value: data.weighted))
            Text("Unweighted \(GradeFormat.gpa(data.unweighted))")
                .font(.figure(.footnote, weight: .regular))
                .foregroundStyle(Color.muted)
                .contentTransition(.numericText(value: data.unweighted))
        }
        .lineLimit(1)
    }
}

extension UnifiedCourseData {
    /// The grade Skyward reports for a term: the current score when posted,
    /// otherwise the historical report-card value.
    func termScore(_ term: TermLabel) -> Double? {
        GradeChangeTracker.officialScore(for: self, term: term)
    }

    /// Every term Skyward has a grade for, for the term picker.
    var termScores: [TermLabel: Double] {
        var scores: [TermLabel: Double] = [:]
        for term in TermLabel.allCases {
            if let score = termScore(term), score.isFinite { scores[term] = score }
        }
        return scores
    }
}

/// One course as an open row: the period in a narrow gutter, the class and
/// teacher, and the term grade set inside a thin ring that traces its share
/// of 100, with any change since last viewed just before it. At
/// accessibility sizes the period joins the details and the grade moves
/// beneath them.
/// Teacher names go through `PersonName`, never the course-title formatter.
struct CourseRow: View {
    var course: UnifiedCourseData
    var term: TermLabel
    var periodGutter: CGFloat
    /// Signed change in the official course grade since the student last
    /// saw it, supplied by the caller; nil shows nothing.
    var gradeChange: Double? = nil
    var gradeViewport: CGRect = .zero
    var onGradeVisibilityChange: (Bool) -> Void = { _ in }

    private var termScore: Double? { course.termScore(term) }

    /// The change, when it is large enough to show as a compact figure.
    private var shownChange: Double? {
        guard let gradeChange, gradeChange.isFinite, abs(gradeChange) >= 0.05 else { return nil }
        return gradeChange
    }

    private var name: String {
        ClassNameFormatter.format(course.courseName.replacingOccurrences(of: " ", with: "_"))
    }

    private var instructor: String? {
        guard let instructor = course.instructor.map(PersonName.display), !instructor.isEmpty else { return nil }
        return instructor
    }

    var body: some View {
        CourseRowLayout(period: course.period, name: name, instructor: instructor,
                        periodGutter: periodGutter, score: termScore, change: changeText,
                        gradeViewport: gradeViewport, onGradeVisibilityChange: onGradeVisibilityChange)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityName)
            .accessibilityValue(accessibilityValue)
    }

    /// "+1" or "−0.5": the sign carries the direction, so it stays muted.
    private var changeText: String? {
        shownChange.map { ($0 > 0 ? "+" : "−") + GradeFormat.compact(abs($0)) }
    }

    private var accessibilityValue: String {
        let grade = GradeFormat.spoken(termScore)
        guard let shownChange else { return grade }
        let amount = GradeFormat.compact(abs(shownChange))
        let unit = amount == "1" ? "point" : "points"
        let direction = shownChange > 0 ? "up" : "down"
        return "\(grade), \(direction) \(amount) \(unit) since you last checked"
    }

    private var accessibilityName: String {
        var parts = [name]
        if let period = course.period { parts.append("period \(period)") }
        if let instructor { parts.append(instructor) }
        return parts.joined(separator: ", ")
    }
}

/// The real and loading course rows share type, columns and viewport behavior.
private struct CourseRowLayout: View {
    /// Approximate name and teacher lengths, in figures, of a loading row.
    struct Placeholder {
        var name: Int
        var instructor: Int
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var period: Int?
    var name: String
    var instructor: String?
    var periodGutter: CGFloat
    var score: Double?
    var change: String?
    /// A loading row: bars on the name and teacher lines, an empty period
    /// gutter, and the ring's bare track.
    var placeholder: Placeholder? = nil
    var gradeViewport: CGRect = .zero
    var onGradeVisibilityChange: (Bool) -> Void = { _ in }

    /// Room above and below the ring. At the default size the ring plus
    /// this clearance matches the name and teacher lines with the usual row
    /// padding, so neither one sets the row taller than the other.
    private static let ringClearance: CGFloat = 7

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    details
                    grade
                }
                .padding(.vertical, Metrics.rowPadding - Self.ringClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 0) {
                    Text(period.map(String.init) ?? "")
                        .font(.figure(.subheadline, weight: .regular))
                        .foregroundStyle(Color.muted)
                        .frame(width: periodGutter, alignment: .leading)
                    details
                        .padding(.vertical, Metrics.rowPadding - Self.ringClearance)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Rings keep the trailing edge, so grades and arcs line
                    // up from row to row whether or not a change shows.
                    grade
                        .padding(.leading, 12)
                }
            }
        }
        .padding(.horizontal, Metrics.page)
        .padding(.vertical, Self.ringClearance)
        // Natural height when unconstrained; takes any spare height the
        // course list gives it, with the content centered.
        .frame(maxHeight: .infinity)
    }

    /// The ring, and the change beside it rather than squeezed into the
    /// hole: before the ring in the trailing column, after it once the
    /// grade sits beneath the details. Both stop growing at the second
    /// accessibility size, where the ring is already wide for the row;
    /// names and teachers keep growing.
    private var grade: some View {
        HStack(spacing: 8) {
            if !dynamicTypeSize.isAccessibilitySize { changeLabel }
            GradeRing(score: score, isLoading: placeholder != nil)
                .onGeometryChange(for: Bool.self) { geometry in
                    let frame = geometry.frame(in: .global)
                    return gradeViewport.contains(CGPoint(x: frame.midX, y: frame.midY))
                } action: { onGradeVisibilityChange($0) }
            if dynamicTypeSize.isAccessibilitySize { changeLabel }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// Muted at every size; the sign carries the direction. The row speaks
    /// the change in its accessibility value.
    @ViewBuilder
    private var changeLabel: some View {
        if let change {
            Text(change)
                .font(.figure(.footnote, weight: .regular))
                .foregroundStyle(Color.muted)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var details: some View {
        if let placeholder {
            VStack(alignment: .leading, spacing: 2) {
                if dynamicTypeSize.isAccessibilitySize {
                    SkeletonText(.footnote, length: 6, tone: .secondary)
                }
                SkeletonText(.body.weight(.medium), length: placeholder.name)
                SkeletonText(.subheadline, length: placeholder.instructor, tone: .secondary)
            }
        } else {
            loadedDetails
        }
    }

    private var loadedDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            if dynamicTypeSize.isAccessibilitySize, let period = period {
                Text("Period \(period)")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
            }
            Text(name)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let instructor {
                Text(instructor)
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize >= .xxxLarge ? nil : 1)
            }
        }
    }

}

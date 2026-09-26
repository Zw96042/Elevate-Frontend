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
    }

    private var courseList: some View {
        @Bindable var store = store
        return GeometryReader { proxy in
            let courseCount = max(store.visibleCourses.count, 1)
            let availableForRows = max(proxy.size.height - 49, 0)
            let rowHeight = min(max(availableForRows / CGFloat(courseCount), 70), 82)

            ScrollView {
                LazyVStack(spacing: 0) {
                    TermPickerPill(selectedTerm: $store.selectedTerm, showsDescriptor: false)

                    if store.coursesError != nil, store.courses != nil {
                        StaleDataBanner(lastUpdated: store.coursesLastUpdated) {
                            await store.refreshCourses(force: true)
                        }
                        .padding(.vertical, 12)
                    }

                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.32))
                        .frame(height: 0.5)

                    if store.coursesLoading && store.courses == nil {
                        ForEach(0..<7, id: \.self) { _ in
                            SkeletonRow(height: rowHeight)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Loading courses")
                    } else if store.visibleCourses.isEmpty {
                        EmptyStateView(
                            systemImage: "graduationcap",
                            title: "No courses found",
                            subtitle: "Try selecting a different term"
                        )
                    } else {
                        ForEach(store.visibleCourses) { course in
                            NavigationLink(value: course) {
                                VStack(spacing: 0) {
                                    ClassCardView(
                                        course: course,
                                        term: store.selectedTerm,
                                        rowHeight: rowHeight
                                    )
                                    Rectangle()
                                        .fill(Color(uiColor: .separator).opacity(0.32))
                                        .frame(height: 0.5)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .contentMargins(.vertical, 0, for: .scrollContent)
            .refreshable {
                await store.refreshCourses(force: true)
            }
            .background(Color.appBackground)
        }
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

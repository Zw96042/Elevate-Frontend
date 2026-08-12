import SwiftUI

struct CoursesView: View {
    @Environment(AppStore.self) private var store
    @State private var showingSettings = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                if !store.canShowData {
                    LoginPromptView(message: "Connect your Skyward account in Settings to view courses.") {
                        showingSettings = true
                    }
                } else if let error = store.coursesError, store.courses == nil {
                    ErrorStateView(title: "Couldn't load courses", message: error) {
                        await store.refreshCourses(force: true)
                    }
                } else {
                    courseList
                }
            }
            .navigationTitle("Courses")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .navigationDestination(for: UnifiedCourseData.self) { course in
                ClassDetailView(course: course)
            }
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

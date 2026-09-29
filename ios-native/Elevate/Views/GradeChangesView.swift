import SwiftUI

/// Official changes Elevate found in fresh, validated Skyward responses,
/// newest first and grouped by the day each was found. Times are when
/// Elevate found a change, never when a teacher made it. The history is
/// separate from "since you last checked" deltas and from grade alerts, and
/// What-if never enters it. Synthetic journal fixtures are DEBUG-only.
struct GradeChangesView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The account this page opened for. History is shown and cleared only
    /// while it is still the current account.
    @State private var openedScope: String?
    @State private var didCaptureScope = false
    /// A class ID; nil shows every class.
    @State private var courseFilter: String?
    @State private var confirmingClear = false
    @State private var clearRevision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.bottom, 32)
        }
        .softScrollEdges()
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Grade Changes")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("history.screen")
        .onAppear {
            if !didCaptureScope {
                openedScope = store.localAccountScope
                didCaptureScope = true
            }
            if isCurrentScope { store.planning.reloadHistory() }
        }
        .alert("Clear grade changes?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive, action: clearHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the changes Elevate found on this iPhone. Skyward isn't changed.")
        }
        .sensoryFeedback(.success, trigger: clearRevision)
        .onChange(of: store.accountRevision) { _, _ in
            confirmingClear = false
            courseFilter = nil
        }
    }

    // MARK: - Scope

    /// The planning store holds this account's history, and it is the
    /// account the page opened for.
    private var isCurrentScope: Bool {
        guard store.canShowData, let scope = store.localAccountScope,
              store.planning.accountScope == scope else { return false }
        return !didCaptureScope || openedScope == scope
    }

    private var events: [GradeJournalEvent] {
        isCurrentScope ? store.planning.gradeChanges : []
    }

    /// Current classes in Courses order, then any other class with a change.
    private var classOptions: [(id: String, name: String)] {
        var seen: Set<String> = []
        var options: [(id: String, name: String)] = []
        for course in store.courses(for: store.currentGradeLevel)
        where course.hasGradebookParams && seen.insert(course.id).inserted {
            options.append((id: course.id, name: GradeChangeText.course(course.courseName)))
        }
        var others: [(id: String, name: String)] = []
        for event in events where seen.insert(event.courseID).inserted {
            others.append((id: event.courseID, name: GradeChangeText.course(event.courseName)))
        }
        return options + others.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A filter whose class has left the list shows every class.
    private var shownFilter: String? {
        guard let courseFilter, classOptions.contains(where: { $0.id == courseFilter }) else { return nil }
        return courseFilter
    }

    private var shownEvents: [GradeJournalEvent] {
        guard let filter = shownFilter else { return events }
        return events.filter { $0.courseID == filter }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !isCurrentScope {
            EmptyStateView(
                title: "Grade changes aren't available",
                message: "Connect your Skyward account to see official changes Elevate finds."
            )
            .padding(.horizontal, Metrics.page)
            .accessibilityIdentifier("history.unavailable")
        } else if store.planning.historyUnavailable {
            VStack(alignment: .leading, spacing: 0) {
                EmptyStateView(
                    title: "Grade changes can't be read",
                    message: "The saved history on this iPhone couldn't be read. Clearing it starts a new one."
                )
                .accessibilityIdentifier("history.unreadable")
                clearButton
            }
            .padding(.horizontal, Metrics.page)
        } else if events.isEmpty {
            EmptyStateView(
                title: "No changes found yet",
                message: "Elevate starts with a silent first check, then lists changes in official grades it finds later."
            )
            .padding(.horizontal, Metrics.page)
            .accessibilityIdentifier("history.empty")
            footer
        } else {
            HStack(spacing: 0) {
                filterPicker
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.page)

            Text("Times show when Elevate found a change, not when a teacher made it.")
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.page)
                .padding(.top, 4)
                .accessibilityIdentifier("history.note")

            let shown = shownEvents
            if shown.isEmpty {
                EmptyStateView(title: "No changes for \(filterName)")
                    .padding(.horizontal, Metrics.page)
                    .accessibilityIdentifier("history.filterEmpty")
            } else {
                dayGroups(shown)
            }
            footer
        }
    }

    private var filterName: String {
        guard let filter = shownFilter else { return "All classes" }
        return classOptions.first { $0.id == filter }?.name ?? "All classes"
    }

    private var filterPicker: some View {
        let all = ChoiceOption<String?>(value: nil, title: "All classes", identifier: "history.filter.all")
        let classes = classOptions.enumerated().map { index, option in
            ChoiceOption<String?>(value: option.id, title: option.name, identifier: "history.filter.\(index)")
        }
        return ScopePicker(
            title: "Class",
            valueName: filterName,
            hint: "Shows changes for one class or all classes",
            identifier: "history.filter",
            groups: [ChoiceGroup(title: nil, options: [all] + classes)],
            selection: Binding(get: { shownFilter }, set: { value in
                Motion.perform(Motion.replace(reduceMotion)) { courseFilter = value }
            })
        )
    }

    private struct DayGroup: Identifiable {
        var id: Date
        var title: String
        var events: [GradeJournalEvent]
    }

    /// Days in the order found, newest first; events keep the history's order.
    private func groups(_ events: [GradeJournalEvent]) -> [DayGroup] {
        let calendar = Calendar.current
        var groups: [DayGroup] = []
        for event in events {
            let day = calendar.startOfDay(for: event.observedAt)
            if let last = groups.indices.last, groups[last].id == day {
                groups[last].events.append(event)
            } else {
                groups.append(DayGroup(id: day, title: Self.dayTitle(day), events: [event]))
            }
        }
        return groups
    }


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

    /// "Today", "Yesterday", or "Friday, Oct 2".
    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if calendar.isDate(day, equalTo: Date(), toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    private func dayGroups(_ events: [GradeJournalEvent]) -> some View {
        ForEach(Array(groups(events).enumerated()), id: \.element.id) { dayIndex, group in
            GroupLabel(group.title)
                .padding(.horizontal, Metrics.page)
                .padding(.top, dayIndex == 0 ? 16 : 24)
                .accessibilityIdentifier("history.day.\(dayIndex)")
            ForEach(Array(group.events.enumerated()), id: \.element.id) { row, event in
                if row > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                GradeChangeRow(
                    text: GradeChangeText(event),
                    onOpen: openAction(for: event),
                    identifier: "history.row.\(dayIndex).\(row)"
                )
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Elevate keeps up to 500 changes from the last 90 days on this iPhone. Assignment changes appear after Elevate loads that class.")
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("history.footer")
            clearButton
        }
        .padding(.horizontal, Metrics.page)
        .padding(.top, 24)
    }

    private var clearButton: some View {
        Button("Clear history") { confirmingClear = true }
            .buttonStyle(ActionTextButtonStyle())
            .accessibilityHint("Removes the changes Elevate found on this iPhone")
            .accessibilityIdentifier("history.clear")
    }

    // MARK: - Actions

    /// The class's current record, only when it still offers that term.
    private func openAction(for event: GradeJournalEvent) -> (() -> Void)? {
        guard let course = store.courses?.first(where: { $0.id == event.courseID }),
              course.hasGradebookParams, course.availableTerms.contains(event.term) else { return nil }
        return {
            store.selectedTerm = event.term
            router.coursesPath.append(.course(course))
        }
    }

    /// Writes only to the account this page opened for, while it is current.
    private func clearHistory() {
        guard didCaptureScope, let expected = openedScope, store.localAccountScope == expected,
              store.planning.accountScope == expected else { return }
        store.planning.clearHistory(expectedAccountScope: store.localAccountScope)
        courseFilter = nil
        if !store.planning.historyUnavailable, store.planning.gradeChanges.isEmpty {
            clearRevision += 1
        }
    }
}

// MARK: - Entry summary

/// The Courses footer row's subtitle. Nothing from history shows unless the
/// planning store holds the current account's history.
enum GradeChangeSummary {
    static let defaultSubtitle = "Official changes Elevate finds"

    @MainActor
    static func entrySubtitle(_ store: AppStore) -> String {
        guard store.canShowData, let scope = store.localAccountScope,
              store.planning.accountScope == scope else { return defaultSubtitle }
        if store.planning.historyUnavailable { return "Saved changes can't be read" }
        guard let latest = store.planning.gradeChanges.max(by: { $0.observedAt < $1.observedAt }) else {
            return defaultSubtitle
        }
        return "Latest: \(GradeChangeText.course(latest.courseName)), found \(day(latest.observedAt))"
    }

    private static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Row text

/// Everything a change row says, written so it stays true when Skyward
/// renames an assignment (it reads as first seen) and never claiming when a
/// teacher acted.
struct GradeChangeText {
    struct Phrase: Hashable {
        var text: String
        var isMissing = false
    }

    var title: String
    var detail: String
    var phrases: [Phrase] = []
    var value: String
    var valueIsFigure = true
    var secondary: String?
    var spoken: String

    static func course(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Class" }
        return ClassNameFormatter.format(text.replacingOccurrences(of: " ", with: "_"))
    }

    init(_ event: GradeJournalEvent) {
        let course = Self.course(event.courseName)
        let term = event.term.displayName
        let time = event.observedAt.formatted(date: .omitted, time: .shortened)

        switch event.kind {
        case .averageChanged:
            title = course
            if event.currentScore == nil {
                detail = "\(term) average no longer shown, found \(time)"
                value = "No grade"
                valueIsFigure = false
                secondary = event.previousScore.map { "was \(GradeFormat.twoDecimals($0))" }
                spoken = [course, "\(term) average no longer shown",
                          event.previousScore.map { "was \(GradeFormat.twoDecimals($0))" }, "found \(time)"]
                    .compactMap { $0 }.joined(separator: ", ")
            } else if event.previousScore == nil {
                let posted = GradeFormat.twoDecimals(event.currentScore)
                detail = "\(term) average posted, found \(time)"
                value = posted
                spoken = "\(course), \(term) average posted, \(posted), found \(time)"
            } else {
                let current = event.currentScore ?? 0, previous = event.previousScore ?? 0
                let change = current - previous
                let shown = GradeFormat.twoDecimals(current)
                detail = "\(term) average, found \(time)"
                value = shown
                secondary = GradeFormat.signedChange(change)
                let direction: String
                if abs(change) < 0.005 {
                    direction = "changed from"
                } else {
                    direction = "\(change > 0 ? "up" : "down") \(GradeFormat.twoDecimals(abs(change))) from"
                }
                spoken = "\(course), \(term) average, \(shown), \(direction) \(GradeFormat.twoDecimals(previous)), found \(time)"
            }

        case .assignmentAdded, .assignmentChanged:
            let trimmed = event.assignmentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = trimmed.isEmpty ? "Untitled assignment" : trimmed
            let category = event.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let context = ([course, term] + (category.isEmpty ? [] : [category])).joined(separator: ", ")
            let current = Self.score(event.currentAssignment)
            let previous = Self.score(event.previousAssignment)
            title = name
            value = current?.text ?? "Not graded"
            valueIsFigure = current != nil
            if event.kind == .assignmentAdded {
                // Skyward has no stable assignment ID, so a renamed row is
                // also first seen here; this never claims a teacher added it.
                let statusPhrases = Self.statuses(event.currentAssignment)
                detail = "\(context). First seen \(time)"
                phrases = statusPhrases
                spoken = ([name, context, "first seen \(time)", current?.spoken ?? "not graded"]
                    + statusPhrases.map(\.text)).joined(separator: ", ")
            } else {
                let statusPhrases = Self.statusChanges(from: event.previousAssignment, to: event.currentAssignment)
                let scoreChanged = previous?.text != current?.text
                detail = "\(context). Changed, found \(time)"
                phrases = statusPhrases
                if scoreChanged {
                    secondary = "was \(previous?.text ?? "not graded")"
                }
                var parts = [name, context, current?.spoken ?? "not graded"]
                if scoreChanged { parts.append("was \(previous?.spoken ?? "not graded")") }
                spoken = (parts + statusPhrases.map(\.text) + ["found \(time)"]).joined(separator: ", ")
            }
        }
    }


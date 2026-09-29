import SwiftUI

/// Assignments Skyward itself flags Missing in one quarter, by class. Only
/// the source `missing` flag counts: ungraded work, zeros, and attendance
/// never make an assignment missing here. The quarter starts from Courses'
/// term (a semester maps to its second quarter, stated on screen) and is
/// chosen here independently of Calendar's quarter.
struct MissingWorkView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var chosenQuarter: TermLabel?
    /// The Courses term when it was a semester, for the explanatory note.
    @State private var openedFromSemester: TermLabel?
    @State private var data: SchoolCalendarData?
    @State private var dataAccountRevision: Int?
    @State private var loadID = UUID()
    @State private var loading = false
    @State private var error: String?
    @State private var reminder: ReminderRequest?

    private var quarter: TermLabel {
        chosenQuarter ?? SchoolCalendar.quarter(for: store.selectedTerm)
    }

    /// Any change restarts loading and discards an older request's result.
    private struct LoadKey: Hashable {
        var accountRevision: Int
        var coursesRevision: Int
        var canShowData: Bool
        var quarter: TermLabel
    }

    private var loadKey: LoadKey {
        LoadKey(accountRevision: store.accountRevision, coursesRevision: store.coursesRefreshRevision,
                canShowData: store.canShowData, quarter: quarter)
    }

    private var eligible: [UnifiedCourseData] {
        SchoolCalendar.eligibleCourses(store.courses ?? [], term: quarter)
    }

    /// This quarter's data only; another quarter's is never shown under its name.
    private var shownData: SchoolCalendarData? {
        guard let data, data.term == quarter, dataAccountRevision == store.accountRevision else { return nil }
        return data
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    lastUpdated: shownData?.updatedAt,
                    isRefreshing: loading && shownData != nil,
                    error: shownData != nil ? error : nil
                ) {
                    await load(force: true)
                } control: {
                    ScopePicker(
                        title: "Missing work quarter",
                        valueName: quarter.displayName,
                        hint: "Selects the quarter whose missing work is listed",
                        identifier: "missing.quarter",
                        groups: [
                            ChoiceGroup(title: "Fall semester", options: [TermLabel.q1, .q2].map(quarterOption)),
                            ChoiceGroup(title: "Spring semester", options: [TermLabel.q3, .q4].map(quarterOption)),
                        ],
                        selection: Binding(get: { quarter }, set: { chosenQuarter = $0 })
                    )
                }
                .padding(.horizontal, Metrics.page)

                Text(scopeNote)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 4)

                content
                    .padding(.top, 12)
            }
            .padding(.bottom, 32)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Missing Work")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("missing.screen")
        .visibleRefreshable { await load(force: true) }
        .onAppear {
            guard chosenQuarter == nil else { return }
            chosenQuarter = SchoolCalendar.quarter(for: store.selectedTerm)
            openedFromSemester = store.selectedTerm.isSemester ? store.selectedTerm : nil
        }
        .task(id: loadKey) { await load(force: false) }
        .sheet(item: $reminder) { request in
            ReminderSheet(request: request)
        }
        .onChange(of: store.accountRevision) { _, _ in
            reminder = nil; data = nil; dataAccountRevision = nil; error = nil
        }
    }

    private func quarterOption(_ term: TermLabel) -> ChoiceOption<TermLabel> {
        ChoiceOption(value: term, title: term.displayName, identifier: "missing.quarter.\(term.shortName)")
    }

    private var scopeNote: String {
        var text = "Only assignments Skyward marks Missing. Ungraded work isn't treated as missing or as a zero."
        if let semester = openedFromSemester, semester.whatIfQuarterTerms.contains(quarter) {
            text = "Courses shows \(semester.displayName); missing work is listed by quarter. " + text
        }
        return text
    }

    // MARK: - Loading

    private func load(force: Bool) async {
        let key = loadKey
        let id = UUID()
        loadID = id
        guard key.canShowData else { return }
        if data?.term != key.quarter || dataAccountRevision != key.accountRevision {
            data = nil
            error = nil
        }
        // Calendar's saved data for the same quarter shows at once; this
        // screen's own load replaces it. Calendar's quarter is never changed.
        if data == nil, let saved = store.calendarQuarter(key.quarter).data, saved.term == key.quarter {
            data = saved
            dataAccountRevision = key.accountRevision
        }
        var courses = store.courses
        if courses == nil {
            loading = true
            await store.refreshCourses()
            guard !Task.isCancelled, loadKey == key && loadID == id else { return }
            courses = store.courses
        }
        guard let courses else {
            loading = false
            error = store.coursesError ?? "Courses couldn't load. Try again to see missing work."
            return
        }
        let eligible = SchoolCalendar.eligibleCourses(courses, term: key.quarter)
        guard !eligible.isEmpty else {
            loading = false
            error = nil
            return
        }
        loading = true
        error = nil
        defer { if loadKey == key && loadID == id { loading = false } }
        do {
            let result: SchoolCalendarData
            #if DEBUG
            if store.isUsingSampleData {
                result = SampleData.calendar(term: key.quarter, courses: eligible)
            } else {
                result = try await SchoolCalendarService.load(courses: courses, term: key.quarter, force: force,
                                                             previous: data ?? store.calendarQuarter(key.quarter).data)
            }
            #else
            result = try await SchoolCalendarService.load(courses: courses, term: key.quarter, force: force,
                                                         previous: data ?? store.calendarQuarter(key.quarter).data)
            #endif
            guard !Task.isCancelled, loadKey == key && loadID == id else { return }
            data = result
            dataAccountRevision = key.accountRevision
            if !result.failedCourseNames.isEmpty {
                error = result.resolvedCourseCount == 0
                    ? "Assignments couldn't load for any class. Try again."
                    : "Some classes couldn't refresh. Saved assignments are shown where available."
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, loadKey == key && loadID == id else { return }
            self.error = error.localizedDescription
        }
    }

    // MARK: - Content

    private struct CourseGroup: Identifiable {
        var course: UnifiedCourseData
        var assignments: [CalendarAssignment]
        var id: String { course.id }
    }

    /// Missing assignments grouped in the Courses order, from current classes only.
    private func groups(_ data: SchoolCalendarData) -> [CourseGroup] {
        eligible.compactMap { course in
            let missing = data.assignments.filter { assignment in
                assignment.course.id == course.id && assignment.meta.contains { $0.type == "missing" }
            }
            return missing.isEmpty ? nil : CourseGroup(course: course, assignments: missing)
        }
    }

    /// Classes with nothing loaded, and classes shown from saved data after a
    /// failed refresh, by source name.
    private func coverage(_ data: SchoolCalendarData) -> (missing: [String], saved: [String]) {
        let missing = eligible.filter { !data.resolvedCourseIDs.contains($0.id) }.map(\.courseName)
        let saved = data.failedCourseNames.filter { !missing.contains($0) }
        return (missing, saved)
    }

    @ViewBuilder
    private var content: some View {
        if store.courses != nil, eligible.isEmpty {
            EmptyStateView(
                title: "Missing work isn't available for \(quarter.displayName)",
                message: "None of your current classes has a Skyward gradebook for this quarter."
            )
            .padding(.horizontal, Metrics.page)
            .accessibilityIdentifier("missing.unavailable")
        } else if let data = shownData, data.resolvedCourseCount > 0 || data.failedCourseNames.isEmpty {
            loaded(data)
        } else if let error, !loading {
            InlineErrorState(title: "Couldn't load missing work", message: error) {
                await load(force: true)
            }
            .padding(.horizontal, Metrics.page)
            .accessibilityIdentifier("missing.error")
        } else {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    if index > 0 { InsetDivider() }
                    SkeletonRow(lines: [SkeletonLine(.body, [15, 11, 18][index]),
                                        SkeletonLine(.footnote, [10, 12, 9][index])])
                }
            }
            .padding(.horizontal, Metrics.page)
            .loadingPlaceholder("Loading missing work")
            .accessibilityIdentifier("missing.loading")
        }
    }

    @ViewBuilder
    private func loaded(_ data: SchoolCalendarData) -> some View {
        let groups = groups(data)
        let coverage = coverage(data)
        let isComplete = coverage.missing.isEmpty && coverage.saved.isEmpty && error == nil
        let count = groups.reduce(0) { $0 + $1.assignments.count }
        let undated = groups.reduce(0) { total, group in total + group.assignments.filter { $0.date == nil }.count }

        VStack(alignment: .leading, spacing: 0) {
            if groups.isEmpty {
                EmptyStateView(title: emptyTitle(complete: isComplete), message: emptyMessage(data, complete: isComplete))
                    .padding(.horizontal, Metrics.page)
                    .accessibilityIdentifier(isComplete ? "missing.none" : "missing.noneLoaded")
            } else {
                SectionHeading("Marked missing", count: "\(count)")
                    .padding(.horizontal, Metrics.page)
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    GroupLabel(MissingCourseTitle.display(group.course.courseName))
                        .padding(.horizontal, Metrics.page)
                        .padding(.top, index == 0 ? 4 : 20)
                    ForEach(Array(group.assignments.enumerated()), id: \.element.id) { row, assignment in
                        if row > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                        MissingAssignmentRow(
                            assignment: assignment,
                            onOpen: openAction(for: assignment),
                            onRemind: { remind(assignment) }, identifier: "missing.assignment.\(index).\(row)"
                        )
                    }
                }
                if undated > 0 {
                    note(undated == 1
                        ? "One has no calendar date in Skyward; its source text is shown."
                        : "\(undated) have no calendar date in Skyward; their source text is shown.")
                        .padding(.top, 12)
                }
            }

            if !coverage.missing.isEmpty || !coverage.saved.isEmpty {
                coverageNote(coverage)
                    .padding(.top, 12)
            }
        }
    }

    private func emptyTitle(complete: Bool) -> String {
        complete
            ? "No missing work in \(quarter.displayName)"
            : "No missing work in the classes that loaded"
    }

    /// A verified zero names its time; partial coverage says what it covers.
    private func emptyMessage(_ data: SchoolCalendarData, complete: Bool) -> String {
        let base = "Skyward marks no assignment Missing"
        if let updated = data.updatedAt {
            let time = updated.formatted(date: .abbreviated, time: .shortened)
            return complete ? "\(base) in your classes as of \(time)." : "\(base) in the saved assignments, as of \(time)."
        }
        return complete ? "\(base) in your classes." : "\(base) in the saved assignments."
    }

    private func coverageNote(_ coverage: (missing: [String], saved: [String])) -> some View {
        func names(_ list: [String]) -> String {
            ListFormatter.localizedString(byJoining: list.map(MissingCourseTitle.display))
        }
        return VStack(alignment: .leading, spacing: 0) {
            if !coverage.missing.isEmpty {
                note("Assignments couldn't load for \(names(coverage.missing)), so their missing work isn't listed.")
            }
            if !coverage.saved.isEmpty {
                note("Couldn't refresh \(names(coverage.saved)). Their saved assignments are shown.")
            }
            Button("Retry") {
                Task { await load(force: true) }
            }
            .buttonStyle(ActionTextButtonStyle())
            .disabled(loading)
            .padding(.horizontal, Metrics.page)
            .accessibilityLabel("Retry loading assignments")
            .accessibilityIdentifier("missing.coverage.retry")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("missing.coverage")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.page)
            .padding(.vertical, 4)
    }

    // MARK: - Actions

    /// The class's current record, never a copy saved with the assignment,
    /// and only when it has this quarter's gradebook.
    private func liveCourse(for assignment: CalendarAssignment) -> UnifiedCourseData? {
        guard let course = SchoolCalendar.eligibleCourses(store.courses ?? [], term: assignment.term)
            .first(where: { $0.id == assignment.course.id }) else { return nil }
        return course
    }

    private func openAction(for assignment: CalendarAssignment) -> (() -> Void)? {
        guard liveCourse(for: assignment) != nil else { return nil }
        let revision = store.accountRevision
        return {
            guard revision == store.accountRevision, let course = liveCourse(for: assignment) else { return }
            store.selectedTerm = assignment.term
            router.coursesPath.append(.assignment(course, assignment.term, assignment.routeID, UUID()))
        }
    }

    private func remind(_ assignment: CalendarAssignment) {
        let course = liveCourse(for: assignment) ?? assignment.course
        reminder = ReminderRequest(accountScope: store.notifications.accountScope ?? "", course: course, term: assignment.term, assignmentID: assignment.id,
                                   title: assignment.title, dueDay: assignment.date)
    }
}

/// Course names through the shared class-name formatter.
private enum MissingCourseTitle {
    static func display(_ raw: String) -> String {
        ClassNameFormatter.format(
            raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
        )
    }
}

/// One missing assignment: its title, category and source due date. Opens
/// the class on that quarter; the bell adds a personal reminder.
private struct MissingAssignmentRow: View {
    var assignment: CalendarAssignment
    var onOpen: (() -> Void)?
    var onRemind: () -> Void
    var identifier: String

    private var title: String {
        let text = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Untitled assignment" : text
    }

    /// A valid school date, or Skyward's own unreadable text.
    private var dateText: String {
        if let iso = assignment.date, let parts = AttendanceSchoolDate.components(iso),
           let date = Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12)) {
            return "Due " + date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        let source = assignment.sourceDate.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? "No date in Skyward" : "Date in Skyward: \(source)"
    }


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


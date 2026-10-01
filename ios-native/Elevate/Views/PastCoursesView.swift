import SwiftUI

/// Posted grades as Skyward sends them: letters, zeros and numbers are kept
/// as written, and only an empty value counts as not posted.
private enum PostedGrade {
    static func value(_ raw: String?) -> String? {
        CourseHistoryDisplay.postedValue(raw)
    }

    static func shown(_ value: String?) -> String {
        value ?? "—"
    }

    static func spoken(_ value: String?) -> String {
        value ?? "Not posted"
    }
}

/// "2023-2024" read as a span rather than a subtraction.
private func spokenSchoolYear(_ year: String) -> String {
    year.replacingOccurrences(of: "-", with: " to ")
}

/// Courses from earlier school years, one school year at a time. Read-only:
/// the rows show Skyward's posted semester grades and open a course's posted
/// quarter, exam and semester grades. Nothing here requests a gradebook.
/// Pushed from Records; a course opens through `RecordsRoute.pastCourse`.
struct PastCoursesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var gradeColumn: CGFloat = 52
    @State private var showingConnect = false
    @State private var selectedYear: String?

    var body: some View {
        Group {
            if !store.canShowData {
                LoginPromptView(message: "Connect your Skyward account to see posted grades from previous school years.") {
                    showingConnect = true
                }
            } else if let error = store.coursesError, store.courses == nil {
                ErrorStateView(title: "Couldn't load past courses", message: error) {
                    await store.refreshCourses(force: true)
                }
            } else {
                content
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Past courses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("history.screen")
        .sheet(isPresented: $showingConnect) {
            SkywardConnectSheet()
        }
        .task(id: store.accountRevision) {
            guard store.canShowData, store.courses == nil, !store.coursesLoading else { return }
            await store.refreshCourses()
        }
        .onChange(of: store.accountRevision) { _, _ in
            selectedYear = nil
        }
    }

    /// Nothing saved yet: a request is running or about to start.
    private var isFirstLoad: Bool {
        store.courses == nil
    }

    private var content: some View {
        let report = CourseHistoryReport(courses: store.courses ?? [])
        // Without the current school year, previous years can't be told
        // apart from it, so every recorded year is offered and labelled so.
        let showsRecordedYears = !report.hasCurrentYearEvidence
        let choices = showsRecordedYears ? report.knownAcademicYears : report.years
        let year = selectedYear.flatMap { choices.contains($0) ? $0 : nil } ?? choices.first
        let courses = year.map {
            showsRecordedYears ? report.courses(inAcademicYear: $0) : report.courses(for: $0)
        } ?? []
        let entries = CourseHistoryDisplay.entries(courses: courses)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusLine(choices: choices, year: year, report: report)
                    .padding(.horizontal, Metrics.page)

                if isFirstLoad {
                    loadingRows
                } else if choices.isEmpty {
                    if yearsUnavailable(report) {
                        InlineErrorState(
                            title: "School years unavailable",
                            message: "Refresh to load school years from Skyward."
                        ) {
                            await store.refreshCourses(force: true)
                        }
                        .padding(.horizontal, Metrics.page)
                        .padding(.top, 12)
                    } else {
                        EmptyStateView(
                            title: "No past courses",
                            message: "Posted semester grades from previous school years will appear here."
                        )
                        .padding(.horizontal, Metrics.page)
                    }
                } else {
                    if showsRecordedYears {
                        Text("Showing recorded school years. The current school year is unavailable.")
                            .font(.footnote)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Metrics.page)
                            .padding(.top, 4)
                    }
                    if entries.isEmpty {
                        EmptyStateView(title: "No posted semester grades", message: "No semester grades are posted for this school year.")
                            .padding(.horizontal, Metrics.page)
                    } else {
                        courseRows(entries)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .visibleRefreshable {
            await store.refreshCourses(force: true)
        }
    }

    /// Rows without a source year, or a schedule that couldn't be placed in
    /// a school year, are not a verified absence of past courses.
    private func yearsUnavailable(_ report: CourseHistoryReport) -> Bool {
        if report.hasLegacyMetadata { return true }
        return !report.hasCurrentYearEvidence && !(store.courses ?? []).isEmpty
    }

    // MARK: - School year

    @ViewBuilder
    private func statusLine(choices: [String], year: String?, report: CourseHistoryReport) -> some View {
        let isRefreshing = store.coursesLoading && store.courses != nil
        let error = store.courses != nil ? store.coursesError : nil
        if let year {
            StatusStrip(
                lastUpdated: store.coursesLastUpdated,
                isRefreshing: isRefreshing,
                error: error
            ) {
                await store.refreshCourses(force: true)
            } control: {
                ScopePicker(
                    title: "School year",
                    valueName: year,
                    hint: "Selects the school year shown",
                    identifier: "history.schoolYear",
                    groups: [ChoiceGroup(title: nil, options: choices.map { yearOption($0, report: report) })],
                    selection: Binding(get: { year }, set: { choose($0) })
                )
            }
        } else {
            StatusStrip(
                lastUpdated: store.coursesLastUpdated,
                isRefreshing: isRefreshing,
                error: error
            ) {
                await store.refreshCourses(force: true)
            }
        }
    }

    private func yearOption(_ year: String, report: CourseHistoryReport) -> ChoiceOption<String> {
        // A grade is named only when every course that year agrees on it.
        let grades = Set(report.courses(inAcademicYear: year).compactMap(\.gradeYear))
        return ChoiceOption(
            value: year,
            title: year,
            note: grades.count == 1 ? grades.first.map { "Grade \($0)" } : nil,
            identifier: "history.year.\(year)"
        )
    }

    private func choose(_ year: String) {
        guard year != selectedYear else { return }
        Motion.perform(Motion.select(reduceMotion)) { selectedYear = year }
    }

    // MARK: - Rows

    private struct Entry: Identifiable {
        var index: Int
        var course: UnifiedCourseData
        var id: String
    }

    private func indexedEntries(_ entries: [CourseHistoryDisplayEntry]) -> [Entry] {
        entries.enumerated().map { index, entry in
            Entry(index: index, course: entry.course, id: entry.id)
        }
    }

    private func courseRows(_ entries: [CourseHistoryDisplayEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                // Column names over the semester grades, not a header band.
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Text("Sem 1")
                        .frame(width: gradeColumn, alignment: .trailing)
                    Text("Sem 2")
                        .frame(width: gradeColumn, alignment: .trailing)
                }
                .modifier(TableHeaderStyle())
                .padding(.horizontal, Metrics.page)
                .padding(.top, 8)
            }
            ForEach(indexedEntries(entries)) { entry in
                if entry.index > 0 {
                    InsetDivider()
                        .padding(.horizontal, Metrics.page)
                }
                NavigationLink(value: RecordsRoute.pastCourse(entry.course)) {
                    PastCourseRow(course: entry.course, gradeColumn: gradeColumn)
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("history.course.\(entry.index)")
            }
        }
    }

    /// The archive's shape: the real column names over each course name and
    /// its two semester grades.
    private var loadingRows: some View {
        let names = [14, 10, 17, 12, 15, 9]
        return VStack(alignment: .leading, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Text("Sem 1")
                        .frame(width: gradeColumn, alignment: .trailing)
                    Text("Sem 2")
                        .frame(width: gradeColumn, alignment: .trailing)
                }
                .modifier(TableHeaderStyle())
                .padding(.horizontal, Metrics.page)
                .padding(.top, 8)
            }
            ForEach(names.indices, id: \.self) { index in
                if index > 0 {
                    InsetDivider()
                        .padding(.horizontal, Metrics.page)
                }
                PastCourseRowPlaceholder(name: names[index], gradeColumn: gradeColumn)
            }
        }
        .loadingPlaceholder("Loading past courses")
        .accessibilityIdentifier("history.loading")
    }
}

/// A loading past course in `PastCourseRow`'s layout: the name and a grade
/// bar in each semester column, or labelled semesters beneath the name at
/// accessibility sizes. Hidden from accessibility.
private struct PastCourseRowPlaceholder: View {
    var name: Int
    var gradeColumn: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    nameLine
                    semester("Semester 1")
                    semester("Semester 2")
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    nameLine
                        .frame(maxWidth: .infinity, alignment: .leading)
                    grade
                    grade
                }
            }
        }
        .padding(.horizontal, Metrics.page)
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var nameLine: some View {
        SkeletonText(.body.weight(.medium), length: name)
    }

    private var grade: some View {
        SkeletonText(.figure(.body), length: 2)
            .frame(width: gradeColumn, alignment: .trailing)
    }

    /// The semester names are fixed labels, as in `LabeledValue`.
    private func semester(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.muted)
            SkeletonText(.figure(.body), length: 2)
        }
    }
}

/// One past course as an open row: the name, the teacher when Skyward lists
/// one, and the posted semester grades. At accessibility sizes the grades
/// move beneath the name as labelled pairs.
private struct PastCourseRow: View {
    var course: UnifiedCourseData
    var gradeColumn: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var name: String {
        ClassNameFormatter.format(course.courseName.replacingOccurrences(of: " ", with: "_"))
    }


    private var sm1: String? { PostedGrade.value(course.postedGrades.sm1) }
    private var sm2: String? { PostedGrade.value(course.postedGrades.sm2) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    details
                    LabeledValue(label: "Semester 1", value: PostedGrade.shown(sm1),
                                 valueColor: sm1 == nil ? Color.muted : nil)
                    LabeledValue(label: "Semester 2", value: PostedGrade.shown(sm2),
                                 valueColor: sm2 == nil ? Color.muted : nil)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                    grade(sm1)
                    grade(sm2)
                }
            }
        }
        .padding(.horizontal, Metrics.page)
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("Semester 1 \(PostedGrade.spoken(sm1)), Semester 2 \(PostedGrade.spoken(sm2))")
        .accessibilityHint("Shows posted grades")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize >= .xxxLarge ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func grade(_ value: String?) -> some View {
        Text(PostedGrade.shown(value))
            .font(.figure(.body))
            .foregroundStyle(value == nil ? Color.muted : Color.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: gradeColumn, alignment: .trailing)
    }

    private var accessibilityName: String {
        name
    }
}

// MARK: - Course

/// A past course's posted grades, read-only: each semester's quarters,
/// exam and semester grade, as Skyward reported them.
struct HistoricalCourseDetailView: View {
    var course: UnifiedCourseData

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Line: Identifiable {
        var label: String
        var value: String?
        var isSemester = false
        var id: String { label }
    }

    private struct Part: Identifiable {
        var title: String
        var lines: [Line]
        var id: String { title }
    }

    private var name: String {
        ClassNameFormatter.format(course.courseName.replacingOccurrences(of: " ", with: "_"))
    }


    /// Semesters with at least one posted value; an empty semester is left out.
    private var parts: [Part] {
        let grades = course.postedGrades
        return [
            Part(title: "Fall semester", lines: [
                Line(label: "Quarter 1", value: PostedGrade.value(grades.rc1)),
                Line(label: "Quarter 2", value: PostedGrade.value(grades.rc2)),
                Line(label: "Exam 1", value: PostedGrade.value(grades.ex1)),
                Line(label: "Semester 1", value: PostedGrade.value(grades.sm1), isSemester: true),
            ]),
            Part(title: "Spring semester", lines: [
                Line(label: "Quarter 3", value: PostedGrade.value(grades.rc3)),
                Line(label: "Quarter 4", value: PostedGrade.value(grades.rc4)),
                Line(label: "Exam 2", value: PostedGrade.value(grades.ex2)),
                Line(label: "Semester 2", value: PostedGrade.value(grades.sm2), isSemester: true),
            ]),
        ].filter { $0.lines.contains { $0.value != nil } }
    }


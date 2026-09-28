import SwiftUI

/// Which GPA the trend chart plots. Both are the district's percentage scale.
private enum GPASeries: String, CaseIterable, Identifiable {
    case weighted = "Weighted"
    case unweighted = "Unweighted"

    var id: String { rawValue }
}

extension GradeLevel {
    /// "Senior year", "All years".
    var yearName: String {
        switch self {
        case .allTime: return "All years"
        default: return "\(rawValue) year"
        }
    }
}

/// GPA history for a school year. Pushed from the GPA line on Courses and
/// opened by the GPA widgets.
struct GPAView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 56
    @State private var showingConnect = false
    @State private var manualClasses: [ManualClass] = []
    @State private var series: GPASeries = .weighted

    private var selectedCourses: [UnifiedCourseData] {
        store.courses(for: store.selectedGradeLevel)
    }

    private var supportsManualEntry: Bool {
        GPAReport.supportsManualEntry(level: store.selectedGradeLevel, courses: selectedCourses)
    }

    private var selectableGradeLevels: [GradeLevel] {
        let currentYear = store.courses?.compactMap(\.gradeYear).max()
        var levels: [GradeLevel] = [.freshman, .sophomore, .junior, .senior].filter { level in
            guard let currentYear, let year = level.gradeYear else { return true }
            return year <= currentYear
        }
        if store.courses?.contains(where: { $0.gradeYear == nil }) == true {
            levels.insert(.current, at: 0)
        }
        levels.append(.allTime)
        return levels
    }

    private var gpaData: [String: GPAData] {
        GPAReport.termGPAs(
            level: store.selectedGradeLevel,
            courses: selectedCourses,
            manualClasses: manualClasses
        )
    }

    var body: some View {
        Group {
            if !store.canShowData {
                LoginPromptView(message: "Connect your Skyward account to see GPA history for each school year.") {
                    showingConnect = true
                }
            } else if let error = store.coursesError, store.courses == nil {
                ErrorStateView(title: "Couldn't load GPA data", message: error) {
                    await store.refreshCourses(force: true)
                }
            } else {
                content
            }
        }
        .navigationTitle("GPA")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.appBackground.ignoresSafeArea())
        .accessibilityIdentifier("gpa.screen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarButton { router.isShowingSettings = true }
            }
        }
        .sheet(isPresented: $showingConnect) { SkywardConnectSheet() }
        .task {
            validateSelectedYear()
            loadManualClasses()
        }
        .onChange(of: store.courses) { _, _ in validateSelectedYear() }
        .onChange(of: store.selectedGradeLevel) { _, _ in
            loadManualClasses()
        }
    }

    private func validateSelectedYear() {
        if !selectableGradeLevels.contains(store.selectedGradeLevel) {
            store.selectedGradeLevel = store.currentGradeLevel
        }
    }

    private var content: some View {
        let data = gpaData
        let points = graphPoints(data)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    lastUpdated: store.coursesLastUpdated,
                    isRefreshing: store.coursesLoading && store.courses != nil,
                    error: store.courses != nil ? store.coursesError : nil
                ) {
                    await store.refreshCourses(force: true)
                } control: {
                    schoolYearSelector
                }

                if store.coursesLoading && store.courses == nil {
                    // A semester's group of the term table: two quarters,
                    // then the semester set off by a hairline.
                    VStack(alignment: .leading, spacing: 0) {
                        SkeletonText(.footnote.weight(.medium), length: 11, tone: .secondary)
                            .padding(.bottom, 2)
                        GPATableRowPlaceholder(name: 8)
                        GPATableRowPlaceholder(name: 8)
                        InsetDivider()
                        GPATableRowPlaceholder(name: 9)
                    }
                    .padding(.top, 16)
                    .loadingPlaceholder("Loading GPA")
                } else if data.isEmpty && !supportsManualEntry {
                    EmptyStateView(
                        title: "No GPA yet",
                        message: "GPA appears when Skyward posts graded terms for this school year."
                    )
                } else {
                    if let latest = GPAReport.latest(in: data) {
                        hero(label: latest.label, data: latest.data, change: latestChange(in: data, latest: latest.label))
                            .padding(.top, 16)
                    }
                    if points.count >= 2 {
                        trendSection(points)
                    } else if !data.isEmpty {
                        Text("The trend appears after two graded terms.")
                            .font(.footnote)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 16)
                    }
                    termTable(data)
                    if supportsManualEntry {
                        ManualGradeEntryView(
                            gradeLevel: store.selectedGradeLevel,
                            classes: $manualClasses
                        )
                        .padding(.top, Metrics.sectionGap)
                    }
                }

                if !(store.coursesLoading && store.courses == nil) {
                    otherScales
                        .padding(.top, Metrics.sectionGap)
                    planning
                        .padding(.top, Metrics.sectionGap)
                }
            }
            .padding(.horizontal, Metrics.page)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .visibleRefreshable {
            // A forced fetch bypasses the cache on its own; saved data stays
            // on screen until the new response replaces it.
            await store.refreshCourses(force: true)
        }
    }

    // MARK: - Other scales

    /// Conversion stays separate from the district GPA above.
    private var otherScales: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Other scales")
            routeRow(.gpaConverter, title: "GPA converter",
                     note: "Completed semesters on 4.0 and 5.0 scales",
                     identifier: "gpa.converter")
        }
    }

    /// Local course planning. It pushes
    /// directly rather than through `CoursesRoute`; nothing deep-links to it.
    private var planning: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Planning")
            NavigationLink {
                CoursePlanView()
            } label: {
                routeLabel(title: "Course plan", note: "Credits toward graduation and planned semesters")
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("plan.navigation")
        }
    }

    private func routeRow(_ route: CoursesRoute, title: String, note: String, identifier: String) -> some View {
        NavigationLink(value: route) {
            routeLabel(title: title, note: note)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func routeLabel(title: String, note: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.faint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func loadManualClasses() {
        guard store.selectedGradeLevel.gradeYear != nil else {
            manualClasses = []
            return
        }
        manualClasses = WhatIfStore.manualClasses(gradeLevel: store.selectedGradeLevel)
    }

    // MARK: - School year

    /// Completed/current school years, followed by every year together.
    private var schoolYearSelector: some View {
        @Bindable var store = store
        let levels = selectableGradeLevels
        var groups = [ChoiceGroup(title: nil, options: levels.filter { $0 != .allTime }.map(yearOption))]
        if levels.contains(.allTime) {
            groups.append(ChoiceGroup(title: nil, options: [yearOption(.allTime)]))
        }
        return ScopePicker(
            title: "School year",
            valueName: store.selectedGradeLevel.yearName,
            hint: "Selects the school year used for GPA",
            identifier: "gpa.schoolYear",
            groups: groups,
            selection: $store.selectedGradeLevel
        )
    }

    private func yearOption(_ level: GradeLevel) -> ChoiceOption<GradeLevel> {
        let note: String?
        switch level {
        case .current: note = "Classes in Skyward now"
        case .allTime: note = "Every school year together"
        default: note = level.gradeYear.map { "Grade \($0)" }
        }
        return ChoiceOption(
            value: level,
            title: level.yearName,
            note: note,
            identifier: "gpa.year.\(level.shortName)"
        )
    }

    // MARK: - Latest

    /// Weighted change from the preceding progress report or quarter. Only
    /// defined for terms on the trend line; a semester or final is an average.
    private func latestChange(in data: [String: GPAData], latest: String) -> (from: String, value: Double)? {
        let terms = GPACalculator.graphTerms
        guard let index = terms.firstIndex(of: latest), let current = data[latest]?.weighted,
              let previous = terms[..<index].last(where: { data[$0] != nil }),
              let prior = data[previous]?.weighted,
              current.isFinite, prior.isFinite else { return nil }
        return (previous, current - prior)
    }

    /// The latest weighted GPA as the one large figure, with the unweighted
    /// value and the latest change as plain pairs beneath it.
    private func hero(label: String, data: GPAData, change: (from: String, value: Double)?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Weighted GPA")
                    .foregroundStyle(Color.ink)
                Text(GPAReport.termName(label))
                    .foregroundStyle(Color.muted)
                    .contentTransition(.opacity)
            }
            .font(.footnote)
            Text(GradeFormat.gpa(data.weighted))
                .font(.display(size: min(heroSize, 88)))
                .tracking(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: data.weighted))
                .animation(Motion.value(reduceMotion), value: data.weighted)

            pairs {
                LabeledValue(label: "Unweighted", value: GradeFormat.gpa(data.unweighted))
                if let change {
                    LabeledValue(
                        label: "Since \(GPAReport.termName(change.from))",
                        value: GradeFormat.signedChange(change.value)
                    )
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Latest GPA, \(GPAReport.termName(label))")
        .accessibilityValue(heroAccessibilityValue(data: data, change: change))
        .accessibilityIdentifier("gpa.latest")
    }

    /// Label/value pairs side by side, stacked at accessibility sizes.
    @ViewBuilder
    private func pairs<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10, content: content)
        } else {
            HStack(alignment: .top, spacing: 32, content: content)
        }
    }

    private func heroAccessibilityValue(data: GPAData, change: (from: String, value: Double)?) -> String {
        var parts = [
            "Weighted \(GradeFormat.gpa(data.weighted))",
            "unweighted \(GradeFormat.gpa(data.unweighted))",
        ]
        if let change {
            parts.append("\(GradeFormat.signedChange(change.value)) since \(GPAReport.termName(change.from))")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Trend

    /// Every graded progress report and quarter in order, in the chosen
    /// series. Terms without a GPA are left out, never drawn as zero.
    private func graphPoints(_ data: [String: GPAData]) -> [GPATrendPoint] {
        if store.selectedGradeLevel == .allTime {
            let manualByYear = Dictionary(uniqueKeysWithValues:
                [GradeLevel.freshman, .sophomore, .junior, .senior].compactMap { level in
                    level.gradeYear.map { ($0, WhatIfStore.manualClasses(gradeLevel: level)) }
                }
            )
            return GPATimeline.allYears(courses: selectedCourses, manualClassesByYear: manualByYear).map {
                GPATrendPoint(label: $0.term, value: series == .weighted ? $0.data.weighted : $0.data.unweighted, level: $0.level)
            }
        }
        return GPATimeline.terms.compactMap { label in
            guard let value = data[label], value.weighted.isFinite, value.unweighted.isFinite else { return nil }
            return GPATrendPoint(
                label: label,
                value: series == .weighted ? value.weighted : value.unweighted
            )
        }
    }

    /// Weighted or unweighted, chosen in place beside the heading; on its own
    /// line when large text leaves no room beside it.
    private var seriesChoice: some View {
        InlineChoice(
            label: "GPA shown in the chart",
            options: GPASeries.allCases.map { ChoiceOption(value: $0, title: $0.rawValue) },
            selection: $series
        )
        .accessibilityIdentifier("gpa.series")
    }

    private func trendSection(_ points: [GPATrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize >= .xxLarge {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeading("Trend")
                    seriesChoice
                }
            } else {
                SectionHeading(title: "Trend", count: nil) {
                    seriesChoice
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                // The curve is too small to read at these sizes; list the terms.
                VStack(spacing: 0) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        if index > 0 { InsetDivider() }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(point.displayName)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            Text(GradeFormat.gpa(point.value))
                                .font(.figure(.body))
                        }
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(series.rawValue) GPA by term")
                .accessibilityIdentifier("gpa.chart")
            } else {
                let values = graphPoints.map(\.weighted)
                let minY = (values.min() ?? 0) - 1
                let maxY = (values.max() ?? 100) + 1
                Chart(graphPoints) { point in
                    LineMark(x: .value("Term", point.label), y: .value("GPA", point.weighted))
                        .foregroundStyle(Color.themeAccent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("Term", point.label), y: .value("GPA", point.weighted))
                        .foregroundStyle(Color.themeAccent)
                    if point.label == selectedGraphTerm {
                        PointMark(x: .value("Term", point.label), y: .value("GPA", point.weighted))
                            .foregroundStyle(Color.themeAccent)
                            .annotation(position: .top) {
                                Text("\(graphDisplayName(point.label)): \(point.weighted, specifier: "%.2f")")
                                    .font(.caption.monospacedDigit().bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                    }
                }
                .chartYScale(domain: minY...maxY)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: graphAxisLabels) { value in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisTick().foregroundStyle(.tertiary)
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(graphDisplayName(label))
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedGraphTerm)
                .chartPlotStyle { plotArea in plotArea.clipped() }
                .frame(height: 130)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weighted GPA trend")
                .accessibilityValue(graphAccessibilityValue)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var graphAxisLabels: [String] {
        let labels = graphPoints.map(\.label)
        guard labels.count > 5 else { return labels }
        let preferred = ["RC1", "RC2", "RC3", "RC4"]
            .filter(labels.contains)
        if preferred.count >= 2 { return preferred }
        return labels.enumerated().compactMap { index, label in
            index == 0 || index == labels.count - 1 || index.isMultiple(of: 3) ? label : nil
        }
    }

    private func gradeLevelPicker(selection: Binding<GradeLevel>) -> some View {
        Picker("School year", selection: selection) {
            ForEach(selectableGradeLevels) { level in
                Text(level.rawValue)
                    .tag(level)
            }
        }
        .pickerStyle(.menu)
    }

    private var graphAccessibilityValue: String {
        graphPoints
            .map { "\(graphDisplayName($0.label)) \(String(format: "%.2f", $0.weighted))" }
            .joined(separator: ", ")
    }

    private func graphDisplayName(_ label: String) -> String {
        switch label {
        case "RC1": return "Q1"
        case "RC2": return "Q2"
        case "RC3": return "Q3"
        case "RC4": return "Q4"
        default: return label.replacingOccurrences(of: "PR", with: "P")
        }
    }

    // MARK: - Cards

    private var gpaCards: some View {
        let data = gpaData
        let hasFin = data["SM1"] != nil && data["SM2"] != nil

        return VStack(spacing: 0) {
            // Latest progress-report pair when the semester isn't complete yet.
            if !hasFin {
                let prLabels = ["PR1", "PR2", "PR3", "PR4", "PR5", "PR6", "PR7", "PR8"].filter { data[$0] != nil }
                let latest = Array(prLabels.suffix(2))
                if latest.count == 2 {
                    gpaPair(first: latest[0], second: latest[1], data: data)
                } else if latest.count == 1 {
                    GpaSoloCardView(label: latest[0], data: data[latest[0]]!)
                }
            }

            ForEach([["RC1", "RC2"], ["RC3", "RC4"]], id: \.self) { pair in
                if data[pair[0]] != nil || data[pair[1]] != nil {
                    gpaPair(first: pair[0], second: pair[1], data: data)
                }
                if pair[0] == "RC1", let sm1 = data["SM1"] {
                    GpaSoloCardView(label: "SM1", data: sm1)
                }
                if pair[0] == "RC3", let sm2 = data["SM2"] {
                    GpaSoloCardView(label: "SM2", data: sm2)
                }
            }

            if hasFin, let sm1 = data["SM1"], let sm2 = data["SM2"] {
                GpaSoloCardView(label: "FIN", data: GPAData(
                    unweighted: (sm1.unweighted + sm2.unweighted) / 2,
                    weighted: (sm1.weighted + sm2.weighted) / 2
                ))
            }
        }
    }

    private func gpaPair(first: String, second: String, data: [String: GPAData]) -> some View {
        VStack(spacing: 0) {
            GpaCardView(label: first, data: data[first])
            GpaCardView(label: second, data: data[second])
        }
    }
}

struct GpaCardView: View {
    var label: String
    var data: GPAData?

    var body: some View {
        GpaRowLayout(label: label, data: data)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct GpaSoloCardView: View {
    var label: String
    var data: GPAData

    var body: some View {
        GpaRowLayout(label: label, data: data)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct GpaRowLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var label: String
    var data: GPAData?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if dynamicTypeSize < .xxxLarge {
                HStack(alignment: .center, spacing: 12) {
                    termLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                    values
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                termLabel
                values
            }

            VStack(alignment: .leading, spacing: 10) {
                termLabel
                VStack(alignment: .leading, spacing: 8) {
                    gpaValue("Unweighted", value: data?.unweighted, horizontal: true)
                    gpaValue("Weighted", value: data?.weighted, horizontal: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var termLabel: some View {
        Text(gpaTermName(label))
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var values: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            gpaValue("Unweighted", value: data?.unweighted)
            gpaValue("Weighted", value: data?.weighted)
        }
    }

    private func gpaValue(_ label: String, value: Double?, horizontal: Bool = false) -> some View {
        Group {
            if horizontal {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    number(value)
                }
                .font(.body)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    number(value)
                }
            }
        }
    }

    private func number(_ value: Double?) -> some View {
        Text(value.map { String(format: "%.2f", $0) } ?? "—")
            .font(.title3.weight(.semibold).monospacedDigit())
            .contentTransition(.numericText(value: value ?? 0))
            .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Manual grade entry (fallback when Skyward has no data for a year)

struct ManualGradeEntryView: View {
    var gradeLevel: GradeLevel
    @Binding var classes: [ManualClass]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var newClassName = ""
    @State private var newSM1 = ""
    @State private var newSM2 = ""
    @State private var pendingDeletion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Grade Entry")
                .font(.headline)
            Text("No Skyward data for \(gradeLevel.rawValue). Add semester grades manually to estimate your GPA.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(classes) { entry in
                Group {
                    if dynamicTypeSize >= .xxxLarge {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.className)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(nil)
                            Text(CourseLevelDetector.level(for: entry.className).rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Semester 1: \(manualGrade(entry.sm1))")
                                .font(.caption.monospacedDigit())
                            Text("Semester 2: \(manualGrade(entry.sm2))")
                                .font(.caption.monospacedDigit())
                            HStack {
                                Spacer()
                                deleteButton(for: entry)
                            }
                        }
                    } else {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.className).font(.subheadline.weight(.medium))
                                Text(CourseLevelDetector.level(for: entry.className).rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("S1: \(entry.sm1.map { String(format: "%.0f", $0) } ?? "--")")
                                .font(.caption.monospacedDigit())
                            Text("S2: \(entry.sm2.map { String(format: "%.0f", $0) } ?? "--")")
                                .font(.caption.monospacedDigit())
                            deleteButton(for: entry)
                        }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }

            VStack(spacing: 12) {
                field("Class name") {
                    TextField("e.g. AP Biology", text: $newClassName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        semesterOneField
                        semesterTwoField
                    }
                    VStack(spacing: 12) {
                        semesterOneField
                        semesterTwoField
                    }
                }
                Button {
                    guard canAdd else { return }
                    classes.append(ManualClass(
                        className: newClassName.trimmingCharacters(in: .whitespacesAndNewlines),
                        sm1: parsedSM1,
                        sm2: parsedSM2
                    ))
                    WhatIfStore.saveManualClasses(classes, gradeLevel: gradeLevel)
                    newClassName = ""; newSM1 = ""; newSM2 = ""
                } label: {
                    Label("Add class", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .tint(Color.prominentFill)
                .disabled(!canAdd)
            }
        }
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) { Divider() }
        .confirmationDialog(
            "Delete manual class?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete class", role: .destructive) {
                guard let pendingDeletion else { return }
                classes.removeAll { $0.id == pendingDeletion }
                WhatIfStore.saveManualClasses(classes, gradeLevel: gradeLevel)
                self.pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        }
    }

    private func manualGrade(_ grade: Double?) -> String {
        grade.map { String(format: "%.0f", $0) } ?? "Not entered"
    }

    private func deleteButton(for entry: ManualClass) -> some View {
        Button(role: .destructive) {
            pendingDeletion = entry.id
        } label: {
            Image(systemName: "trash")
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Delete \(entry.className)")
    }

    private var parsedSM1: Double? { parsedGrade(newSM1) }
    private var parsedSM2: Double? { parsedGrade(newSM2) }

    private var canAdd: Bool {
        let sm1Empty = newSM1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let sm2Empty = newSM2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !newClassName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (sm1Empty || parsedSM1 != nil)
            && (sm2Empty || parsedSM2 != nil)
            && !(sm1Empty && sm2Empty)
    }

    private func parsedGrade(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite, (0...110).contains(value) else {
            return nil
        }
        return value
    }

    private var semesterOneField: some View {
        field("Semester 1") {
            TextField("Grade", text: $newSM1)
                .keyboardType(.decimalPad)
        }
    }

    private var semesterTwoField: some View {
        field("Semester 2") {
            TextField("Grade", text: $newSM2)
                .keyboardType(.decimalPad)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.subtleBorder, lineWidth: 0.5)
                }
        }
    }
}

private func gpaTermName(_ code: String) -> String {
    switch code {
    case "RC1": return "Quarter 1"
    case "RC2": return "Quarter 2"
    case "RC3": return "Quarter 3"
    case "RC4": return "Quarter 4"
    case "SM1": return "Semester 1"
    case "SM2": return "Semester 2"
    case "FIN": return "Final"
    default:
        if code.hasPrefix("PR"), let number = code.dropFirst(2).first {
            return "Progress report \(number)"
        }
        return code
    }
}

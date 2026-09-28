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
    }

    private var content: some View {
        @Bindable var store = store
        return ScrollView {
            VStack(spacing: 0) {
                if store.coursesError != nil, store.courses != nil {
                    StaleDataBanner(lastUpdated: store.coursesLastUpdated) {
                        await store.refreshCourses(force: true)
                    }
                    .padding(.bottom, 16)
                }

                if selectableGradeLevels.count > 1 {
                    Group {
                        if dynamicTypeSize >= .xxxLarge {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("School year")
                                    .font(.subheadline.weight(.semibold))
                                gradeLevelPicker(selection: $store.selectedGradeLevel)
                            }
                        } else {
                            HStack {
                                Text("School year")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                gradeLevelPicker(selection: $store.selectedGradeLevel)
                            }
                        }
                    }
                    .accessibilityHint("Selects the school year used for GPA")
                    .padding(.bottom, 20)
                }

                if store.coursesLoading && store.courses == nil {
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in SkeletonRow(height: 70) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading GPA")
                } else if gpaData.isEmpty && !supportsManualEntry {
                    EmptyStateView(
                        systemImage: "chart.line.uptrend.xyaxis",
                        title: "No GPA data yet",
                        subtitle: "GPA will appear when graded terms are available in Skyward"
                    )
                    .padding(.top, 40)
                } else {
                    if graphPoints.count >= 2 {
                        graphCard
                    }
                    gpaCards
                    if supportsManualEntry {
                        ManualGradeEntryView(
                            gradeLevel: store.selectedGradeLevel,
                            classes: $manualClasses
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable {
            await DataService.shared.clearCaches()
            await store.refreshCourses(force: true)
        }
        .background(Color.appBackground)
    }

    private func loadManualClasses() {
        guard store.selectedGradeLevel.gradeYear != nil else {
            manualClasses = []
            return
        }
        manualClasses = WhatIfStore.manualClasses(gradeLevel: store.selectedGradeLevel)
    }

    // MARK: - Graph

    private struct GraphPoint: Identifiable {
        var index: Int
        var label: String
        var weighted: Double
        var id: Int { index }
    }

    private var graphPoints: [GraphPoint] {
        let data = gpaData
        return GPACalculator.graphTerms
            .compactMap { label -> (String, Double)? in
                guard let value = data[label], value.weighted.isFinite else { return nil }
                return (label, value.weighted)
            }
            .enumerated()
            .map { GraphPoint(index: $0.offset, label: $0.element.0, weighted: $0.element.1) }
    }

    private var graphCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Weighted GPA trend")
                    .font(.headline)
                Spacer()
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(Color.highlightText)
                    .accessibilityHidden(true)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(graphPoints) { point in
                        HStack {
                            Text(graphDisplayName(point.label))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 16)
                            Text(point.weighted, format: .number.precision(.fractionLength(2)))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
                .accessibilityElement(children: .combine)
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

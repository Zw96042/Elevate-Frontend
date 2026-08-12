import SwiftUI

enum AssignmentSortOption: String, CaseIterable, Identifiable {
    case date = "Date"
    case category = "Category"
    case grade = "Grade"
    var id: String { rawValue }
}

enum AssignmentFilterOption: String, CaseIterable, Identifiable {
    case missing = "Missing"
    case noCount = "No Count"
    case absent = "Absent"
    var id: String { rawValue }
}

enum AssignmentGradeRange: String, CaseIterable, Identifiable {
    case excellent = "90–100"
    case good = "80–89"
    case passing = "70–79"
    case belowPassing = "Below 70"
    case ungraded = "Ungraded"

    var id: String { rawValue }

    func contains(_ assignment: CalcAssignment) -> Bool {
        guard let grade = assignment.grade, assignment.outOf > 0 else {
            return self == .ungraded
        }
        let percentage = grade / assignment.outOf * 100
        switch self {
        case .excellent: return percentage >= 90
        case .good: return (80..<90).contains(percentage)
        case .passing: return (70..<80).contains(percentage)
        case .belowPassing: return percentage < 70
        case .ungraded: return false
        }
    }
}

struct ClassDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let course: UnifiedCourseData

    @State private var gradeInfo: GradeInfoResult?
    @State private var gradeInfoLastUpdated: Date?
    @State private var loading = true
    @State private var loadError: String?
    @State private var loadedBucket: String?

    @State private var showCalculated = false
    @State private var whatIfAssignments: [WhatIfAssignment] = []
    @State private var finalExamGrades: [String: Double] = [:]
    @State private var showingAddSheet = false
    @State private var showingResetConfirmation = false

    @State private var sortOption: AssignmentSortOption = .date
    @State private var sortAscending = false
    @State private var categoryFilter: Set<String> = []
    @State private var assignmentFilter: Set<AssignmentFilterOption> = []
    @State private var gradeFilter: Set<AssignmentGradeRange> = []
    @State private var showsBreakdown = false

    private var classKey: String {
        WhatIfStore.classKey(studentID: course.stuId, className: course.courseName, corNumId: course.corNumId,
                             section: course.section, gbId: course.gbId)
    }

    private var examType: String { store.selectedTerm == .sm1 ? "EX1" : "EX2" }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                headerSection
                if loading {
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { _ in SkeletonRow(height: 80) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading assignments")
                } else if let loadError, !hasCurrentGradeInfo {
                    ErrorStateView(title: "Couldn't load assignments", message: loadError) {
                        await load(force: true)
                    }
                    .frame(minHeight: 300)
                } else {
                    if loadError != nil {
                        StaleDataBanner(lastUpdated: gradeInfoLastUpdated) {
                            await load(force: true)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    categoriesSection
                    if store.selectedTerm.isSemester {
                        finalExamSection
                    }
                    assignmentsSection
                }
            }
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Assignments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if showCalculated {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingAddSheet = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add what-if assignment")
                    if !whatIfAssignments.isEmpty || hasFinalExamEstimateForSelectedTerm {
                        Button(role: .destructive) { showingResetConfirmation = true } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .accessibilityLabel("Reset what-if changes")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddAssignmentSheet(
                categories: gradeInfo?.gradebook.map(\.category).filter { $0 != "Final Exam" } ?? [],
                term: store.selectedTerm
            ) { assignment in
                var a = assignment
                a.className = course.courseName
                WhatIfStore.add(a, classKey: classKey)
                reloadWhatIf()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task(id: store.selectedTerm) {
            categoryFilter.removeAll()
            assignmentFilter.removeAll()
            gradeFilter.removeAll()
            showCalculated = WhatIfStore.showCalculated(classKey: classKey)
            reloadWhatIf()
            await load()
        }
        .refreshable {
            await load(force: true)
        }
        .alert("Reset what-if changes?", isPresented: $showingResetConfirmation) {
            Button("Reset changes", role: .destructive) { resetWhatIf() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resetConfirmationMessage)
        }
        .background(Color.appBackground)
    }

    // MARK: - Data

    private func load(force: Bool = false) async {
        let bucket = store.selectedTerm.bucket
        if !force, loadedBucket == bucket, gradeInfo != nil { return }
        loading = gradeInfo == nil || loadedBucket != bucket
        loadError = nil
        do {
            let params = GradeInfoParams(stuId: course.stuId, corNumId: course.corNumId,
                                         gbId: course.gbId, section: course.section, bucket: bucket)
            let result = try await DataService.shared.gradeInfo(params: params, forceRefresh: force)
            guard !Task.isCancelled, store.selectedTerm.bucket == bucket else { return }
            gradeInfo = result
            gradeInfoLastUpdated = Date()
            let availableCategories = Set(
                gradeInfo?.gradebook.map(\.category).filter { $0 != "Final Exam" } ?? []
            )
            categoryFilter.formIntersection(availableCategories)
            loadedBucket = bucket
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, store.selectedTerm.bucket == bucket else { return }
            loadError = error.localizedDescription
        }
        guard !Task.isCancelled, store.selectedTerm.bucket == bucket else { return }
        loading = false
    }

    private var hasCurrentGradeInfo: Bool {
        gradeInfo != nil && loadedBucket == store.selectedTerm.bucket
    }

    private func reloadWhatIf() {
        whatIfAssignments = WhatIfStore.assignments(classKey: classKey, term: store.selectedTerm)
        finalExamGrades = WhatIfStore.finalExamGrades(classKey: classKey)
    }

    private func resetWhatIf() {
        WhatIfStore.reset(classKey: classKey, term: store.selectedTerm)
        reloadWhatIf()
    }

    private var hasFinalExamEstimateForSelectedTerm: Bool {
        store.selectedTerm.isSemester && finalExamGrades[examType] != nil
    }

    private var resetConfirmationMessage: String {
        if store.selectedTerm.isSemester {
            return "This removes the hypothetical assignments and final exam grade for this term."
        }
        return "This removes the hypothetical assignments for this term."
    }

    // MARK: - Computation

    private var apiAssignments: [CalcAssignment] {
        guard let gradeInfo else { return [] }
        return gradeInfo.gradebook.flatMap { cat in
            cat.assignments.enumerated().map { index, a in
                CalcAssignment(
                    id: "\(cat.category)-\(index)-\(a.name)",
                    className: course.courseName,
                    name: a.name,
                    term: store.selectedTerm.shortName,
                    category: cat.category,
                    grade: a.pointsEarned,
                    outOf: a.pointsTotal ?? 100,
                    dueDate: a.date,
                    artificial: false,
                    meta: a.meta
                )
            }
        }
    }

    /// Real assignments plus independently identified hypothetical assignments.
    private var meshedAssignments: [CalcAssignment] {
        guard showCalculated else { return apiAssignments }
        let whatIf = whatIfAssignments.map { w in
            CalcAssignment(id: w.id, className: w.className, name: w.name, term: w.term,
                           category: w.category, grade: w.grade, outOf: w.outOf,
                           dueDate: w.dueDate, artificial: true,
                           meta: metadata(for: w.resolvedStatus))
        }
        return whatIf + apiAssignments
    }

    private func metadata(for status: WhatIfAssignmentStatus) -> [AssignmentMeta] {
        switch status {
        case .counted:
            return []
        case .noCount:
            return [AssignmentMeta(type: "noCount", note: "Excluded from grade")]
        case .missing:
            return [AssignmentMeta(type: "missing", note: "Missing")]
        case .absent:
            return [AssignmentMeta(type: "absent", note: "Absent")]
        }
    }

    private var effectiveFinalExamGrade: Double? {
        if showCalculated, let estimate = finalExamGrades[examType], estimate.isFinite {
            return estimate
        }
        if let assignment = gradeInfo?.gradebook
            .first(where: { $0.category == "Final Exam" })?
            .assignments.first(where: { !$0.meta.contains { $0.type == "noCount" } }) {
            if let percentage = GradeCalculator.percentage(
                earned: assignment.pointsEarned,
                outOf: assignment.pointsTotal
            ) {
                return percentage
            }
            if let score = assignment.score, score.isFinite { return score }
            if let grade = assignment.grade { return Double(grade) }
        }
        return course.currentScores.first { $0.bucket == examType && $0.score.isFinite }?.score
    }

    private var quarterTotals: (first: Double?, second: Double?) {
        func score(_ bucket: String) -> Double? {
            course.currentScores.first { $0.bucket == bucket }?.score
        }
        return store.selectedTerm == .sm1
            ? (score("Q1"), score("Q2"))
            : (score("Q3"), score("Q4"))
    }

    private var summary: GradeSummary {
        let countable = meshedAssignments.filter { $0.category != "Final Exam" }
        let weights = GradeCalculator.normalizedWeights(categories: gradeInfo?.gradebook ?? [], assignments: countable)
        return GradeCalculator.summary(
            assignments: countable,
            categoryWeights: weights,
            quarterTotals: store.selectedTerm.isSemester ? quarterTotals : nil,
            selectedTerm: store.selectedTerm,
            finalExamGrade: store.selectedTerm.isSemester ? effectiveFinalExamGrade : nil
        )
    }

    private var displayGrade: Double? {
        guard hasCurrentGradeInfo else { return nil }
        if showCalculated, let calculated = summary.courseTotal {
            return calculated
        }
        return gradeInfo?.score
            ?? summary.courseTotal
            ?? course.historicalGrades[store.selectedTerm.historicalKey].flatMap { Double($0) }
    }

    private var displayedAssignments: [CalcAssignment] {
        var list = meshedAssignments.filter { $0.category != "Final Exam" }
        if !categoryFilter.isEmpty {
            list = list.filter { categoryFilter.contains($0.category) }
        }
        if !assignmentFilter.isEmpty {
            list = list.filter { assignment in
                (assignmentFilter.contains(.missing) && assignment.isMissing)
                    || (assignmentFilter.contains(.noCount) && assignment.isNoCount)
                    || (assignmentFilter.contains(.absent) && assignment.isAbsent)
            }
        }
        if !gradeFilter.isEmpty {
            list = list.filter { assignment in
                gradeFilter.contains { $0.contains(assignment) }
            }
        }
        let parsedDates = Dictionary(
            list.map { ($0.id, parseDate($0.dueDate)) },
            uniquingKeysWith: { first, _ in first }
        )
        list.sort { a, b in
            switch sortOption {
            case .category:
                return sortAscending ? a.category < b.category : a.category > b.category
            case .date:
                let first = parsedDates[a.id] ?? .distantPast
                let second = parsedDates[b.id] ?? .distantPast
                return sortAscending ? first < second : first > second
            case .grade:
                let first = (a.grade ?? -1) / max(a.outOf, 1)
                let second = (b.grade ?? -1) / max(b.outOf, 1)
                return sortAscending ? first < second : first > second
            }
        }
        return list
    }

    private func parseDate(_ string: String) -> Date {
        let parts = string.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantPast }
        var components = DateComponents()
        components.month = parts[0]
        components.day = parts[1]
        components.year = parts[2] < 100 ? 2000 + parts[2] : parts[2]
        return Calendar.current.date(from: components) ?? .distantPast
    }

    // MARK: - Sections

    private var headerSection: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        courseIdentity
                        displayGradeLabel
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        courseIdentity
                        Spacer()
                        displayGradeLabel
                    }
                }
            }
            .padding(.bottom, 14)

            TermPickerPill(selectedTerm: $store.selectedTerm, showsDescriptor: false)

            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.32))
                .frame(height: 0.5)

            Toggle("What-if grades", isOn: Binding(
                get: { showCalculated },
                set: { newValue in
                    showCalculated = newValue
                    WhatIfStore.setShowCalculated(newValue, classKey: classKey)
                }
            ))
            .frame(minHeight: 52)
            .sensoryFeedback(.selection, trigger: showCalculated)

            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.32))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var courseIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ClassNameFormatter.format(course.courseName.replacingOccurrences(of: " ", with: "_")))
                .font(.title2.weight(.semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let instructor = course.instructor, !instructor.isEmpty {
                Text(ClassNameFormatter.format(instructor.replacingOccurrences(of: " ", with: "_")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var displayGradeLabel: some View {
        if let displayGrade {
            (Text(displayGrade, format: .number.precision(.fractionLength(1))) + Text("%"))
                .font(.title2.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(value: displayGrade))
        }
    }

    private var categoriesSection: some View {
        let categories = gradeInfo?.gradebook.filter { $0.category != "Final Exam" } ?? []
        return Group {
            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        if reduceMotion {
                            showsBreakdown.toggle()
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showsBreakdown.toggle()
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text("Grade breakdown")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showsBreakdown ? 180 : 0))
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showsBreakdown ? "Expanded" : "Collapsed")

                    if showsBreakdown {
                        Rectangle()
                            .fill(Color(uiColor: .separator).opacity(0.32))
                            .frame(height: 0.5)

                        ForEach(Array(categories.enumerated()), id: \.element.category) { index, category in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color(uiColor: .separator).opacity(0.32))
                                    .frame(height: 0.5)
                            }
                            categoryRow(category)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: GradeCategory) -> some View {
        let result = summary.categories[category.category]
        let baseWeight = category.weight ?? 0
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(category.category)
                    .font(.subheadline.weight(.medium))
                Text(categoryAverage(result))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(categoryWeight(result: result, baseWeight: baseWeight))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else {
            HStack(alignment: .center, spacing: 12) {
                Text(category.category)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(categoryAverage(result))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(categoryWeight(result: result, baseWeight: baseWeight))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 46)
        }
    }

    private func categoryAverage(_ result: GradeSummary.CategoryResult?) -> String {
        result.map { String(format: "%.1f%%", $0.average) } ?? "Ungraded"
    }

    private func categoryWeight(result: GradeSummary.CategoryResult?, baseWeight: Double) -> String {
        guard let result else { return String(format: "%.0f%% weight, inactive", baseWeight) }
        if abs(result.weight - baseWeight) >= 0.05 {
            return String(format: "%.0f%% weight, %.1f%% active", baseWeight, result.weight)
        }
        return String(format: "%.0f%% weight", baseWeight)
    }

    private var finalExamSection: some View {
        let examName = store.selectedTerm == .sm1 ? "Exam 1" : "Exam 2"
        let realAssignment = apiAssignments.first { $0.category == "Final Exam" }
        let dueDate = realAssignment?.dueDate ?? ""
        let estimate = finalExamGrades[examType]
        let realGrade = effectiveFinalExamGrade
        let shown: Double? = (showCalculated && estimate != nil) ? estimate : realGrade

        return AssignmentRow(
            assignment: CalcAssignment(
                id: "final-exam-\(examType)", className: course.courseName, name: examName,
                term: examType, category: "Final Exam", grade: shown, outOf: 100,
                dueDate: dueDate, artificial: showCalculated && estimate != nil, meta: []
            ),
            editable: showCalculated,
            onEditGrade: { newGrade in
                WhatIfStore.setFinalExamGrade(newGrade, examType: examType, classKey: classKey)
                reloadWhatIf()
            },
            onDelete: nil
        )
        .padding(.horizontal, 20)
    }

    private var assignmentsSection: some View {
        let assignments = displayedAssignments
        let hasUnfilteredAssignments = meshedAssignments.contains { $0.category != "Final Exam" }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Assignments")
                    .font(.title3.weight(.semibold))
                Spacer()
                if hasUnfilteredAssignments || hasActiveAssignmentControls {
                    filterMenu
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)

            if assignments.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No assignments found",
                    subtitle: categoryFilter.isEmpty
                        && assignmentFilter.isEmpty
                        && gradeFilter.isEmpty
                        ? "No assignments available for this term"
                        : "Try adjusting your filters to see more results"
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(assignments) { assignment in
                        AssignmentRow(
                            assignment: assignment,
                            editable: showCalculated && assignment.artificial,
                            onEditGrade: assignment.artificial ? { newGrade in
                                if var match = whatIfAssignments.first(where: { $0.id == assignment.id }) {
                                    match.grade = newGrade
                                    WhatIfStore.update(match, classKey: classKey)
                                    reloadWhatIf()
                                }
                            } : nil,
                            onChangeStatus: assignment.artificial ? { status in
                                if var match = whatIfAssignments.first(where: { $0.id == assignment.id }) {
                                    match.resolvedStatus = status
                                    WhatIfStore.update(match, classKey: classKey)
                                    reloadWhatIf()
                                }
                            } : nil,
                            onDelete: assignment.artificial ? {
                                WhatIfStore.remove(id: assignment.id, classKey: classKey, term: store.selectedTerm)
                                reloadWhatIf()
                            } : nil
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Menu {
                Menu {
                    ForEach(AssignmentSortOption.allCases) { option in
                        Button {
                            sortOption = option
                            sortAscending = option == .category
                        } label: {
                            if sortOption == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(sortOption.rawValue, systemImage: "arrow.up.arrow.down")
                }

                Menu {
                    Button {
                        sortAscending = true
                    } label: {
                        if sortAscending {
                            Label(ascendingLabel, systemImage: "checkmark")
                        } else {
                            Text(ascendingLabel)
                        }
                    }
                    Button {
                        sortAscending = false
                    } label: {
                        if !sortAscending {
                            Label(descendingLabel, systemImage: "checkmark")
                        } else {
                            Text(descendingLabel)
                        }
                    }
                } label: {
                    Label(
                        sortAscending ? ascendingLabel : descendingLabel,
                        systemImage: "arrow.up.arrow.down.circle"
                    )
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }

            Menu {
                if !availableFilterCategories.isEmpty {
                    Menu {
                        ForEach(availableFilterCategories, id: \.self) { category in
                            Button {
                                if categoryFilter.contains(category) {
                                    categoryFilter.remove(category)
                                } else {
                                    categoryFilter.insert(category)
                                }
                            } label: {
                                if categoryFilter.contains(category) {
                                    Label(category, systemImage: "checkmark")
                                } else {
                                    Text(category)
                                }
                            }
                        }
                    } label: {
                        Label(
                            categoryFilter.isEmpty ? "Categories" : "Categories (\(categoryFilter.count))",
                            systemImage: "tag"
                        )
                    }
                }

                Menu {
                    ForEach(AssignmentFilterOption.allCases) { option in
                        Button {
                            if assignmentFilter.contains(option) {
                                assignmentFilter.remove(option)
                            } else {
                                assignmentFilter.insert(option)
                            }
                        } label: {
                            if assignmentFilter.contains(option) {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(
                        assignmentFilter.isEmpty
                            ? "Assignment types"
                            : "Assignment types (\(assignmentFilter.count))",
                        systemImage: "checklist"
                    )
                }

                Menu {
                    ForEach(AssignmentGradeRange.allCases) { range in
                        Button {
                            if gradeFilter.contains(range) {
                                gradeFilter.remove(range)
                            } else {
                                gradeFilter.insert(range)
                            }
                        } label: {
                            if gradeFilter.contains(range) {
                                Label(range.rawValue, systemImage: "checkmark")
                            } else {
                                Text(range.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(
                        gradeFilter.isEmpty ? "Grade" : "Grade (\(gradeFilter.count))",
                        systemImage: "percent"
                    )
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease")
            }

            if hasActiveAssignmentControls {
                Divider()
                Button("Reset sort and filters", systemImage: "arrow.counterclockwise") {
                    sortOption = .date
                    sortAscending = false
                    categoryFilter.removeAll()
                    assignmentFilter.removeAll()
                    gradeFilter.removeAll()
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.medium))
                .foregroundStyle(hasActiveAssignmentControls ? Color.themeAccent : Color.primary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if hasActiveAssignmentControls {
                        Circle()
                            .fill(Color.themeAccent)
                            .frame(width: 7, height: 7)
                    }
                }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Sort and filter assignments")
    }

    private var availableFilterCategories: [String] {
        Array(Set(gradeInfo?.gradebook.map(\.category).filter { $0 != "Final Exam" } ?? []))
            .sorted()
    }

    private var ascendingLabel: String {
        switch sortOption {
        case .date: return "Oldest first"
        case .grade: return "Lowest first"
        case .category: return "A–Z"
        }
    }

    private var descendingLabel: String {
        switch sortOption {
        case .date: return "Newest first"
        case .grade: return "Highest first"
        case .category: return "Z–A"
        }
    }

    private var hasActiveAssignmentControls: Bool {
        sortOption != .date
            || sortAscending
            || !categoryFilter.isEmpty
            || !assignmentFilter.isEmpty
            || !gradeFilter.isEmpty
    }
}

// MARK: - Assignment row

struct AssignmentRow: View {
    var assignment: CalcAssignment
    var editable: Bool
    var onEditGrade: ((Double?) -> Void)?
    var onChangeStatus: ((WhatIfAssignmentStatus) -> Void)? = nil
    var onDelete: (() -> Void)?

    @State private var editingGradeText = ""
    @State private var showingDeleteConfirmation = false
    @FocusState private var gradeFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesStackedLayout: Bool { dynamicTypeSize >= .xxxLarge }

    private var badge: (label: String, color: Color)? {
        if assignment.isMissing { return ("MISSING", .red) }
        if assignment.isNoCount { return ("NO COUNT", .gray) }
        if assignment.isAbsent { return ("ABSENT", .orange) }
        if assignment.artificial { return ("WHAT-IF", Color.themeAccent) }
        return nil
    }

    var body: some View {
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: 10) {
                    assignmentDetails
                    HStack {
                        Spacer(minLength: 0)
                        trailingControls
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    assignmentDetails
                    Spacer(minLength: 8)
                    trailingControls
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.32))
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onAppear {
            editingGradeText = assignment.grade.map { trimNumber($0) } ?? ""
        }
        .onChange(of: assignment.grade) { _, grade in
            guard !gradeFieldFocused else { return }
            editingGradeText = grade.map { trimNumber($0) } ?? ""
        }
        .onChange(of: gradeFieldFocused) { _, focused in
            if !focused { commitGrade() }
        }
        .onDisappear {
            if gradeFieldFocused { commitGrade() }
        }
        .contextMenu {
            if onDelete != nil {
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .alert("Delete what-if assignment?", isPresented: $showingDeleteConfirmation) {
            Button("Delete assignment", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: editable ? .contain : .combine)
        .accessibilityLabel(assignment.name)
        .accessibilityValue(assignmentAccessibilityValue)
    }

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 2) {
            gradeControl
            if assignment.artificial, onChangeStatus != nil {
                statusMenu
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var gradeControl: some View {
        if editable, onEditGrade != nil {
            HStack(spacing: 5) {
                TextField("--", text: $editingGradeText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($gradeFieldFocused)
                    .frame(width: 52, height: 34)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .frame(minHeight: 44)
                    .accessibilityLabel("Points earned")

                Text("/")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(outOfText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 5) {
                Text(gradeText)
                    .foregroundStyle(assignment.grade == nil ? .secondary : .primary)
                Text("/")
                    .foregroundStyle(.tertiary)
                Text(outOfText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .lineLimit(1)
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(WhatIfAssignmentStatus.allCases) { status in
                Button {
                    onChangeStatus?(status)
                } label: {
                    if currentStatus == status {
                        Label(status.rawValue, systemImage: "checkmark")
                    } else {
                        Label(status.rawValue, systemImage: status.systemImage)
                    }
                }
            }
            if onDelete != nil {
                Divider()
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Label("Delete Assignment", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Assignment options")
        .accessibilityValue(currentStatus.rawValue)
    }

    private var currentStatus: WhatIfAssignmentStatus {
        if assignment.isMissing { return .missing }
        if assignment.isAbsent { return .absent }
        if assignment.isNoCount { return .noCount }
        return .counted
    }

    private func commitGrade() {
        let trimmed = editingGradeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onEditGrade?(nil)
        } else if let grade = validNumber(trimmed) {
            onEditGrade?(grade)
        } else {
            editingGradeText = assignment.grade.map { trimNumber($0) } ?? ""
        }
    }

    private var assignmentDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(assignment.name)
                .font(.body.weight(.semibold))
                .strikethrough(assignment.isNoCount)
                .foregroundStyle(assignment.isNoCount ? .secondary : .primary)
                .lineLimit(usesStackedLayout ? nil : 1)
                .layoutPriority(1)

            Group {
                if usesStackedLayout {
                    VStack(alignment: .leading, spacing: 3) {
                        badgeView
                        Text(assignment.category)
                        if !assignment.dueDate.isEmpty {
                            Text("Due \(assignment.dueDate)")
                        }
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            badgeView
                            Text(assignment.category)
                            if !assignment.dueDate.isEmpty {
                                Text("Due \(assignment.dueDate)")
                            }
                        }

                        HStack(spacing: 8) {
                            badgeView
                            if !assignment.dueDate.isEmpty {
                                Text(assignment.dueDate)
                            } else {
                                Text(assignment.category)
                            }
                        }

                        badgeView
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Text(badge.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badge.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var gradeText: String {
        guard let grade = assignment.grade, grade.isFinite else { return "--" }
        return grade >= 100 ? String(format: "%.0f", grade) : String(format: "%.1f", grade)
    }

    private var outOfText: String { trimNumber(assignment.outOf) }

    private var assignmentAccessibilityValue: String {
        var values = [assignment.category]
        if assignment.grade?.isFinite == true {
            values.append("\(gradeText) out of \(outOfText)")
        } else {
            values.append("No grade, \(outOfText) points possible")
        }
        if let badge {
            values.append(badge.label.capitalized)
        }
        if !assignment.dueDate.isEmpty {
            values.append("due \(assignment.dueDate)")
        }
        return values.joined(separator: ", ")
    }

    private func trimNumber(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        if value == value.rounded(),
           value >= Double(Int.min), value <= Double(Int.max) {
            return String(Int(value))
        }
        return String(value)
    }

    private func validNumber(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite, abs(value) <= 1_000_000 else {
            return nil
        }
        return value
    }
}

// MARK: - Add what-if assignment sheet

struct AddAssignmentSheet: View {
    var categories: [String]
    var term: TermLabel
    var onAdd: (WhatIfAssignment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = ""
    @State private var gradeText = ""
    @State private var outOfText = "100"
    @State private var status: WhatIfAssignmentStatus = .counted
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case grade
        case points
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Assignment") {
                    TextField("Assignment name", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .grade }

                    Picker("Category", selection: $category) {
                        ForEach(availableCategories, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section {
                    Picker("Status", selection: $status) {
                        ForEach(WhatIfAssignmentStatus.allCases) { option in
                            Label(option.rawValue, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }

                    LabeledContent("Points earned") {
                        TextField("Optional", text: $gradeText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .grade)
                    }

                    LabeledContent("Points possible") {
                        TextField("100", text: $outOfText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .points)
                    }
                } header: {
                    Text("Score")
                } footer: {
                    Text(statusDescription)
                        .contentTransition(.opacity)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let pointsPossible = parsedPointsPossible else { return }
                        let formatter = DateFormatter()
                        formatter.dateFormat = "M/d/yy"
                        onAdd(WhatIfAssignment(
                            className: "",
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            term: term.shortName,
                            category: category,
                            grade: parsedGrade,
                            outOf: pointsPossible,
                            dueDate: formatter.string(from: Date()),
                            status: status
                        ))
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
            .onAppear {
                if category.isEmpty { category = availableCategories.first ?? "Assignments" }
            }
        }
    }

    private var availableCategories: [String] {
        let unique = Array(Set(categories.filter { !$0.isEmpty })).sorted()
        return unique.isEmpty ? ["Assignments"] : unique
    }

    private var parsedGrade: Double? {
        let value = gradeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let parsed = Double(value), parsed.isFinite, abs(parsed) <= 1_000_000 else {
            return nil
        }
        return parsed
    }

    private var parsedPointsPossible: Double? {
        let value = outOfText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(value), parsed.isFinite,
              parsed > 0, parsed <= 1_000_000 else {
            return nil
        }
        return parsed
    }

    private var canAdd: Bool {
        let gradeIsEmpty = gradeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !category.isEmpty
            && (gradeIsEmpty || parsedGrade != nil)
            && parsedPointsPossible != nil
    }

    private var statusDescription: String {
        switch status {
        case .counted:
            return "Leave points earned empty for an ungraded assignment."
        case .noCount:
            return "Visible in the list, but excluded from the calculated grade."
        case .missing:
            return "Flags this assignment as missing."
        case .absent:
            return "Flags this assignment as absent."
        }
    }
}

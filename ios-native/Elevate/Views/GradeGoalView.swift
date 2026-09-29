import SwiftUI

/// Plans what one class needs for a target grade, for the term its detail
/// screen showed. A quarter solves for one counted score, a new assignment
/// or a chosen ungraded one, holding every other score fixed. A semester
/// solves for the exam under the district's 40/40/20 formula from explicit
/// end-of-quarter assumptions. Official scores are the default; saved
/// what-if edits are included only when chosen. Planning never changes a
/// score; "Try in What-if" saves one local edit only when the class would
/// show exactly this result.
struct GradeGoalView: View {
    let course: UnifiedCourseData
    let term: TermLabel

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .title) private var figureSize: CGFloat = 34

    // Sources, keyed by the gradebook term they came from.
    @State private var infos: [TermLabel: GradeInfoResult] = [:]
    @State private var updatedAt: [TermLabel: Date] = [:]
    @State private var failures: [TermLabel: String] = [:]
    @State private var loading = true
    @State private var refreshing = false
    @State private var originatingRevision: Int?
    @State private var loadID = UUID()

    // Saved local what-if work, read once per appearance.
    @State private var savedWhatIf: [WhatIfAssignment] = []
    @State private var overridesByQuarter: [TermLabel: [String: AssignmentGradeOverride]] = [:]
    @State private var savedExamEstimate: Double?

    // Inputs
    @State private var targetText = "90"
    @State private var basis: Basis = .official
    @State private var mode: ScoreMode?
    @State private var category: String?
    @State private var possibleText = "100"
    @State private var existingID: String?
    @State private var quarterEdits: [TermLabel: String] = [:]
    @State private var hypotheticalExam = false
    @State private var tryRevision = 0
    @FocusState private var focus: Field?

    private enum Basis: Hashable { case official, whatIf }
    private enum ScoreMode: Hashable { case new, existing }
    private enum Field: Hashable {
        case target
        case possible
        case quarter(TermLabel)
    }

    private enum QuarterProgress { case ended, inProgress, notStarted }

    // MARK: - Identity

    private var liveCourse: UnifiedCourseData {
        store.courses?.first { $0.id == course.id } ?? course
    }

    private var classKey: String {
        WhatIfStore.classKey(studentID: course.stuId, className: course.courseName, corNumId: course.corNumId,
                             section: course.section, gbId: course.gbId)
    }

    private var courseName: String {
        ClassNameFormatter.format(course.courseName.replacingOccurrences(of: " ", with: "_"))
    }

    private var examType: String { term == .sm1 ? "EX1" : "EX2" }
    private var examName: String { term == .sm1 ? "Exam 1" : "Exam 2" }
    private var quarters: [TermLabel] { term.whatIfQuarterTerms }

    private var parsedTarget: Double? {
        guard let value = Self.number(targetText), value <= 1_000 else { return nil }
        return value
    }

    private var targetName: String { parsedTarget.map { GradeFormat.upToTwoDecimals($0) } ?? "—" }

    /// "Q1" for a quarter, "Semester 1" for a semester, in short result lines.
    private func termName(_ label: TermLabel) -> String {
        label.isSemester ? label.displayName : label.shortName
    }

    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite,
              value >= 0, value <= 1_000_000 else { return nil }
        return value
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    showsRefresh: !loading,
                    lastUpdated: sourceUpdated,
                    isRefreshing: refreshing && !loading,
                    error: sourceError
                ) {
                    await load(force: true)
                } control: {
                    EmptyView()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(courseName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(term.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)

                if loading && infos[term] == nil {
                    placeholder
                        .padding(.top, 20)
                } else if !term.isSemester, infos[term] == nil {
                    InlineErrorState(
                        title: "Couldn't load this quarter's assignments",
                        message: failures[term] ?? "Try again to plan a goal."
                    ) {
                        await load(force: true)
                    }
                    .padding(.top, 20)
                } else {
                    numberRow("Target grade", note: nil, text: $targetText, field: .target, suffix: "%",
                              identifier: "goal.target")
                        .padding(.top, 12)
                    if parsedTarget == nil {
                        note("Enter a target grade, such as 90.")
                    }
                    InsetDivider()

                    if term.isSemester {
                        semesterInputs
                    } else {
                        quarterInputs
                    }

                    resultSection
                        .padding(.top, Metrics.sectionGap / 2)
                }
            }
            .padding(.horizontal, Metrics.page)
            .padding(.bottom, 32)
            .background {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { focus = nil }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Grade Goal")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("goal.screen")
        .sensoryFeedback(.success, trigger: tryRevision)
        .task(id: "\(store.accountRevision)-\(store.coursesRefreshRevision)") { await load(force: false) }
        .visibleRefreshable { await load(force: true) }
        .onChange(of: focus) { old, new in if old != nil, new == nil { revealAnswer(proxy) } }
        .onChange(of: mode) { _, _ in revealAnswer(proxy) }
        .onChange(of: category) { _, _ in revealAnswer(proxy) }
        .onChange(of: existingID) { _, _ in revealAnswer(proxy) }
        .onChange(of: basis) { _, _ in revealAnswer(proxy) }
        .onChange(of: hypotheticalExam) { _, _ in revealAnswer(proxy) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Text(keyboardSummary).font(.footnote.monospacedDigit()).foregroundStyle(Color.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Button("Done") { focus = nil }
                    .accessibilityIdentifier("goal.keyboard.done")
            }
        }
        }
    }

    private func revealAnswer(_ proxy: ScrollViewProxy) {
        guard focus == nil, result != nil else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            proxy.scrollTo("goal.answer", anchor: dynamicTypeSize.isAccessibilitySize ? .top : .bottom)
        }
    }

    private var keyboardSummary: String {
        guard let result else { return missingInputText }
        switch result.status {
        case .required: return "Need \(GradeFormat.upToTwoDecimals(result.requiredEarned)) / \(GradeFormat.upToTwoDecimals(resultPossible))"
        case .aboveMaximum: return "Above full credit"
        case .alreadyGuaranteed: return "Target reached, even with zero"
        case .fixedResult: return "Posted result: \(GradeFormat.twoDecimals(result.resultingGrade))"
        case .unavailable: return "More information needed"
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                if index > 0 { InsetDivider() }
                SkeletonRow(lines: [SkeletonLine(.body, [12, 16, 10][index])],
                            trailing: [SkeletonLine(.figure(.body), 4)])
            }
        }
        .loadingPlaceholder("Loading grade goal")
    }

    // MARK: - Loading

    /// Read the same quarter sources as class detail, even without local edits.
    private var neededTerms: [TermLabel] {
        guard term.isSemester else { return [term] }
        return [term] + quarters
    }

    private func reloadWhatIf() {
        savedWhatIf = WhatIfStore.assignments(classKey: classKey, term: term)
        overridesByQuarter = Dictionary(uniqueKeysWithValues: quarters.map {
            ($0, WhatIfStore.gradeOverrides(classKey: classKey, term: $0))
        })
        savedExamEstimate = term.isSemester ? WhatIfStore.finalExamGrades(classKey: classKey)[examType] : nil
    }

    /// Cache-first, like the class itself. A refresh keeps what is shown; a
    /// failure falls back to the saved gradebook with its true time.
    private func load(force: Bool) async {
        let revision = store.accountRevision
        if originatingRevision == nil { originatingRevision = revision }
        guard originatingRevision == revision else { dismiss(); return }
        let id = UUID()
        loadID = id
        reloadWhatIf()
        if infos[term] == nil { loading = true }
        refreshing = true
        defer {
            if store.accountRevision == revision, loadID == id {
                refreshing = false
                loading = false
            }
        }
        for source in neededTerms {
            let params = GradeInfoParams(stuId: course.stuId, corNumId: course.corNumId, gbId: course.gbId,
                                         section: course.section, bucket: source.bucket)
            do {
                let info = try await DataService.shared.gradeInfo(params: params, forceRefresh: force)
                guard !Task.isCancelled, store.accountRevision == revision, loadID == id else { return }
                infos[source] = info
                updatedAt[source] = DataService.shared.cachedGradeInfo(params: params)?.updatedAt
                    ?? (store.isUsingSampleData ? Date() : nil)
                failures[source] = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, store.accountRevision == revision, loadID == id else { return }
                failures[source] = error.localizedDescription
                if infos[source] == nil, let saved = DataService.shared.cachedGradeInfo(params: params) {
                    infos[source] = saved.value
                    updatedAt[source] = saved.updatedAt
                }
            }
        }
    }

    /// The oldest time among the sources this plan uses, so the line never
    /// claims fresher data than is shown.
    private var sourceUpdated: Date? {
        var dates = neededTerms.compactMap { infos[$0] != nil ? updatedAt[$0] : nil }
        if term.isSemester, let courses = store.coursesLastUpdated { dates.append(courses) }
        return dates.min()
    }


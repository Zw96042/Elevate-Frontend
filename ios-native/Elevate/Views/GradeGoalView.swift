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

    private var sourceError: String? {
        let messages = neededTerms.compactMap { source -> String? in
            guard infos[source] != nil || term.isSemester, let failure = failures[source] else { return nil }
            return "\(source.displayName): \(failure.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))"
        }
        return messages.isEmpty ? nil : messages.joined(separator: ". ")
    }

    // MARK: - Shared rows

    /// A label with an optional note, and a number in a quiet well. The
    /// field keeps exactly what was typed.
    private func numberRow(
        _ label: String,
        note: String?,
        text: Binding<String>,
        field: Field,
        suffix: String?,
        identifier: String
    ) -> some View {
        let isFocused = focus == field
        let labels = VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.body.weight(isFocused ? .semibold : .regular))
                .foregroundStyle(isFocused ? Color.themeAccent : Color.ink)
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(true)
        let input = HStack(alignment: .firstTextBaseline, spacing: 4) {
            TextField("—", text: text)
                .font(.figure(.body))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focus, equals: field)
                .padding(.horizontal, 10)
                .frame(width: fieldWidth, height: 44)
                .background(Color.well, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                .accessibilityLabel(label)
                .accessibilityHint(note ?? "")
                .accessibilityIdentifier(identifier)
            if let suffix {
                Text(suffix)
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
            }
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    labels
                    input
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    labels.frame(maxWidth: .infinity, alignment: .leading)
                    input
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }

    private func groupLabel(_ title: String) -> some View {
        GroupLabel(title)
            .frame(minHeight: 32, alignment: .bottomLeading)
            .padding(.top, 16)
            .padding(.bottom, 2)
    }

    /// Official or with saved what-if, shown only when there is saved work
    /// that would change the answer.
    @ViewBuilder
    private var basisChoice: some View {
        if whatIfAvailable {
            HStack(spacing: 12) {
                Text("Scores").font(.body).frame(maxWidth: .infinity, alignment: .leading)
                ScopePicker(
                    title: "Scores used",
                    valueName: effectiveBasis == .official ? "Official" : "With what-if",
                    hint: "Choose which scores are held fixed in this plan",
                    identifier: "goal.basis",
                    groups: [ChoiceGroup(title: nil, options: [
                        ChoiceOption(value: Basis.official, title: "Official", note: "Skyward's scores only", identifier: "goal.basis.official"),
                        ChoiceOption(value: Basis.whatIf, title: "With what-if", note: "Includes your saved changes for \(term.displayName)", identifier: "goal.basis.whatIf"),
                    ])], selection: $basis
                )
            }
            .frame(minHeight: 56)
            InsetDivider()
        }
    }

    private var whatIfAvailable: Bool {
        term.isSemester ? quarters.contains(where: quarterHasEffectiveChanges) : quarterWhatIfChanges
    }

    private var effectiveBasis: Basis { whatIfAvailable ? basis : .official }

    // MARK: - Quarter

    private var quarterInfo: GradeInfoResult? { infos[term] }

    private var officialAssignments: [CalcAssignment] {
        guard let quarterInfo else { return [] }
        return AssignmentGradeEdits.assignments(from: quarterInfo, className: course.courseName, term: term)
            .filter { $0.category != "Final Exam" }
    }

    private var quarterAddedWhatIf: [CalcAssignment] {
        savedWhatIf.filter { $0.term == term.shortName }
            .map(WhatIfQuarterMath.assignment(from:))
            .filter { $0.category != "Final Exam" }
    }

    private var quarterWhatIfChanges: Bool {
        guard !term.isSemester, quarterInfo != nil else { return false }
        return !quarterAddedWhatIf.isEmpty
            || AssignmentGradeEdits.hasEffectiveChanges(overridesByQuarter[term] ?? [:], to: officialAssignments)
    }

    /// Every score this scenario holds fixed, with saved what-if work only
    /// when chosen.
    private var scenarioAssignments: [CalcAssignment] {
        switch effectiveBasis {
        case .official:
            return officialAssignments
        case .whatIf:
            return AssignmentGradeEdits.applying(overridesByQuarter[term] ?? [:], to: officialAssignments)
                + quarterAddedWhatIf
        }
    }

    /// Real Skyward assignments without a score that would count.
    private var ungradedCandidates: [CalcAssignment] {
        scenarioAssignments.filter {
            !$0.artificial && $0.grade == nil && !$0.isNoCount && $0.outOf > 0 && $0.category != "Final Exam"
        }
    }

    private var selectedCandidate: CalcAssignment? {
        guard mode == .existing, let existingID else { return nil }
        return ungradedCandidates.first { $0.id == existingID }
    }

    private var isWeighted: Bool { quarterInfo?.gradebook.contains { $0.weight != nil } ?? false }

    /// Categories a new score can count in: weighted ones need weight.
    private var categoryChoices: [GradeCategory] {
        (quarterInfo?.gradebook ?? []).filter { category in
            guard category.category != "Final Exam", !category.category.isEmpty else { return false }
            return !isWeighted || (category.weight ?? 0) > 0
        }
    }

    private var chosenCategory: String? {
        if let category, categoryChoices.contains(where: { $0.category == category }) { return category }
        return categoryChoices.count == 1 ? categoryChoices[0].category : nil
    }

    private var parsedPossible: Double? {
        guard let value = Self.number(possibleText), value > 0 else { return nil }
        return value
    }

    /// Without ungraded work there is only one honest choice, stated as such.
    private var effectiveMode: ScoreMode? {
        ungradedCandidates.isEmpty ? .new : mode
    }

    private var assignmentChoice: (choice: GradeGoalAssignmentChoice, possible: Double)? {
        switch effectiveMode {
        case .new:
            guard let chosenCategory, let parsedPossible else { return nil }
            return (.new(category: chosenCategory, possible: parsedPossible), parsedPossible)
        case .existing:
            guard let selectedCandidate else { return nil }
            return (.existingID(selectedCandidate.id), selectedCandidate.outOf)
        case nil:
            return nil
        }
    }

    private var quarterResult: GradeGoalResult? {
        guard let target = parsedTarget, let quarterInfo, let assignmentChoice else { return nil }
        return GradeGoalSolver.assignment(
            target: target,
            assignments: scenarioAssignments,
            categories: quarterInfo.gradebook,
            choice: assignmentChoice.choice,
            ungradedPolicy: .ignoreUngraded
        )
    }

    @ViewBuilder
    private var quarterInputs: some View {
        basisChoice

        groupLabel("Score to solve for")
        if ungradedCandidates.isEmpty {
            note("No ungraded assignments in \(termName(term)). Planning a new one.")
        } else {
            ChoiceList(
                groups: [ChoiceGroup(title: nil, options: [
                    ChoiceOption(value: ScoreMode.new, title: "A new assignment",
                                 identifier: "goal.mode.new"),
                    ChoiceOption(value: ScoreMode.existing, title: "An ungraded assignment",
                                 note: "\(ungradedCandidates.count) in \(term.displayName)", identifier: "goal.mode.existing"),
                ])],
                isSelected: { $0 == mode },
                choose: { value in
                    Motion.perform(Motion.select(reduceMotion)) { mode = value }
                }
            )
        }

        switch effectiveMode {
        case .new:
            newAssignmentInputs
        case .existing:
            existingAssignmentInput
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var newAssignmentInputs: some View {
        if categoryChoices.isEmpty {
            note("No category here can count a new score.")
        } else {
            GroupLabel("New assignment").padding(.top, 12)
            pickerRow("Category") {
                ScopePicker(
                    title: "Category",
                    valueName: chosenCategory ?? "Choose",
                    hint: "Selects the category the new score counts in",
                    identifier: "goal.category",
                    groups: [ChoiceGroup(title: nil, options: categoryChoices.map { item in
                        ChoiceOption<String?>(
                            value: item.category, title: item.category,
                            note: item.weight.map { "\(GradeFormat.upToTwoDecimals($0))% of grade" } ?? "Points-based",
                            identifier: "goal.category.\(item.category)"
                        )
                    })],
                    selection: Binding(get: { chosenCategory }, set: { category = $0 })
                )
            }
            InsetDivider()
            numberRow("Points possible", note: nil, text: $possibleText, field: .possible, suffix: nil,
                      identifier: "goal.possible")
            if parsedPossible == nil {
                note("Enter the points the assignment is out of.")
            }
        }
    }


    private func pickerRow<Picker: View>(_ title: String, @ViewBuilder picker: () -> Picker) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.body)
                    picker()
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text(title).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                    picker()
                }
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
    }

    private var existingAssignmentInput: some View {
        VStack(alignment: .leading, spacing: 0) {
            InsetDivider()
            pickerRow("Assignment") {
                ScopePicker(
                    title: "Ungraded assignment",
                    valueName: selectedCandidate?.name ?? "Choose",
                    hint: "Selects the ungraded assignment to solve for",
                    identifier: "goal.assignment",
                    groups: [ChoiceGroup(title: nil, options: ungradedCandidates.map { item in
                        ChoiceOption<String?>(
                            value: item.id, title: item.name,
                            note: candidateNote(item),
                            identifier: "goal.assignment.option"
                        )
                    })],
                    selection: Binding(get: { selectedCandidate?.id }, set: { existingID = $0 })
                )
            }
            if let selectedCandidate {
                note(candidateNote(selectedCandidate))
            }
        }
    }

    private func candidateNote(_ assignment: CalcAssignment) -> String {
        var parts = [assignment.category, "out of \(GradeFormat.upToTwoDecimals(assignment.outOf))"]
        if !assignment.dueDate.isEmpty { parts.append("due \(assignment.dueDate)") }
        if assignment.isMissing { parts.append("marked Missing") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Semester

    private func officialQuarter(_ quarter: TermLabel) -> Double? {
        infos[quarter]?.score.flatMap { $0.isFinite ? $0 : nil }
            ?? liveCourse.currentScores.first { $0.bucket == quarter.shortName && $0.score.isFinite }?.score
    }

    private func hasSavedChanges(_ quarter: TermLabel) -> Bool {
        savedWhatIf.contains { $0.term == quarter.shortName } || !(overridesByQuarter[quarter] ?? [:]).isEmpty
    }

    /// Saved work that actually changes a score, when the quarter's source is
    /// loaded; otherwise any saved work counts, since it can't be ruled out.
    private func quarterHasEffectiveChanges(_ quarter: TermLabel) -> Bool {
        guard let info = infos[quarter] else { return hasSavedChanges(quarter) }
        let official = AssignmentGradeEdits.assignments(from: info, className: course.courseName, term: quarter)
            .filter { $0.category != "Final Exam" }
        return savedWhatIf.contains { $0.term == quarter.shortName }
            || AssignmentGradeEdits.hasEffectiveChanges(overridesByQuarter[quarter] ?? [:], to: official)
    }

    /// The value a quarter starts from: Skyward's, or the class's own
    /// what-if estimate when chosen.
    private func basisQuarter(_ quarter: TermLabel) -> Double? {
        switch effectiveBasis {
        case .official:
            return officialQuarter(quarter)
        case .whatIf:
            return WhatIfQuarterMath.quarterTotal(
                term: quarter,
                info: infos[quarter],
                className: course.courseName,
                postedCourseGrade: officialQuarter(quarter),
                whatIfAssignments: savedWhatIf,
                overrides: overridesByQuarter[quarter] ?? [:],
                hasSavedChanges: hasSavedChanges(quarter)
            )
        }
    }

    private func quarterValue(_ quarter: TermLabel) -> Double? {
        if let edit = quarterEdits[quarter] { return Self.number(edit) }
        return basisQuarter(quarter)
    }

    private func isEdited(_ quarter: TermLabel) -> Bool {
        quarterEdits[quarter] != nil && quarterValue(quarter) != basisQuarter(quarter)
    }

    /// Two decimals at rest; the exact value once focused or typed.
    private func quarterText(_ quarter: TermLabel) -> Binding<String> {
        Binding(
            get: {
                if let edit = quarterEdits[quarter] { return edit }
                guard let value = basisQuarter(quarter) else { return "" }
                return focus == .quarter(quarter) ? Self.exactText(value) : GradeFormat.twoDecimals(value)
            },
            set: { quarterEdits[quarter] = $0 }
        )
    }

    static func exactText(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1_000_000 { return String(Int(value)) }
        return String(value)
    }

    private func progress(_ quarter: TermLabel) -> QuarterProgress {
        let order: [TermLabel] = [.q1, .q2, .sm1, .q3, .q4, .sm2]
        guard let current = order.firstIndex(of: AcademicCalendar.currentTerm()),
              let index = order.firstIndex(of: quarter) else { return .inProgress }
        if current > index { return .ended }
        return current == index ? .inProgress : .notStarted
    }

    /// Where a quarter's value comes from, in words, and the whole number
    /// the formula counts. Unfinished quarters are called assumptions.
    private func quarterNote(_ quarter: TermLabel) -> String {
        let value = quarterValue(quarter)
        var text: String
        if isEdited(quarter) {
            text = officialQuarter(quarter).map { "Your assumption. Skyward has \(GradeFormat.twoDecimals($0))." }
                ?? "Your assumption. Skyward has no grade yet."
        } else if effectiveBasis == .whatIf, hasSavedChanges(quarter) {
            text = value == nil ? "What-if unavailable. Enter an assumption." : "What-if estimate."
        } else {
            switch progress(quarter) {
            case .ended:
                text = value == nil ? "Ended without a Skyward grade. Enter one." : "Final."
            case .inProgress:
                text = value == nil ? "No grade yet. Enter the grade you expect." : "Current, assumed to hold."
            case .notStarted:
                text = value == nil ? "Not started. Enter the grade you expect." : "Not started. Skyward's value assumed."
            }
        }
        if let value {
            text += " Counts as \(GradeFormat.upToTwoDecimals(value.rounded()))."
        }
        return text
    }

    /// A quarter's source when it isn't a final Skyward grade, for the line
    /// under the answer; nil for a final grade.
    private func quarterQualifier(_ quarter: TermLabel) -> String? {
        if isEdited(quarter) { return "your assumption" }
        if effectiveBasis == .whatIf, hasSavedChanges(quarter) { return "what-if" }
        switch progress(quarter) {
        case .ended: return nil
        case .inProgress: return "current, assumed to hold"
        case .notStarted: return "not started, assumed"
        }
    }

    private var postedExam: Double? {
        WhatIfQuarterMath.postedExamGrade(semesterInfo: infos[term], course: liveCourse, examType: examType)
    }

    private var semesterResult: GradeGoalResult? {
        guard let target = parsedTarget else { return nil }
        return GradeGoalSolver.semesterExam(
            target: target,
            firstQuarter: quarterValue(quarters[0]),
            secondQuarter: quarterValue(quarters[1]),
            postedExam: hypotheticalExam ? nil : postedExam
        )
    }

    @ViewBuilder
    private var semesterInputs: some View {
        basisChoice

        groupLabel("End-of-quarter grades")
        ForEach(Array(quarters.enumerated()), id: \.element) { index, quarter in
            if index > 0 { InsetDivider() }
            numberRow(quarter.displayName, note: quarterNote(quarter), text: quarterText(quarter),
                      field: .quarter(quarter), suffix: "%", identifier: "goal.quarter.\(quarter.shortName)")
            if quarterEdits[quarter] != nil, basisQuarter(quarter) != nil {
                Button(effectiveBasis == .whatIf ? "Use the what-if estimate" : "Use Skyward's grade") {
                    focus = nil
                    quarterEdits[quarter] = nil
                }
                .buttonStyle(ActionTextButtonStyle())
                .accessibilityIdentifier("goal.quarter.reset.\(quarter.shortName)")
            }
        }

        groupLabel(examName)
        if let postedExam {
            Text("Posted: \(GradeFormat.twoDecimals(postedExam))")
                .font(.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .accessibilityLabel("Posted in Skyward: \(GradeFormat.twoDecimals(postedExam))")
            Toggle(isOn: $hypotheticalExam) {
                Text("Plan a different exam score")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Color.themeAccent)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .accessibilityHint("Solves as if the posted score were replaced. Skyward is never changed.")
            .accessibilityIdentifier("goal.hypotheticalExam")
        } else {
            note(infos[term] == nil
                 ? "Not on the course record. The semester gradebook didn't load to confirm."
                 : "Not posted yet.")
        }
    }

    // MARK: - Result

    private var result: GradeGoalResult? {
        term.isSemester ? semesterResult : quarterResult
    }

    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let result {
                VStack(alignment: .leading, spacing: 0) {
                    outcome(result)
                        .animation(Motion.value(reduceMotion), value: result)
                    if let basis = basisLine(result) {
                        Text(basis)
                            .font(.footnote)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                            .accessibilityIdentifier("goal.basisLine")
                    }
                    tryAction(result)
                        .padding(.top, 12)
                }
                .id("goal.answer")
                assumptions
                    .padding(.top, 12)
            } else {
                Text(missingInputText)
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("goal.result.incomplete")
            }
        }
    }

    /// The next thing needed, one step at a time.
    private var missingInputText: String {
        if parsedTarget == nil { return "Enter a target grade." }
        if term.isSemester { return "Enter both quarter grades." }
        switch effectiveMode {
        case nil: return "Choose a new or ungraded assignment to solve for."
        case .new:
            if categoryChoices.isEmpty { return "A new score can't count in any category here." }
            if chosenCategory == nil { return "Choose the new assignment's category." }
            return "Enter the points the assignment is out of."
        case .existing: return "Choose the ungraded assignment."
        }
    }

    /// "out of 50" for a quarter score; the exam is out of 100.
    private var resultPossible: Double {
        term.isSemester ? 100 : (assignmentChoice?.possible ?? 100)
    }

    /// "Q1", or "Semester 1", the grade a result describes.
    private var gradeName: String { termName(term) }

    @ViewBuilder
    private func outcome(_ result: GradeGoalResult) -> some View {
        let possible = GradeFormat.upToTwoDecimals(resultPossible)
        switch result.status {
        case .required:
            outcomeBlock(
                label: term.isSemester ? "You need on \(examName)" : "You need",
                figure: "\(GradeFormat.upToTwoDecimals(result.requiredEarned)) / \(possible)",
                qualifier: "\(GradeFormat.twoDecimals(result.requiredPercentage))%",
                lines: ["\(gradeName) grade becomes \(GradeFormat.twoDecimals(result.resultingGrade))."]
            )
        case .alreadyGuaranteed:
            outcomeBlock(
                label: "Already reached",
                figure: GradeFormat.twoDecimals(result.resultingGrade),
                qualifier: nil,
                lines: ["Even 0 / \(possible) keeps \(gradeName) at \(GradeFormat.twoDecimals(result.resultingGrade))."]
            )
        case .aboveMaximum:
            outcomeBlock(
                label: "Not reachable with full credit",
                figure: "\(GradeFormat.upToTwoDecimals(result.requiredEarned)) / \(possible)",
                qualifier: "\(GradeFormat.twoDecimals(result.requiredPercentage))%",
                lines: [result.maximumGrade.map { "Above full credit. Full credit gives \(GradeFormat.twoDecimals($0))." }
                    ?? "Above full credit."]
            )
        case .fixedResult:
            outcomeBlock(
                label: "Semester grade with the posted exam",
                figure: GradeFormat.twoDecimals(result.resultingGrade),
                qualifier: nil,
                lines: [result.targetMet
                    ? "Meets \(targetName)."
                    : "Below \(targetName). Plan a different exam score."]
            )
        case .unavailable(let reason):
            outcomeBlock(label: "Can't calculate", figure: nil, qualifier: nil, lines: [unavailableText(reason)])
        }
    }

    private func outcomeBlock(label: String, figure: String?, qualifier: String?, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            if let figure {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(figure)
                        .font(.system(size: min(figureSize, 56), weight: .light).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    if let qualifier {
                        Text(qualifier)
                            .font(.figure(.title3, weight: .regular))
                            .foregroundStyle(Color.muted)
                            .lineLimit(1)
                    }
                }
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenOutcome(figure: figure, qualifier: qualifier, lines: lines))
        .accessibilityIdentifier("goal.result")
    }

    private func spokenOutcome(figure: String?, qualifier: String?, lines: [String]) -> String {
        var parts: [String] = []
        if let figure { parts.append(figure.replacingOccurrences(of: " / ", with: " out of ")) }
        if let qualifier { parts.append(qualifier.replacingOccurrences(of: "%", with: " percent")) }
        return (parts + lines).joined(separator: ", ")
    }

    private func unavailableText(_ reason: GradeGoalResult.UnavailableReason) -> String {
        switch reason {
        case .invalidInput: return "Check the numbers entered. Each must be zero or more."
        case .missingQuarter: return "Enter both quarter grades to solve for the exam."
        case .unresolvedAssignments: return "Other assignments are still ungraded."
        case .assignmentNotFound: return "That assignment is no longer in Skyward's gradebook. Choose another."
        case .excludedAssignment: return "That assignment doesn't count toward the grade."
        case .noEffectiveCategory: return "This category carries no weight, so no score in it changes the grade."
        case .invalidWeights: return "Skyward's category weights for this class can't support a reliable answer."
        case .searchLimit: return "No score within a reasonable range reaches this target."
        }
    }

    // MARK: - Assumptions

    /// Ungraded work, other than the chosen assignment, that the solver
    /// leaves out rather than counting as zero.
    private var otherUngradedCount: Int {
        scenarioAssignments.filter {
            $0.grade == nil && !$0.isNoCount && $0.outOf > 0 && $0.id != selectedCandidate?.id
        }.count
    }

    /// The inputs behind the answer in one line, kept visible: what's held,
    /// what's left out, and which quarter values are assumptions.
    private func basisLine(_ result: GradeGoalResult) -> String? {
        if case .unavailable = result.status { return nil }
        var parts: [String] = []
        if term.isSemester {
            let values = quarters.compactMap { quarter in
                quarterValue(quarter).map { "\(termName(quarter)) \(GradeFormat.upToTwoDecimals($0.rounded()))" }
            }
            guard values.count == quarters.count else { return nil }
            parts.append("\(values.joined(separator: ", ")) after rounding. 40/40/20.")
            for quarter in quarters {
                if let qualifier = quarterQualifier(quarter) {
                    parts.append("\(termName(quarter)): \(qualifier).")
                }
            }
            if postedExam != nil, hypotheticalExam {
                parts.append("Posted exam replaced in this plan only.")
            }
        } else {
            if effectiveBasis == .whatIf { parts.append("With your what-if changes.") }
            parts.append("Other scores held.")
            let others = otherUngradedCount
            if others > 0 { parts.append("\(others) ungraded left out.") }
        }
        return parts.joined(separator: " ")
    }

    private var assumptionLines: [String] {
        var lines: [String] = []
        if term.isSemester {
            lines.append("Semester grade = 40% \(termName(quarters[0])) + 40% \(termName(quarters[1])) + 20% exam. Quarter grades are rounded to whole numbers first, as the district does.")
            if postedExam == nil || hypotheticalExam {
                lines.append("The exam is out of 100, rounded up to the next hundredth.")
            }
            if let savedExamEstimate, effectiveBasis == .whatIf {
                lines.append("Your saved what-if exam estimate (\(GradeFormat.twoDecimals(savedExamEstimate))) isn't used; the exam is what this solves for.")
            }
            if let date = sourceUpdated {
                lines.append("Skyward's scores as of \(date.formatted(date: .abbreviated, time: .shortened)).")
            }
        } else {
            if otherUngradedCount > 0 {
                lines.append("Ungraded assignments are left out, not counted as zero.")
            }
            if isWeighted {
                lines.append("Category weights are shared among categories with graded work, as Skyward does.")
            } else {
                lines.append("Points-based: every counted point weighs the same.")
            }
            lines.append("The score is rounded up to the next hundredth of a point.")
            if let date = updatedAt[term] {
                lines.append("Skyward's scores as of \(date.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
        lines.append("Teachers can still change scores or weights.")
        return lines
    }

    private var assumptions: some View {
        let lines = assumptionLines
        return GPADisclosure(title: "Assumptions", count: lines.count, identifier: "goal.assumptions") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }


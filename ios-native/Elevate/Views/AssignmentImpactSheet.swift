import SwiftUI
import UIKit

/// One official quarter row a tapped assignment can stand for. Semester
/// rows carry semester IDs, so they are matched to their quarter rows;
/// identical rows are offered as explicit choices, never guessed.
struct AssignmentImpactCandidate: Identifiable, Hashable {
    /// Skyward's own row from the quarter gradebook, without local edits.
    var assignment: CalcAssignment
    var quarter: TermLabel

    var id: String { assignment.id }
}

/// Identity captured when Impact opens. Trying a score rechecks it, so a
/// sheet left open across an account or term change writes nothing.
struct AssignmentImpactRequest: Identifiable {
    let id = UUID()
    var accountScope: String
    var classKey: String
    var term: TermLabel
    var title: String
    var category: String
    var dueDate: String
    var candidates: [AssignmentImpactCandidate]
    /// Why no candidate could be found; shown instead of the calculator.
    var unavailableMessage: String?
}

/// How one score on a real Skyward assignment would move the quarter grade,
/// and on a semester view the semester grade, from Skyward's posted scores.
/// Numbers come straight from `AssignmentImpactCalculator`.
struct AssignmentImpactSheet: View {
    var request: AssignmentImpactRequest
    /// Live official sources keyed by quarter short name.
    var quarterSources: [String: WhatIfScenarioSource]
    var semesterSource: WhatIfScenarioSource?
    var whatIfIsOn: Bool
    var canTryInWhatIf: Bool
    /// The class's saved local edits, used only to confirm a replacement.
    var localOverrides: [String: AssignmentGradeOverride]
    /// Writes one local override and turns What-if on. Returns why it
    /// couldn't, or nil once written.
    var onTry: (AssignmentImpactCandidate, Double) -> String?

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 76
    @ScaledMetric(relativeTo: .body) private var wellHeight: CGFloat = 36

    @State private var chosenID: String?
    @State private var text: String
    @State private var focused = false
    @State private var selectionRequest = 0
    @State private var pendingTry: PendingTry?
    @State private var failure: String?

    private struct PendingTry {
        var candidate: AssignmentImpactCandidate
        var earned: Double
        var replacing: AssignmentGradeOverride?
    }

    private enum Entry: Equatable {
        case empty
        case invalid
        case points(Double)

        var enteredPoints: Double? {
            if case .points(let value) = self { return value }
            return nil
        }
    }

    private struct Outcome: Identifiable {
        var term: TermLabel
        /// Nil when the term's official source isn't loaded.
        var result: AssignmentImpactResult?
        var id: String { term.rawValue }
    }

    init(
        request: AssignmentImpactRequest,
        quarterSources: [String: WhatIfScenarioSource],
        semesterSource: WhatIfScenarioSource?,
        whatIfIsOn: Bool,
        canTryInWhatIf: Bool,
        localOverrides: [String: AssignmentGradeOverride],
        onTry: @escaping (AssignmentImpactCandidate, Double) -> String?
    ) {
        self.request = request
        self.quarterSources = quarterSources
        self.semesterSource = semesterSource
        self.whatIfIsOn = whatIfIsOn
        self.canTryInWhatIf = canTryInWhatIf
        self.localOverrides = localOverrides
        self.onTry = onTry
        let single = request.candidates.count == 1 ? request.candidates[0] : nil
        _chosenID = State(initialValue: single?.id)
        _text = State(initialValue: single?.assignment.grade.map(Self.exactText) ?? "")
    }

    private var candidate: AssignmentImpactCandidate? {
        request.candidates.first { $0.id == chosenID }.flatMap(currentCandidate)
    }

    private func currentCandidate(_ captured: AssignmentImpactCandidate) -> AssignmentImpactCandidate? {
        guard let source = quarterSources[captured.quarter.shortName],
              let info = source.quarterGradebooks[captured.quarter.shortName] else { return nil }
        let matches = AssignmentGradeEdits.assignments(from: info, className: source.className,
            term: captured.quarter).filter { $0.id == captured.id }
        guard matches.count == 1, let assignment = matches.first else { return nil }
        return AssignmentImpactCandidate(assignment: assignment, quarter: captured.quarter)
    }

    private var fieldHeight: CGFloat { max(44, wellHeight) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if request.candidates.isEmpty {
                        message(request.unavailableMessage
                                ?? "This assignment isn't in the loaded gradebook. Refresh the class and try again.")
                            .padding(.top, 12)
                    } else {
                        if request.candidates.count > 1 {
                            candidateChoice
                        }
                        if let candidate {
                            calculator(for: candidate)
                        } else if chosenID != nil {
                            message("This assignment isn't available in the current gradebook. Refresh the class and try again.")
                                .padding(.top, 12)
                        }
                    }
                }
                .padding(.horizontal, Metrics.page)
                .padding(.bottom, 24)
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { focused = false }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .softScrollEdges()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Impact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        focused = false
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("impact.close")
                }
            }
            .alert(
                replaceTitle,
                isPresented: Binding(get: { pendingTry != nil }, set: { if !$0 { pendingTry = nil } }),
                presenting: pendingTry
            ) { pending in
                Button("Replace") { commitTry(pending) }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text("What-if will use \(GradeFormat.upToTwoDecimals(pending.earned))/\(GradeFormat.upToTwoDecimals(pending.candidate.assignment.outOf)) instead. Skyward isn't changed.")
            }
        }
        .tint(Color.themeAccent)
        .foregroundStyle(Color.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: chosenID) {
            guard chosenID != nil else { return }
            focusField()
        }
        .onChange(of: store.accountRevision) { _, _ in dismiss() }
        .onChange(of: store.selectedTerm) { _, _ in dismiss() }
    }

    // MARK: Header and choice

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(request.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(headerDetail)
                .font(.subheadline)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("impact.header")
    }

    /// "Labs, Quarter 1, due 10/2/26. Skyward: 16/20"
    private var headerDetail: String {
        let official = candidate?.assignment
        var parts = [official?.category ?? request.category]
        if request.term.isSemester, let candidate {
            parts.append(candidate.quarter.displayName)
        }
        let due = official?.dueDate ?? request.dueDate
        if !due.isEmpty { parts.append("due \(due)") }
        var detail = parts.filter { !$0.isEmpty }.joined(separator: ", ")
        if let official {
            let score = official.grade.map {
                "Skyward: \(GradeFormat.upToTwoDecimals($0))/\(GradeFormat.upToTwoDecimals(official.outOf))"
            } ?? "Not graded in Skyward"
            detail = detail.isEmpty ? score : "\(detail). \(score)"
        }
        return detail
    }

    private var candidateChoice: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Which assignment?")
                .frame(minHeight: 32, alignment: .bottomLeading)
                .padding(.top, 12)
                .padding(.bottom, 4)
            footnote("Skyward lists more than one matching assignment in \(request.term.displayName)'s quarters. Choose the one you mean.")
                .padding(.bottom, 4)
            ChoiceList(
                groups: [ChoiceGroup(title: nil, options: candidateOptions)],
                isSelected: { $0 == chosenID }
            ) { id in
                choose(id)
            }
        }
    }

    private var candidateOptions: [ChoiceOption<String>] {
        request.candidates.enumerated().map { index, candidate in
            let sameQuarter = request.candidates.filter { $0.quarter == candidate.quarter }
            var title = candidate.quarter.displayName
            if sameQuarter.count > 1, let position = sameQuarter.firstIndex(of: candidate) {
                title += ", row \(position + 1) of \(sameQuarter.count)"
            }
            let current = currentCandidate(candidate)
            let score = current.map { current in
                current.assignment.grade.map {
                    "Skyward: \(GradeFormat.upToTwoDecimals($0))/\(GradeFormat.upToTwoDecimals(current.assignment.outOf))"
                } ?? "Not graded in Skyward"
            } ?? "Unavailable in the current gradebook"
            return ChoiceOption(value: candidate.id, title: title, note: score,
                                identifier: "impact.candidate.\(index)")
        }
    }

    // MARK: Calculator

    @ViewBuilder
    private func calculator(for candidate: AssignmentImpactCandidate) -> some View {
        let entry = self.entry
        let earned = entry.enteredPoints
        let outcomes = earned.map { outcomes(for: candidate, earned: $0) } ?? []
        let shared = outcomes.first.flatMap { sharedMessage($0.result, candidate: candidate) }

        GroupLabel("Score")
            .frame(minHeight: 32, alignment: .bottomLeading)
            .padding(.top, Metrics.sectionGap - 8)
            .padding(.bottom, 4)
        scoreRow(candidate)

        switch entry {
        case .empty:
            footnote("Enter points to see how this score changes the grade.")
                .padding(.top, 4)
        case .invalid:
            Text("Enter a number of points.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.gradeAttention)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .accessibilityIdentifier("impact.inputError")
        case .points:
            if let shared {
                message(shared)
                    .padding(.top, 12)
            } else {
                GroupLabel("Result")
                    .frame(minHeight: 32, alignment: .bottomLeading)
                    .padding(.top, Metrics.sectionGap - 8)
                    .padding(.bottom, 4)
                ForEach(Array(outcomes.enumerated()), id: \.element.id) { index, outcome in
                    if index > 0 { InsetDivider() }
                    resultRow(outcome, candidate: candidate)
                }
                if let earned, canTry(candidate, earned: earned, outcomes: outcomes) {
                    Button {
                        requestTry(candidate, earned: earned)
                    } label: {
                        Text("Try in What-if")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .padding(.top, 8)
                    .accessibilityHint("Uses this score in What-if on this iPhone. Skyward isn't changed.")
                    .accessibilityIdentifier("impact.try")
                }
            }
        }

        if let failure {
            Label {
                Text(failure)
            } icon: {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Color.gradeAttention)
            }
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
            .accessibilityIdentifier("impact.error")
        }

        VStack(alignment: .leading, spacing: 6) {
            ForEach(notes(for: candidate, outcomes: shared == nil ? outcomes : []), id: \.self) { note in
                footnote(note)
            }
        }
        .padding(.top, 16)
    }

    /// "If you earn" with a points well like the assignment rows', then
    /// Full credit. The well moves beneath the label at larger text sizes.
    @ViewBuilder
    private func scoreRow(_ candidate: AssignmentImpactCandidate) -> some View {
        let label = Text("If you earn")
            .font(.body)
            .foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
        if dynamicTypeSize >= .xLarge {
            VStack(alignment: .leading, spacing: 8) {
                label
                HStack(spacing: 8) {
                    scoreWell(candidate)
                    fullCreditButton(candidate)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                scoreWell(candidate)
                fullCreditButton(candidate)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
    }

    private func scoreWell(_ candidate: AssignmentImpactCandidate) -> some View {
        let outOf = GradeFormat.upToTwoDecimals(candidate.assignment.outOf)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            AssignmentScoreField(
                text: $text,
                displayText: text,
                focused: $focused,
                selectionRequest: selectionRequest,
                finishRequest: 0,
                placeholder: "Points",
                onCommit: { _ in }
            )
            .padding(.leading, 8)
            .frame(width: fieldWidth, height: fieldHeight)
            .alignmentGuide(.firstTextBaseline) { dimensions in
                let font = UIFontMetrics(forTextStyle: .body).scaledFont(
                    for: .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
                )
                return (dimensions.height - font.lineHeight) / 2 + font.ascender
            }
            .accessibilityLabel("If you earn, points")
            .accessibilityHint("Out of \(outOf) points")
            .accessibilityIdentifier("impact.field")

            Text("/\(outOf)")
                .font(.figure(.subheadline, weight: .regular))
                .foregroundStyle(Color.muted)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, 1)
                .padding(.trailing, 8)
                .frame(height: fieldHeight)
                .accessibilityHidden(true)
        }
        .background {
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(Color.well)
                .padding(.vertical, (fieldHeight - wellHeight) / 2)
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { focusField() }
                .accessibilityHidden(true)
        }
        .fixedSize()
    }

    @ViewBuilder
    private func fullCreditButton(_ candidate: AssignmentImpactCandidate) -> some View {
        let possible = candidate.assignment.outOf
        // A zero-possible bonus row has no full credit to fill in.
        if possible > 0, possible.isFinite {
            Button("Full credit") {
                text = Self.exactText(possible)
                failure = nil
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityHint("Enters \(GradeFormat.upToTwoDecimals(possible)) points")
            .accessibilityIdentifier("impact.fullCredit")
        }
    }

    private func resultRow(_ outcome: Outcome, candidate: AssignmentImpactCandidate) -> some View {
        let title = "\(outcome.term.displayName) estimate"
        let value: Double? = outcome.result?.issue == nil ? outcome.result?.after : nil
        let detail = resultDetail(outcome, candidate: candidate)
        let figure = Text(GradeFormat.twoDecimals(value))
            .font(.figure(.body))
            .foregroundStyle(value == nil ? Color.muted : GradeTier(value).textColor)
            .contentTransition(.numericText(value: value ?? 0))
            .animation(Motion.value(reduceMotion), value: value)
            .lineLimit(1)
        let titleText = Text(title)
            .font(.body)
            .foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
        let detailText = Text(detail)
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                    figure
                    detailText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        titleText
                        detailText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    figure
                        .fixedSize()
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(GradeFormat.spokenCourseGrade(value)), \(detail)")
        .accessibilityIdentifier(outcome.term.isSemester ? "impact.semester" : "impact.quarter")
    }

    // MARK: Values

    private var entry: Entry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let value = Double(trimmed), WhatIfScenarioEvaluator.validNumber(value) else { return .invalid }
        return .points(value)
    }

    /// The quarter result, then on a semester view the semester result. Each
    /// uses its own term's source and official grade.
    private func outcomes(for candidate: AssignmentImpactCandidate, earned: Double) -> [Outcome] {
        func calculate(_ source: WhatIfScenarioSource?) -> AssignmentImpactResult? {
            source.map {
                AssignmentImpactCalculator.calculate(
                    assignmentID: candidate.id, quarter: candidate.quarter, earned: earned, source: $0
                )
            }
        }
        var outcomes = [Outcome(term: candidate.quarter, result: calculate(quarterSources[candidate.quarter.shortName]))]
        if request.term.isSemester {
            outcomes.append(Outcome(term: request.term, result: calculate(semesterSource)))
        }
        return outcomes
    }

    /// Reasons about the assignment itself read once, not per grade row.
    private func sharedMessage(_ result: AssignmentImpactResult?, candidate: AssignmentImpactCandidate) -> String? {
        guard let issue = result?.issue else { return nil }
        switch issue {
        case .excludedAssignment, .unavailableCategory, .assignmentNotFound, .invalidInput, .differentTerm:
            return issueText(issue, candidate: candidate)
        case .unavailableGradebook, .calculation:
            return nil
        }
    }

    private func resultDetail(_ outcome: Outcome, candidate: AssignmentImpactCandidate) -> String {
        guard let result = outcome.result else {
            return outcome.term.isSemester
                ? "Elevate can't calculate \(outcome.term.displayName) until the class gradebook loads. Refresh the class and try again."
                : "\(outcome.term.displayName)'s gradebook hasn't loaded. Refresh the class and try again."
        }
        if let issue = result.issue { return issueText(issue, candidate: candidate) }
        guard let before = result.before, let difference = result.difference else {
            return "Elevate can't calculate this grade from the loaded gradebook."
        }
        if abs(difference) < 0.005 { return "No change from \(GradeFormat.twoDecimals(before))" }
        let direction = difference > 0 ? "up" : "down"
        return "Now \(GradeFormat.twoDecimals(before)), \(direction) \(GradeFormat.twoDecimals(abs(difference)))"
    }

    private func issueText(_ issue: AssignmentImpactResult.UnavailableReason, candidate: AssignmentImpactCandidate) -> String {
        switch issue {
        case .excludedAssignment:
            return "Skyward marks this No count, so its score doesn't change the grade."
        case .unavailableCategory:
            return "Its category has no weight in Skyward, so Elevate can't calculate its effect."
        case .unavailableGradebook:
            return "\(candidate.quarter.displayName)'s gradebook hasn't loaded. Refresh the class and try again."
        case .assignmentNotFound:
            return "This assignment is no longer in the loaded gradebook. Refresh the class and try again."
        case .invalidInput:
            // Entered points are checked before calculating, so this is
            // Skyward's own possible points.
            return "Skyward's possible points for this assignment can't be used."
        case .differentTerm:
            return "Elevate can't match this assignment to \(request.term.displayName)."
        case .calculation(let reason):
            switch reason {
            case .unavailableGradebook(let quarter):
                let name = TermLabel.allCases.first { $0.shortName == quarter }?.displayName ?? quarter
                return "\(name)'s gradebook hasn't loaded. Refresh the class and try again."
            case .staleAssignmentIDs:
                return "This assignment is no longer in the loaded gradebook. Refresh the class and try again."
            case .unavailableCategory(_, let category):
                return "“\(category)” has no weight in Skyward, so Elevate can't calculate its effect."
            default:
                return "Elevate can't calculate this grade from the loaded gradebook."
            }
        }
    }

    private func notes(for candidate: AssignmentImpactCandidate, outcomes: [Outcome]) -> [String] {
        var notes = [whatIfIsOn
            ? "Based on Skyward's posted scores. Your what-if changes aren't included."
            : "Based on Skyward's posted scores."]
        if candidate.assignment.outOf == 0 {
            notes.append("This assignment has no possible points, so points add as extra credit.")
        }
        for outcome in outcomes where outcome.result?.issue == nil {
            for assumption in outcome.result?.assumptions ?? [] where !notes.contains(assumption) {
                notes.append(assumption)
            }
        }
        return notes
    }

    /// Offered only when every shown result is valid and the score would
    /// actually change what What-if uses.
    private func canTry(_ candidate: AssignmentImpactCandidate, earned: Double, outcomes: [Outcome]) -> Bool {
        guard canTryInWhatIf, !outcomes.isEmpty,
              outcomes.allSatisfy({ $0.result != nil && $0.result?.issue == nil }) else { return false }
        let existing = localOverrides[candidate.id]
        if existing?.changesScore(of: candidate.assignment) == true {
            return existing?.grade != earned
        }
        return earned != candidate.assignment.grade
    }

    private var replaceTitle: String {
        guard let replacing = pendingTry?.replacing, let candidate = pendingTry?.candidate else { return "" }
        guard let grade = replacing.grade else { return "Replace your what-if change to no score?" }
        return "Replace your what-if score of \(GradeFormat.upToTwoDecimals(grade))/\(GradeFormat.upToTwoDecimals(candidate.assignment.outOf))?"
    }

    // MARK: Actions

    private func choose(_ id: String) {
        guard let next = request.candidates.first(where: { $0.id == id }).flatMap(currentCandidate) else { return }
        chosenID = id
        text = next.assignment.grade.map(Self.exactText) ?? ""
        failure = nil
    }

    private func focusField() {
        selectionRequest += 1
        focused = true
    }

    /// Confirms only when it would replace a different saved what-if score.
    private func requestTry(_ candidate: AssignmentImpactCandidate, earned: Double) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        focused = false
        failure = nil
        let existing = localOverrides[candidate.id]
        if let existing, existing.changesScore(of: candidate.assignment), existing.grade != earned {
            pendingTry = PendingTry(candidate: candidate, earned: earned, replacing: existing)
        } else {
            commitTry(PendingTry(candidate: candidate, earned: earned, replacing: nil))
        }
    }

    private func commitTry(_ pending: PendingTry) {
        guard store.localAccountScope == request.accountScope, store.selectedTerm == request.term else {
            failure = "The account or term changed while this was open. Nothing was changed."
            return
        }
        guard let current = currentCandidate(pending.candidate) else {
            failure = "This assignment isn't available in the current gradebook. Nothing was changed."
            return
        }
        if let reason = onTry(current, pending.earned) {
            failure = reason
        } else {
            dismiss()
        }
    }

    // MARK: Pieces

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("impact.message")
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The exact stored value for editing, never the rounded display.
    private static func exactText(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }
}

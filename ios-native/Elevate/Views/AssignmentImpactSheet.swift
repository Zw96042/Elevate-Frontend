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


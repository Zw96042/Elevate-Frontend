import SwiftUI

/// Identity captured when the Scenarios sheet opens. Every save, rename,
/// delete and apply rechecks it, so a sheet left open across an account or
/// term change never writes into another scope.
struct WhatIfScenarioSheetContext: Identifiable {
    let id = UUID()
    var accountScope: String
    var classKey: String
    var term: TermLabel
    var courseTitle: String
}

/// The class screen's own what-if state, so "Current changes" shows exactly
/// the estimate on the screen behind the sheet.
struct WhatIfScenarioCurrentState: Equatable {
    var officialValue: Double?
    var hasEffectiveChanges: Bool
    /// The class screen's estimate; nil when it can't be calculated.
    var estimate: Double?
}

/// Named snapshots of one class and term's local what-if changes, compared
/// with Skyward's posted grade. Saved scenarios are estimated against the
/// live official gradebooks by `WhatIfScenarioEvaluator`; one that can't be
/// estimated stays saved unchanged and can't be applied.
struct WhatIfScenariosSheet: View {
    var context: WhatIfScenarioSheetContext
    /// Live official source; nil while the class gradebook isn't loaded.
    var source: WhatIfScenarioSource?
    var current: WhatIfScenarioCurrentState
    var onApplied: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scenarios: [WhatIfScenario] = []
    @State private var classScenarioCount = 0
    @State private var isLibraryUnreadable = false
    @State private var currentSnapshot: WhatIfScenarioSnapshot?
    @State private var nameRequest: NameRequest?
    @State private var nameDraft = ""
    @State private var pendingApply: WhatIfScenario?
    @State private var pendingDelete: WhatIfScenario?
    @State private var confirmingClear = false
    @State private var errorMessage: String?
    @State private var commitRevision = 0

    /// The library's own limits; the sheet only explains them.
    private static let classLimit = 50
    private static let nameLimit = 100

    private enum NameRequest {
        case save
        case rename(WhatIfScenario)

        var isSave: Bool {
            if case .save = self { return true }
            return false
        }
    }

    private var library: WhatIfScenarioLibrary {
        WhatIfScenarioLibrary(accountIdentifier: context.accountScope, defaults: .standard)
    }

    var body: some View {
        let evaluations = evaluationsByID
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(context.courseTitle), \(context.term.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                        .accessibilityIdentifier("scenario.subtitle")

                    if let errorMessage {
                        errorLine(errorMessage)
                            .padding(.top, 12)
                    }

                    GroupLabel("Compare")
                        .frame(minHeight: 32, alignment: .bottomLeading)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    skywardRow
                    if current.hasEffectiveChanges {
                        InsetDivider()
                        currentRow
                    }
                    if !isLibraryUnreadable {
                        ForEach(scenarios) { scenario in
                            VStack(spacing: 0) {
                                InsetDivider()
                                savedRow(scenario, evaluation: evaluations[scenario.id])
                            }
                            .transition(.opacity)
                        }
                    }

                    if isLibraryUnreadable {
                        unreadableSection
                            .padding(.top, 16)
                    } else if scenarios.isEmpty {
                        EmptyStateView(
                            title: "No saved scenarios",
                            message: current.hasEffectiveChanges
                                ? "Save current changes to compare them later."
                                : "Make what-if changes, then save them here."
                        )
                        .accessibilityIdentifier("scenario.empty")
                    }

                    notes
                }
                .padding(.horizontal, Metrics.page)
                .padding(.bottom, 24)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .softScrollEdges()
            .navigationTitle("Scenarios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("scenario.close")
                }
            }
            .alert(
                nameRequest.map { $0.isSave ? "Save Scenario" : "Rename Scenario" } ?? "",
                isPresented: Binding(get: { nameRequest != nil }, set: { if !$0 { nameRequest = nil } }),
                presenting: nameRequest
            ) { request in
                TextField("Name", text: $nameDraft)
                    .accessibilityIdentifier("scenario.name")
                Button(request.isSave ? "Save" : "Rename") { commitName(request) }
                    .disabled(!nameIsValid)
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Up to \(Self.nameLimit) characters.")
            }
            .alert(
                "Replace current changes?",
                isPresented: Binding(get: { pendingApply != nil }, set: { if !$0 { pendingApply = nil } }),
                presenting: pendingApply
            ) { scenario in
                Button("Replace", role: .destructive) { apply(scenario) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(replaceMessage)
            }
            .alert(
                pendingDelete.map { "Delete “\($0.name)”?" } ?? "",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { scenario in
                Button("Delete", role: .destructive) { delete(scenario) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Your current what-if changes aren't affected.")
            }
            .alert("Clear saved scenarios?", isPresented: $confirmingClear) {
                Button("Clear", role: .destructive) { clearUnreadable() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes unreadable scenarios on this iPhone. Current what-if isn't affected.")
            }
        }
        .tint(Color.themeAccent)
        .foregroundStyle(Color.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: commitRevision)
        .onAppear(perform: reload)
        // A different account or term owns different edits; close rather
        // than show, or later write, another scope's scenarios.
        .onChange(of: store.accountRevision) { _, _ in dismiss() }
        .onChange(of: store.selectedTerm) { _, _ in dismiss() }
    }

    // MARK: Rows

    private var skywardRow: some View {
        compareRow(
            title: "Skyward",
            detail: current.officialValue == nil ? "No posted grade yet" : "Posted grade",
            value: current.officialValue,
            identifier: "scenario.skyward"
        ) { EmptyView() }
    }

    private var currentRow: some View {
        compareRow(
            title: "Current changes",
            detail: currentDetail,
            value: current.estimate,
            identifier: "scenario.current"
        ) {
            Button {
                beginSave()
            } label: {
                Text("Save…")
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(!canSave)
            .accessibilityLabel("Save current changes as a scenario")
            .accessibilityIdentifier("scenario.save")
        }
    }

    private var currentDetail: String {
        guard let estimate = current.estimate else { return "Can't estimate from the loaded gradebooks" }
        return comparison(estimate, official: current.officialValue) ?? "Estimate"
    }

    @ViewBuilder
    private func savedRow(_ scenario: WhatIfScenario, evaluation: WhatIfScenarioEvaluation?) -> some View {
        let issue = evaluation?.issue
        let readable = issue.map { !Self.isUnreadable($0) } ?? true
        let canApply = source != nil && evaluation != nil && issue == nil
        let inUse = currentSnapshot != nil && currentSnapshot == scenario.snapshot
        compareRow(
            title: scenario.name,
            detail: savedDetail(scenario, evaluation: evaluation, inUse: inUse),
            value: canApply ? evaluation?.value : nil,
            check: inUse,
            identifier: "scenario.row.\(scenario.id)",
            hint: canApply && !inUse ? "Applies this scenario" : nil,
            action: canApply ? { requestApply(scenario) } : nil
        ) {
            Menu {
                if readable {
                    Button { requestApply(scenario) } label: {
                        Label("Apply", systemImage: "arrow.down.circle")
                    }
                    .disabled(!canApply)
                    .accessibilityIdentifier("scenario.apply.\(scenario.id)")
                    Button { beginRename(scenario) } label: {
                        Label("Rename…", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("scenario.rename.\(scenario.id)")
                    Divider()
                }
                Button(role: .destructive) { pendingDelete = scenario } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("scenario.delete.\(scenario.id)")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Options for \(scenario.name)")
            .accessibilityIdentifier("scenario.menu.\(scenario.id)")
        }
    }

    private func savedDetail(_ scenario: WhatIfScenario, evaluation: WhatIfScenarioEvaluation?, inUse: Bool) -> String {
        guard source != nil, let evaluation else { return "Waiting for this class's gradebook" }
        if let issue = evaluation.issue { return Self.issueText(issue) }
        if inUse { return "In use" }
        let saved = "Saved \(Self.savedDate(scenario.createdAt))"
        guard let value = evaluation.value,
              let change = comparison(value, official: evaluation.officialValue) else { return saved }
        return "\(saved), \(change)"
    }

    /// An open row: the name and detail, the figure trailing, and an optional
    /// control after it. At accessibility sizes the figure and control move
    /// beneath the text.
    @ViewBuilder
    private func compareRow<Accessory: View>(
        title: String,
        detail: String,
        value: Double?,
        check: Bool? = nil,
        identifier: String,
        hint: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        let spoken = "\(GradeFormat.spokenCourseGrade(value)), \(detail)"
        let content = compareContent(title: title, detail: detail, value: value, check: check)
        let main = Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(RowPressStyle())
                    .accessibilityLabel(title)
                    .accessibilityValue(spoken)
                    .accessibilityHint(hint ?? "")
            } else {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(spoken)
            }
        }
        .accessibilityAddTraits(check == true ? .isSelected : [])
        .accessibilityIdentifier(identifier)


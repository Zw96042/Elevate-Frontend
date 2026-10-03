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


import SwiftUI

/// Credits toward graduation and planned semesters, kept on this iPhone.
/// Pushed from the GPA screen's Planning group. Earned credits are estimated
/// automatically from completed Skyward semesters, and expected credits from
/// classes Skyward lists as current enrollment. Expected credits are never
/// shown as earned. Every figure comes from `CoursePlanner.calculate` and this
/// view only formats it. Nothing here changes Skyward, official grades, or
/// the district GPA.
struct CoursePlanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var originScope: String?
    @State private var originRevision: Int?
    @State private var hasCapturedOrigin = false
    @State private var sheet: CoursePlanSheet?
    @State private var showingResetConfirmation = false
    @State private var correctionError: String?
    @State private var isRetrying = false
    @State private var commits = 0

    private var planning: StudentPlanningStore { store.planning }

    var body: some View {
        Group {
            if !store.canShowData || planning.accountScope == nil {
                ScrollView {
                    EmptyStateView(
                        title: "Course plan needs an account",
                        message: "Connect Skyward to keep a course plan on this iPhone."
                    )
                    .padding(.horizontal, Metrics.page)
                    .accessibilityIdentifier("plan.noAccount")
                }
            } else if planning.planUnavailable {
                recovery
            } else {
                content(PlanReport.current(store))
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Course Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("plan.screen")
        .onAppear {
            // The account this screen opened for; every save checks it again.
            guard !hasCapturedOrigin else { return }
            hasCapturedOrigin = true
            originScope = store.localAccountScope
            originRevision = store.accountRevision
        }
        .onChange(of: store.accountRevision) { _, _ in
            sheet = nil
            showingResetConfirmation = false
            dismiss()
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .entry(let request):
                CoursePlanEntrySheet(request: request, originScope: originScope, originRevision: originRevision) {
                    commits += 1
                }
            case .correction(let request):
                TranscriptCorrectionSheet(request: request, originScope: originScope, originRevision: originRevision) {
                    commits += 1
                }
            }
        }
        .confirmationDialog("Reset course plan?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { resetUnreadablePlan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the saved course plan on this iPhone and starts an empty one. Official grades and GPA aren't affected.")
        }
        .sensoryFeedback(.success, trigger: commits)
    }

    // MARK: - Unreadable plan

    /// A saved plan that fails to decode or validate is never shown, merged,
    /// or overwritten. Only an explicit reset removes it.
    private var recovery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Course plan can't be read")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("The course plan saved on this iPhone couldn't be read, so Elevate isn't showing or changing it. Resetting deletes it and starts an empty plan.")
                    .font(.body)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showingResetConfirmation = true
                } label: {
                    Text("Reset course plan…")
                        .foregroundStyle(Color.gradeAttention)
                }
                .buttonStyle(ActionTextButtonStyle())
                .accessibilityIdentifier("plan.recovery.reset")
            }
            .frame(maxWidth: 440, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plan.recovery")
            .padding(.horizontal, Metrics.page)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }


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

    private func resetUnreadablePlan() {
        guard let originScope, store.localAccountScope == originScope,
              planning.accountScope == originScope, originRevision == store.accountRevision else { return }
        planning.resetCoursePlan(expectedAccountScope: store.localAccountScope)
        commits += 1
    }

    // MARK: - Content

    /// Where the planner's semester records come from.
    private enum TranscriptSource {
        /// The full transcript projection; an empty one is a verified
        /// transcript with no completed semesters.
        case skyward
        /// No projection yet, so the planner falls back to posted semesters
        /// already saved with the account's courses.
        case savedSemesters
        /// Neither exists, so there is no estimate to show.
        case unavailable
    }

    private var transcriptSource: TranscriptSource {
        if store.planningTranscriptCourses != nil { return .skyward }
        return hasSavedPostedSemesters ? .savedSemesters : .unavailable
    }

    /// A saved transcript-history course with a posted SM1 or SM2 grade and a
    /// verified school year. Quarter grades and live-only courses don't
    /// count, so a missing history never shows as zero credits.
    private var hasSavedPostedSemesters: Bool {
        (store.courses ?? []).contains { course in
            course.isPlanningOnly != true && course.isTranscriptRecord != false
                && (course.isTranscriptRecord == true || course.postedHistoricalGrades != nil)
                && course.academicYearIsVerified != false
                && AcademicYearKey.startYear(course.academicYear ?? "") != nil
                && CourseHistoryDisplay.hasPostedSemesterGrades(course.postedGrades)
        }
    }

    private func content(_ report: CoursePlanReport) -> some View {
        let source = transcriptSource
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if source != .unavailable {
                    StatusStrip(
                        lastUpdated: store.coursesLastUpdated,
                        isRefreshing: store.coursesLoading,
                        error: store.coursesError
                    ) {
                        await store.refreshCourses(force: true)
                    }
                }
                earnedSection(report, source: source)
                    .padding(.top, 4)
                // Current enrollment comes from live courses, not the
                // transcript, so it shows whether or not the transcript loaded.
                currentSection(report, source: source)
                    .padding(.top, Metrics.sectionGap)
                if source != .unavailable {
                    subjectsSection(report)
                        .padding(.top, Metrics.sectionGap)
                }
                plannedSection(report)
                    .padding(.top, Metrics.sectionGap)
                addedCreditsSection(report)
                    .padding(.top, Metrics.sectionGap)
                if source != .unavailable {
                    semesterDetails(report)
                        .padding(.top, Metrics.sectionGap / 2)
                    orphanedCorrections(report, source: source)
                }
                footer(report)
                    .padding(.top, 16)
            }
            .padding(.horizontal, Metrics.page)
            .padding(.bottom, 32)
        }
        .visibleRefreshable { await store.refreshCourses(force: true) }
    }

    // MARK: - Footer

    /// One line, then the method and its sources behind a collapsed
    /// disclosure.
    private func footer(_ report: CoursePlanReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Estimates saved on this iPhone. Not an official graduation check.")
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("plan.explanation")
            GPADisclosure(title: "How credits are estimated", identifier: "plan.method") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Earned credits are estimated from completed semesters on your Skyward transcript. Expected and planned credits assume you pass those classes; they aren't earned until Skyward posts semester grades. None of this is an official transcript or graduation check. Corrections and plans stay on this iPhone and never change Skyward.")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                    ForEach(Array(report.sources.enumerated()), id: \.element.id) { index, source in
                        if let url = URL(string: source.url) {
                            if index > 0 { InsetDivider() }
                            sourceLink(source, url: url)
                                .accessibilityIdentifier("plan.source.\(index)")
                        }
                    }
                }
            }
        }
    }


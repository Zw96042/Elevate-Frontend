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

    /// A source row: its title and site, opening in the browser.
    private func sourceLink(_ source: CoursePlanSource, url: URL) -> some View {
        Link(destination: url) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    Text(url.host() ?? source.url)
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens in Safari")
    }

    // MARK: - Earned credits

    private func earnedSection(_ report: CoursePlanReport, source: TranscriptSource) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Earned credits")
            if source == .unavailable {
                transcriptUnavailable
            } else {
                creditTotal(report, source: source)
            }
        }
    }

    private func creditTotal(_ report: CoursePlanReport, source: TranscriptSource) -> some View {
        let total = "\(PlanFormat.credits(report.earnedTotal)) of \(PlanFormat.credits(report.path.totalRequired)) credits"
        var details: [String] = []
        if source == .skyward { details.append("Estimated from completed Skyward semesters.") }
        details += PlanFormat.outlook(report)
        let review = report.transcriptCredits.unresolved.count
        return VStack(alignment: .leading, spacing: 2) {
            Text(total)
                .font(.figure(.title3))
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText())
            if source == .savedSemesters {
                Text("Using saved high-school semesters. Refresh to include older records.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
            }
            if !details.isEmpty {
                Text(details.joined(separator: " "))
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
            }
            if review > 0 {
                Text("\(review) \(review == 1 ? "semester needs" : "semesters need") review")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ink)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.creditTotal")
    }

    /// Without transcript rows or saved posted semesters there is no
    /// estimate, so no total or subject figures are shown rather than zeros.
    private var transcriptUnavailable: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.coursesLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text("Loading completed semesters")
                }
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            } else {
                Text("Credit totals are unavailable")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ink)
                Text(unavailableDetail)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                Button {
                    Task {
                        guard !isRetrying else { return }
                        isRetrying = true
                        await store.refreshCourses(force: true)
                        isRetrying = false
                    }
                } label: {
                    Text("Try again")
                }
                .buttonStyle(ActionTextButtonStyle())
                .disabled(isRetrying)
                .accessibilityIdentifier("plan.transcript.retry")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.transcript.unavailable")
    }

    private var unavailableDetail: String {
        guard let error = store.coursesError?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty else {
            return "Credits are estimated from your Skyward transcript, which hasn't loaded."
        }
        let reason = error.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return "Your Skyward transcript couldn't load. \(reason)."
    }

    private func subjectsSection(_ report: CoursePlanReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("By subject for the \(report.path.title)")
                .accessibilityIdentifier("plan.pathway")
            if report.currentTotal > 0 || report.plannedTotal > 0 {
                Text("Figures are earned. More needed assumes current and planned classes pass.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("plan.requirement.note")
            }
            ForEach(Array(report.requirements.enumerated()), id: \.element.id) { index, requirement in
                if index > 0 { InsetDivider() }
                requirementRow(requirement)
            }
        }
    }

    /// The figure is earned credit only; current and planned credits are
    /// listed beside it and only reduce what's still needed.
    private func requirementRow(_ requirement: CoursePlanRequirementProgress) -> some View {
        var parts = ["\(PlanFormat.credits(requirement.earned)) earned"]
        if requirement.current > 0 { parts.append("\(PlanFormat.credits(requirement.current)) current") }
        if requirement.planned > 0 { parts.append("\(PlanFormat.credits(requirement.planned)) planned") }
        let note: String?
        if requirement.remaining > 0 {
            note = "\(PlanFormat.credits(requirement.remaining)) more needed"
        } else if requirement.earnedRemaining > 0 {
            note = "Met if completed"
        } else {
            note = nil
        }
        return PlanValueRow(
            title: requirement.subject.title,
            detail: parts.joined(separator: ", "),
            value: "\(PlanFormat.credits(requirement.earned)) of \(PlanFormat.credits(requirement.required))",
            valueNote: note,
            identifier: "plan.requirement.\(requirement.subject.rawValue)"
        )
    }

    // MARK: - Semester records

    /// Counted and unresolved records once each, in the planner's order.
    private func semesterRecords(_ report: CoursePlanReport) -> [TranscriptCreditRecord] {
        var seen = Set<String>()
        return (report.transcriptCredits.records + report.transcriptCredits.unresolved).filter {
            // Ordinary middle-school schedules aren't graduation-credit work.
            // Source records and explicit corrections remain in the calculator.
            !($0.status == .excluded && ($0.gradeYear ?? 9) < 9) && seen.insert($0.id).inserted
        }
    }

    @ViewBuilder
    private func semesterDetails(_ report: CoursePlanReport) -> some View {
        let records = semesterRecords(report)
        let review = report.transcriptCredits.unresolved.count
        if records.isEmpty {
            EmptyStateView(
                title: "No completed semesters yet",
                message: "Credits appear here after Skyward posts semester grades."
            )
            .accessibilityIdentifier("plan.transcript.empty")
        } else {
            GPADisclosure(
                title: "Semester credits",
                note: review > 0 ? "\(review) \(review == 1 ? "needs" : "need") review" : nil,
                count: records.count,
                identifier: "plan.transcript"
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(TranscriptYearGroup.groups(records).enumerated()), id: \.element.id) { index, group in
                        GroupLabel(group.title)
                            .padding(.top, index > 0 ? 16 : 0)
                        ForEach(Array(group.records.enumerated()), id: \.element.id) { recordIndex, record in
                            if recordIndex > 0 { InsetDivider() }
                            recordRow(record)
                        }
                    }
                }
            }
        }
    }


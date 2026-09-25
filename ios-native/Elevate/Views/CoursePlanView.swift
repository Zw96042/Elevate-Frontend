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

    private func recordRow(_ record: TranscriptCreditRecord) -> some View {
        let needsReview = record.status == .needsReview
        let value = needsReview ? "Review" : PlanFormat.credits(record.credits)
        let detail = "\(record.semester.displayName), \(record.subject?.title ?? "No subject")"
        let status = record.status == .estimated
            ? nil
            : [record.status.rawValue, record.detail.trimmingCharacters(in: .whitespacesAndNewlines)]
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
        let compact = dynamicTypeSize.isAccessibilitySize
        return Button {
            sheet = .correction(TranscriptCorrectionRequest(
                record: record,
                correction: planning.coursePlan.creditOverrides.first { $0.id == record.id }
            ))
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    Text(compact ? "\(detail), \(value)" : detail)
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                    if let status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(needsReview ? Color.gradeAttention : Color.muted)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !compact {
                    Text(value)
                        .font(.figure(.body))
                        .foregroundStyle(Color.ink)
                        .fixedSize()
                }
                RowChevron()
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.name)
        .accessibilityValue(([needsReview ? "Needs review" : PlanFormat.creditCount(record.credits), detail] + [status].compactMap { $0 })
            .joined(separator: ". "))
        .accessibilityHint("Opens credit and subject correction")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("plan.transcript.\(record.id)")
    }

    /// Corrections whose semester is no longer on the transcript are listed
    /// and never applied to another record. Saved semesters are only part of
    /// the transcript, so there they're kept without offering removal.
    @ViewBuilder
    private func orphanedCorrections(_ report: CoursePlanReport, source: TranscriptSource) -> some View {
        let orphans = report.transcriptCredits.orphanedOverrideIDs.compactMap { id in
            planning.coursePlan.creditOverrides.first { $0.id == id }
        }
        if !orphans.isEmpty, source == .savedSemesters {
            VStack(alignment: .leading, spacing: 0) {
                GroupLabel("Corrections not applied")
                Text(orphans.count == 1
                     ? "1 saved correction is for a record that isn't loaded. Refresh to apply it."
                     : "\(orphans.count) saved corrections are for records that aren't loaded. Refresh to apply them.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan.correction.pending")
            }
            .padding(.top, 16)
        } else if !orphans.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                GroupLabel("Corrections not applied")
                Text("These semesters are no longer on your Skyward transcript, so their corrections aren't counted.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                ForEach(Array(orphans.enumerated()), id: \.element.id) { index, correction in
                    if index > 0 { InsetDivider() }
                    orphanRow(correction)
                }
                if let correctionError {
                    Label(correctionError, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.gradeAttention)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .accessibilityIdentifier("plan.correction.error")
                }
            }
            .padding(.top, 16)
        }
    }

    private func orphanRow(_ correction: TranscriptCreditOverride) -> some View {
        let detail = "\(PlanFormat.creditCount(correction.credits)), \(correction.subject.title)"
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved correction")
                    .font(.body)
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button("Remove") { removeOrphan(correction.id) }
                .buttonStyle(ActionTextButtonStyle())
                .accessibilityLabel("Remove saved correction, \(detail)")
                .accessibilityIdentifier("plan.correction.orphan.\(correction.id)")
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    }

    private func removeOrphan(_ id: String) {
        let outcome = CoursePlanCommit.apply(store: store, originScope: originScope, originRevision: originRevision) { plan in
            let before = plan.creditOverrides.count
            plan.creditOverrides.removeAll { $0.id == id }
            return plan.creditOverrides.count < before
        }
        switch outcome {
        case .saved:
            correctionError = nil
            commits += 1
        case .accountChanged:
            dismiss()
        case .rejected:
            correctionError = "Couldn't remove this correction. Nothing was changed."
        }
    }

    // MARK: - Added and planned entries

    private var recordCount: Int {
        planning.coursePlan.earnedCourses.count + planning.coursePlan.plannedCourses.count
    }

    private var isFull: Bool { recordCount >= CoursePlanEntryKind.recordLimit }

    /// Entries the planner counts, then every entry it holds: ones saved
    /// before automatic estimates, ones Skyward already lists, and invalid
    /// ones. The split follows the report, never the entry's own flag, so a
    /// course isn't counted twice. Nothing is deleted automatically.
    private func addedCreditsSection(_ report: CoursePlanReport) -> some View {
        let countedIDs = Set(report.manualEarnedCourses.map(\.id))
        let added = planning.coursePlan.earnedCourses.filter { countedIDs.contains($0.id) }
        let saved = planning.coursePlan.earnedCourses.filter { !countedIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Credits not in Skyward", count: added.isEmpty ? nil : "\(added.count)") {
                Button {
                    sheet = .entry(CoursePlanEditRequest(kind: .earned, course: nil))
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(isFull)
                .accessibilityLabel("Add a credit not in Skyward")
                .accessibilityIdentifier("plan.add.earned")
            }
            Text("Credit by exam or from another school.")
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            ForEach(Array(added.enumerated()), id: \.element.id) { index, course in
                if index > 0 { InsetDivider() }
                entryRow(course, kind: .earned, report: report, identifier: "plan.edit.earned.\(index)")
            }
            if !saved.isEmpty {
                if !added.isEmpty { InsetDivider() }
                GPADisclosure(
                    title: "Review saved credits",
                    note: "Not counted, so nothing is counted twice",
                    count: saved.count,
                    identifier: "plan.review"
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(saved.enumerated()), id: \.element.id) { index, course in
                            if index > 0 { InsetDivider() }
                            entryRow(course, kind: .earned, report: report, identifier: "plan.edit.review.\(index)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Current classes

    /// Classes Skyward lists as current enrollment. Expected credit only
    /// reduces what's still needed. A class the planner can't credit stays
    /// listed with its reason under review, never as zero earned.
    private func currentSection(_ report: CoursePlanReport, source: TranscriptSource) -> some View {
        let expected = report.currentCourses.filter { $0.status == .expected }
        let held = report.currentCourses.filter { $0.status != .expected }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Currently taking", count: report.currentCourses.isEmpty ? nil : "\(report.currentCourses.count)")
            if report.currentCourses.isEmpty {
                currentEmpty
            } else {
                currentTotal(report, source: source)
                    .padding(.bottom, 4)
                ForEach(Array(expected.enumerated()), id: \.element.id) { index, course in
                    if index > 0 { InsetDivider() }
                    currentRow(course, report: report)
                }
                if !held.isEmpty {
                    if !expected.isEmpty { InsetDivider() }
                    GPADisclosure(
                        title: "Not counted yet",
                        note: heldNote(held),
                        count: held.count,
                        identifier: "plan.current.review"
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(held.enumerated()), id: \.element.id) { index, course in
                                if index > 0 { InsetDivider() }
                                currentRow(course, report: report)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.currentCourses")
    }

    private func currentTotal(_ report: CoursePlanReport, source: TranscriptSource) -> some View {
        var notes = ["Not earned until Skyward posts semester grades."]
        if source == .unavailable {
            notes.append("Completed semesters haven't loaded, so earlier credit can't be ruled out.")
        }
        return VStack(alignment: .leading, spacing: 2) {
            if report.currentTotal > 0 {
                Text("\(PlanFormat.creditCount(report.currentTotal)) expected if you pass")
                    .font(.figure(.body))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
            } else {
                Text("No expected credits yet")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ink)
            }
            Text(notes.joined(separator: " "))
                .font(.footnote)
                .foregroundStyle(Color.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.currentTotal")
    }

    private func heldNote(_ held: [CurrentCourseCredit]) -> String {
        let review = held.filter { $0.status == .needsReview }.count
        if review == held.count { return review == 1 ? "Needs review" : "All need review" }
        if review == 0 { return "No credit expected" }
        return "\(review) \(review == 1 ? "needs" : "need") review"
    }

    @ViewBuilder
    private var currentEmpty: some View {
        if store.courses == nil, store.coursesLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Loading current classes")
            }
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("plan.current.loading")
        } else if store.courses == nil {
            EmptyStateView(
                title: "Current classes aren't available",
                message: "They appear here once your Skyward classes load."
            )
            .accessibilityIdentifier("plan.current.unavailable")
        } else {
            EmptyStateView(
                title: "No current classes",
                message: "This school year's classes appear here with their expected credit."
            )
            .accessibilityIdentifier("plan.current.empty")
        }
    }

    /// The planner's reason a current class isn't expected to earn credit,
    /// shortened where its known wording maps to a plain fact. Any other
    /// wording is shown in full.
    private func currentReason(_ course: CurrentCourseCredit, report: CoursePlanReport) -> String {
        let detail = course.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.hasPrefix("Current enrollment evidence is unavailable") { return "Enrollment not confirmed for this semester." }
        if detail.hasPrefix("The enrolled semester is unknown") { return "Semester unknown or conflicting." }
        if detail.hasPrefix("This pre-high-school enrollment") { return "Not high-school credit." }
        if detail.hasPrefix("Course subject or credit value is not recognized") { return "Not in the district catalog." }
        if detail.hasPrefix("Source grade level is unavailable") { return "Grade level unavailable or conflicting." }
        if detail.hasPrefix("This course is not a recognized credit-bearing course") { return "No credit at this grade level." }
        if detail.hasPrefix("The enrolled semesters have ended") {
            // The planner caps PE at 4 credits; at the cap, that is the reason.
            if course.subject == .physicalEducation {
                let expectedPE = report.currentCourses
                    .filter { $0.status == .expected && $0.subject == .physicalEducation }
                    .reduce(0) { $0 + $1.credits }
                if report.transcriptCredits.credits(for: .physicalEducation) + expectedPE >= 4 {
                    return "PE credit limit (4) reached."
                }
            }
            return "Semesters ended or credit already counted."
        }
        return detail
    }

    /// Name, then subject, semesters and school year. Only an expected class
    /// shows a figure; others show the planner's status and a short reason.
    private func currentRow(_ course: CurrentCourseCredit, report: CoursePlanReport) -> some View {
        let expected = course.status == .expected
        let source = [course.subject?.title ?? "No subject", PlanFormat.semesters(course.semesters),
                      PlanFormat.enrollmentYear(course.academicYear)].joined(separator: ", ")
        let status: String?
        if expected {
            if let subject = course.subject, subject != .elective,
               report.requirements.first(where: { $0.subject == subject })?.earnedRemaining == 0 {
                status = "Requirement met; counts toward electives."
            } else { status = nil }
        } else {
            let reason = currentReason(course, report: report)
            if course.status == .needsReview {
                status = reason.isEmpty ? "Needs review." : "Needs review. \(reason)"
            } else {
                status = reason.isEmpty ? course.status.rawValue : reason
            }
        }
        let compact = dynamicTypeSize.isAccessibilitySize
        let spokenCredits = "\(PlanFormat.creditCount(course.credits)) expected if passed"
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                Text(compact && expected ? "\(source), \(PlanFormat.creditCount(course.credits)) expected" : source)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(course.status == .needsReview ? Color.gradeAttention : Color.muted)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if expected, !compact {
                Text(PlanFormat.credits(course.credits))
                    .font(.figure(.body))
                    .foregroundStyle(Color.ink)
                    .fixedSize()
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(course.name)
        .accessibilityValue(([expected ? spokenCredits : nil, source, status].compactMap { $0 }).joined(separator: ". "))
        .accessibilityIdentifier("plan.current.\(course.id)")
    }

    // MARK: - Planned entries

    private func plannedSection(_ report: CoursePlanReport) -> some View {
        let courses = planning.coursePlan.plannedCourses
        let held = report.manualPlannedReviewCourses.count
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Planned semesters", count: courses.isEmpty ? nil : "\(courses.count)") {
                Button {
                    sheet = .entry(CoursePlanEditRequest(kind: .planned, course: nil))
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(isFull)
                .accessibilityLabel("Add planned semester")
                .accessibilityIdentifier("plan.add.planned")
            }

            if isFull {
                Text("You can keep up to \(CoursePlanEntryKind.recordLimit) entries in a plan.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }

            if held > 0 {
                Text(held == 1
                     ? "1 planned semester matches a current class and isn't counted. Edit it to choose a future year or semester."
                     : "\(held) planned semesters match current classes and aren't counted. Edit each to choose a future year or semester.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("plan.planned.review")
            }

            if courses.isEmpty {
                EmptyStateView(
                    title: "No planned semesters",
                    message: "Add each future semester. Credits assume you pass."
                )
                .accessibilityIdentifier("plan.empty.planned")
            } else {
                ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                    if index > 0 { InsetDivider() }
                    entryRow(course, kind: .planned, report: report, identifier: "plan.edit.planned.\(index)")
                }
            }
        }
    }

    private func entryRow(_ course: CoursePlanCourse, kind: CoursePlanEntryKind, report: CoursePlanReport, identifier: String) -> some View {
        let detail = entryDetail(course, kind: kind, report: report)
        return Button {
            sheet = .entry(CoursePlanEditRequest(kind: kind, course: course))
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                RowChevron()
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(course.name)
        .accessibilityValue(detail)
        .accessibilityHint("Edits this entry")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    /// "Mathematics, 0.5 credit", any saved semester and school year, then
    /// the report's counting status and any reason the calculator set the
    /// entry's credits aside.
    private func entryDetail(_ course: CoursePlanCourse, kind: CoursePlanEntryKind, report: CoursePlanReport) -> String {
        var text = "\(course.subject.title), \(PlanFormat.creditCount(course.credits))"
        if let semester = course.semester { text += ", \(semester.displayName)" }
        if let year = course.academicYear { text += ", \(PlanFormat.enrollmentYear(year))" }
        var notes: [String] = []
        if kind == .earned, let status = EarnedEntryStatus(course, in: report).summary {
            notes.append(status)
        }
        if kind == .planned, report.manualPlannedReviewCourses.contains(where: { $0.id == course.id }) {
            notes.append("Not counted: matches a current class.")
        }
        let creditReasons: [CoursePlanIssueReason] = [.invalidCredits, .emptyName, .duplicateID, .invalidScope]
        notes += report.issues
            .filter { $0.courseID == course.id && $0.isPlanned == (kind == .planned) && creditReasons.contains($0.reason) }
            .map(\.reason.rawValue)
        return notes.isEmpty ? text : text + ". " + notes.joined(separator: " ")
    }
}

// MARK: - Grouping

/// Semester records under their school year, in the planner's order.
private struct TranscriptYearGroup: Identifiable {
    var id: String
    var title: String
    var records: [TranscriptCreditRecord]

    static func groups(_ records: [TranscriptCreditRecord]) -> [TranscriptYearGroup] {
        var groups: [TranscriptYearGroup] = []
        var indexes: [String: Int] = [:]
        for record in records {
            let key = "\(record.academicYear)|\(record.gradeYear.map { String($0) } ?? "")"
            if let index = indexes[key] {
                groups[index].records.append(record)
            } else {
                var title = record.academicYear.replacingOccurrences(of: "-", with: "–")
                if let grade = record.gradeYear { title += ", grade \(grade)" }
                indexes[key] = groups.count
                groups.append(TranscriptYearGroup(id: key, title: title, records: [record]))
            }
        }
        return groups
    }
}

// MARK: - Report

/// The one planner call the screen and its sheets share, so a sheet's checks
/// match what the screen shows. Live courses and the transcript projection
/// are passed separately, so current enrollment comes from live gradebook
/// courses and earned credit from history. A nil transcript projection uses
/// the planner's saved-semester fallback, whose record IDs corrections target.
@MainActor
private enum PlanReport {
    static func current(_ store: AppStore) -> CoursePlanReport {
        calculate(store.planning.coursePlan, store: store)
    }

    static func calculate(_ plan: CoursePlan, store: AppStore) -> CoursePlanReport {
        CoursePlanner.calculate(plan: plan, officialCourses: store.courses ?? [],
                                planningTranscriptCourses: store.planningTranscriptCourses)
    }

    /// The imported semester an entry's name duplicates under the planner's
    /// catalog equivalence. The planner never counts an entry that has one.
    nonisolated static func skywardMatch(for name: String, in report: CoursePlanReport) -> TranscriptCreditRecord? {
        let key = TranscriptCreditCalculator.equivalenceKey(for: name)
        return report.transcriptCredits.records.first { TranscriptCreditCalculator.equivalenceKey(for: $0.name) == key }
    }

    /// The current class an entry's name matches under the same catalog
    /// equivalence. The planner never counts an earned entry that has one,
    /// and holds an unscoped planned entry that has one for review.
    nonisolated static func currentMatch(for name: String, in report: CoursePlanReport) -> CurrentCourseCredit? {
        let key = TranscriptCreditCalculator.equivalenceKey(for: name)
        return report.currentCourses.first { TranscriptCreditCalculator.equivalenceKey(for: $0.name) == key }
    }
}

/// Whether the report counts an earned entry, and why not.
private enum EarnedEntryStatus {
    case counted
    /// Saved before automatic estimates; counted only while the report has
    /// no Skyward semesters.
    case countedWithoutSkyward
    /// Skyward already lists an equivalent course, so it's never counted,
    /// whatever the entry's flag says.
    case listedInSkyward(TranscriptCreditRecord)
    /// An equivalent class is current enrollment, so it's never counted as
    /// earned; its expected credit is under Currently taking.
    case currentClass(CurrentCourseCredit)
    /// Saved before automatic estimates; counts once confirmed missing.
    case savedBeforeEstimates
    /// Set aside for invalid values; the issue reason says why.
    case invalid

    init(_ course: CoursePlanCourse, in report: CoursePlanReport) {
        if report.manualEarnedCourses.contains(where: { $0.id == course.id }) {
            self = course.isSupplemental == true ? .counted : .countedWithoutSkyward
        } else if !report.manualReviewCourses.contains(where: { $0.id == course.id }) {
            self = .invalid
        } else if let match = PlanReport.currentMatch(for: course.name, in: report) {
            self = .currentClass(match)
        } else if let match = PlanReport.skywardMatch(for: course.name, in: report) {
            self = .listedInSkyward(match)
        } else {
            self = .savedBeforeEstimates
        }
    }

    var summary: String? {
        switch self {
        case .counted, .invalid: return nil
        case .countedWithoutSkyward: return "Counted while no Skyward semesters are available."
        case .listedInSkyward(let record): return "Not counted because Skyward lists \(record.name)."
        case .currentClass(let current): return "Not counted because you're taking \(current.name) now."
        case .savedBeforeEstimates: return "Not counted until you confirm Skyward doesn't show it."
        }
    }
}

// MARK: - Saving

private enum CoursePlanEntryKind: String {
    case earned, planned

    static let recordLimit = 500
}

private struct CoursePlanEditRequest: Identifiable {
    var id = UUID()
    var kind: CoursePlanEntryKind
    /// Nil when adding.
    var course: CoursePlanCourse?
}

private struct TranscriptCorrectionRequest: Identifiable {
    var id = UUID()
    var record: TranscriptCreditRecord
    /// The saved correction for this record, if any.
    var correction: TranscriptCreditOverride?
}

private enum CoursePlanSheet: Identifiable {
    case entry(CoursePlanEditRequest)
    case correction(TranscriptCorrectionRequest)

    var id: UUID {
        switch self {
        case .entry(let request): return request.id
        case .correction(let request): return request.id
        }
    }
}

/// The single save path for the plan screen and its forms. It confirms the
/// account the screen opened for is still the active one before writing, and
/// passes the store a freshly read scope.
@MainActor
private enum CoursePlanCommit {
    enum Outcome { case saved, accountChanged, rejected }

    static func apply(store: AppStore, originScope: String?, originRevision: Int?,
                      _ change: (inout CoursePlan) -> Bool) -> Outcome {
        guard let originScope, let current = store.localAccountScope, current == originScope,
              store.planning.accountScope == current, originRevision == store.accountRevision else {
            return .accountChanged
        }
        guard !store.planning.planUnavailable else { return .rejected }
        var plan = store.planning.coursePlan
        guard change(&plan) else { return .rejected }
        return store.planning.saveCoursePlan(plan, expectedAccountScope: store.localAccountScope) ? .saved : .rejected
    }
}

// MARK: - Formatting and input

private enum PlanFormat {
    static func credits(_ value: Double) -> String {
        GradeFormat.upToTwoDecimals(value)
    }

    /// "0.5 credit", "1 credit", "0 credits", "1.5 credits".
    static func creditCount(_ value: Double) -> String {
        "\(credits(value)) \(value > 0 && value <= 1 ? "credit" : "credits")"
    }

    /// What current and planned classes add toward the total, then what's
    /// still needed counting them. They're named apart from the earned
    /// figure, never folded into it.
    static func outlook(_ report: CoursePlanReport) -> [String] {
        guard report.earnedRemainingTotal > 0 else { return [] }
        var pending: [String] = []
        if report.currentTotal > 0 { pending.append("\(credits(report.currentTotal)) current") }
        if report.plannedTotal > 0 { pending.append("\(credits(report.plannedTotal)) planned") }
        guard !pending.isEmpty else {
            return ["\(credits(report.remainingTotal)) more needed."]
        }
        var lines = ["With \(pending.joined(separator: " and ")): \(credits(report.combinedTotal)) of \(credits(report.path.totalRequired)) if passed."]
        if report.remainingTotal > 0 { lines.append("\(credits(report.remainingTotal)) more needed.") }
        return lines
    }

    /// "Semester 1", "Semesters 1 and 2", or unknown.
    static func semesters(_ terms: [TermLabel]) -> String {
        let semesters = terms.filter(\.isSemester)
        if semesters.count > 1 { return "Semesters 1 and 2" }
        return semesters.first?.displayName ?? "Semester unknown"
    }

    /// "2026–2027"; nil is live enrollment without a dated school year.
    static func enrollmentYear(_ year: String?) -> String {
        year.map { $0.replacingOccurrences(of: "-", with: "–") } ?? "Current enrollment"
    }

    /// "SM1, 2024–2025, grade 10"; a record without a verified year omits it.
    static func recordSource(_ record: TranscriptCreditRecord) -> String {
        var parts = [record.semester.displayName]
        if !record.academicYear.isEmpty { parts.append(record.academicYear.replacingOccurrences(of: "-", with: "–")) }
        if let grade = record.gradeYear { parts.append("grade \(grade)") }
        return parts.joined(separator: ", ")
    }

    /// Full precision for editing, in the person's decimal format.
    static func editable(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...12)).grouping(.never))
    }
}

private enum PlanInput {
    enum Parsed: Equatable {
        case empty, value(Double), invalid
    }

    /// Digits and one decimal separator; anything else is invalid rather
    /// than guessed at.
    static func parse(_ text: String) -> Parsed {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        let separator = Locale.current.decimalSeparator ?? "."
        if separator != "." { trimmed = trimmed.replacingOccurrences(of: separator, with: ".") }
        guard trimmed.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              trimmed.filter({ $0 == "." }).count <= 1,
              let value = Double(trimmed), value.isFinite else { return .invalid }
        return .value(value)
    }

    static let nameLimit = 256
    static let creditLimit = 4.0
}

// MARK: - Rows

/// An open row with a trailing figure and an optional emphasized note under
/// it. At accessibility sizes the figure moves beneath the text.
private struct PlanValueRow: View {
    var title: String
    var detail: String?
    var value: String
    var valueNote: String?
    var identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    titleStack
                    valueStack(alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    titleStack
                        .frame(maxWidth: .infinity, alignment: .leading)
                    valueStack(alignment: .trailing)
                        .fixedSize()
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, valueNote, detail].compactMap { $0 }.joined(separator: ". "))
        .accessibilityIdentifier(identifier)
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(Color.ink)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func valueStack(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(.figure(.body))
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText())
                .animation(Motion.value(reduceMotion), value: value)
            if let valueNote {
                Text(valueNote)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ink)
            }
        }
    }
}

/// A labeled quiet well showing the current choice with a small chevron.
/// It opens the shared `ChoiceSheet`.
private struct PlanChoiceField<Value: Hashable>: View {
    var label: String
    var valueName: String
    var isPlaceholder = false
    var hint: String
    var identifier: String
    var groups: [ChoiceGroup<Value>]
    @Binding var selection: Value

    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
            Button {
                isPresented = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(valueName)
                        .font(.body)
                        .foregroundStyle(isPlaceholder ? Color.muted : Color.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.muted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Color.well, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(ScopePressStyle())
            .accessibilityLabel(label)
            .accessibilityValue(isPlaceholder ? "Not chosen" : valueName)
            .accessibilityHint(hint)
            .accessibilityIdentifier(identifier)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sheet(isPresented: $isPresented) {
            ChoiceSheet(title: label, groups: groups, selection: $selection)
        }
    }
}

/// Shared form pieces for the plan's sheets.
@MainActor
private enum PlanForm {
    static func subjectGroups(identifier: String) -> [ChoiceGroup<CoursePlanSubject?>] {
        [ChoiceGroup(title: nil, options: CoursePlanSubject.allCases.map {
            ChoiceOption(value: Optional($0), title: $0.title, identifier: "\(identifier).\($0.rawValue)")
        })]
    }

    static func label(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .accessibilityHidden(true)
    }

    static func well<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.body)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.well, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
    }

    static func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func error(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.gradeAttention)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func saveError(_ text: String, identifier: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(Color.gradeAttention)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}

/// Bounded choices for a planned entry's optional scope: the school year in
/// progress and the next four, plus a year already saved on the entry.
@MainActor
private enum PlanScope {
    static func yearGroups(saved: String?, identifier: String, asOf: Date = Date()) -> [ChoiceGroup<String?>] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        let start = calendar.component(.year, from: asOf) - (calendar.component(.month, from: asOf) < 8 ? 1 : 0)
        var years = (start...(start + 4)).map { "\($0)-\($0 + 1)" }
        if let saved, AcademicYearKey.startYear(saved) != nil, !years.contains(saved) {
            years.insert(saved, at: 0)
        }
        let options = [ChoiceOption<String?>(value: nil, title: "Not chosen", identifier: "\(identifier).none")]
            + years.map { ChoiceOption(value: Optional($0), title: PlanFormat.enrollmentYear($0), identifier: "\(identifier).\($0)") }
        return [ChoiceGroup(title: nil, options: options)]
    }

    static func semesterGroups(identifier: String) -> [ChoiceGroup<TermLabel?>] {
        let options = [ChoiceOption<TermLabel?>(value: nil, title: "Not chosen", identifier: "\(identifier).none")]
            + [TermLabel.sm1, .sm2].map { ChoiceOption(value: Optional($0), title: $0.displayName, identifier: "\(identifier).\($0.historicalKey)") }
        return [ChoiceGroup(title: nil, options: options)]
    }
}

// MARK: - Correction form

/// Corrects one automatic semester estimate. The correction is saved under
/// the record's own ID, replaces only that record's credits and subject, and
/// removing it restores the automatic estimate.
private struct TranscriptCorrectionSheet: View {
    var request: TranscriptCorrectionRequest
    var originScope: String?
    var originRevision: Int?
    var onCommitted: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var themeManager = ThemeManager.shared
    @State private var fields: Fields
    @State private var saveError: String?
    @State private var confirmingRemove = false
    @FocusState private var creditsFocused: Bool
    private let initialFields: Fields

    private struct Fields: Equatable {
        var subject: CoursePlanSubject?
        var credits: String
    }

    init(request: TranscriptCorrectionRequest, originScope: String?, originRevision: Int?, onCommitted: @escaping () -> Void) {
        self.request = request
        self.originScope = originScope
        self.originRevision = originRevision
        self.onCommitted = onCommitted
        let initial = Fields(
            subject: request.correction?.subject ?? request.record.subject,
            credits: PlanFormat.editable(request.correction?.credits ?? request.record.credits)
        )
        initialFields = initial
        _fields = State(initialValue: initial)
    }

    private var record: TranscriptCreditRecord { request.record }

    private var credits: Double? {
        guard case .value(let value) = PlanInput.parse(fields.credits), value >= 0, value <= PlanInput.creditLimit else { return nil }
        return value
    }


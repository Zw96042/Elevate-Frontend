import SwiftUI
import UIKit

enum AssignmentSortOption: String, CaseIterable, Identifiable {
    case date = "Date"
    case category = "Category"
    case grade = "Grade"
    var id: String { rawValue }
}

enum AssignmentFilterOption: String, CaseIterable, Identifiable {
    case missing = "Missing"
    case noCount = "No Count"
    case absent = "Absent"
    var id: String { rawValue }
}

enum AssignmentGradeRange: String, CaseIterable, Identifiable {
    case excellent = "90–100"
    case good = "80–89"
    case passing = "70–79"
    case belowPassing = "Below 70"
    case ungraded = "Ungraded"

    var id: String { rawValue }

    func contains(_ assignment: CalcAssignment) -> Bool {
        guard let grade = assignment.grade, assignment.outOf > 0 else {
            return self == .ungraded
        }
        let percentage = grade / assignment.outOf * 100
        switch self {
        case .excellent: return percentage >= 90
        case .good: return (80..<90).contains(percentage)
        case .passing: return (70..<80).contains(percentage)
        case .belowPassing: return percentage < 70
        case .ungraded: return false
        }
    }
}

struct ClassDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isMainContentVisible) private var isMainContentVisible
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroGradeSize: CGFloat = 42
    @ScaledMetric(relativeTo: .body) private var averageColumn: CGFloat = 56
    /// Space above each section on this screen. Tighter than the shared
    /// section gap: the 44-point headings already add air above their text.
    private let sectionSpacing: CGFloat = 16
    let course: UnifiedCourseData
    var targetAssignmentID: String? = nil
    var targetTerm: TermLabel? = nil
    @State private var openedAssignmentID: String?
    @State private var highlightsLinkedAssignment = false
    @AccessibilityFocusState private var accessibilityAssignmentID: String?
    @State private var assignmentLinkUnavailable = false
    @State private var navigationAccountRevision: Int?

    @State private var gradeInfo: GradeInfoResult?
    @State private var gradeInfoLastUpdated: Date?
    @State private var loading = true
    @State private var refreshing = false
    @State private var keyboardIsVisible = false
    @State private var focusedScoreRows: Set<String> = []
    @State private var finishScoreRequest = 0
    @State private var finishScoreTargets: Set<String> = []
    @State private var gradeInfoLastAttempt: Date?
    @State private var gradeInfoLoadID: UUID?
    @State private var loadError: String?
    @State private var loadErrorBucket: String?
    @State private var loadedBucket: String?
    @State private var quarterGradeInfo: [String: GradeInfoResult] = [:]
    @State private var semesterCalculationError: String?

    @State private var showCalculated = false
    @State private var whatIfAssignments: [WhatIfAssignment] = []
    @State private var gradeOverrides: [String: AssignmentGradeOverride] = [:]
    @State private var finalExamGrades: [String: Double] = [:]
    @State private var showingAddSheet = false
    @State private var scoreRowFrames: [String: CGRect] = [:]
    @State private var feedbackRevision = 0

    @State private var sortOption: AssignmentSortOption = .date
    @State private var sortAscending = false
    @State private var categoryFilter: Set<String> = []
    @State private var assignmentFilter: Set<AssignmentFilterOption> = []
    @State private var gradeFilter: Set<AssignmentGradeRange> = []
    @State private var showsBreakdown = false
    @State private var reminder: ReminderRequest?
    @State private var scenarioSheet: WhatIfScenarioSheetContext?
    @State private var impactRequest: AssignmentImpactRequest?
    @State private var showingTermSelector = false
    @State private var gradeViewport: CGRect = .zero
    @State private var displayedGradeFrame: CGRect = .zero
    @State private var titleInBar = false

    private var classKey: String {
        WhatIfStore.classKey(studentID: course.stuId, className: course.courseName, corNumId: course.corNumId,
                             section: course.section, gbId: course.gbId)
    }

    private var examType: String { store.selectedTerm == .sm1 ? "EX1" : "EX2" }

    var body: some View {
        @Bindable var store = store
        return ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The navigation bar cannot wrap a full course name. Keep it
                // in the content, including any parenthetical description.
                Text(courseName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("course.fullTitle")
                    .padding(.bottom, 12)
                    .onGeometryChange(for: Bool.self) { geometry in
                        geometry.frame(in: .scrollView).maxY < 0
                    } action: { titleInBar = $0 }

                StatusStrip(
                    showsRefresh: hasCurrentGradeInfo && (loadError != nil || gradeInfoLastUpdated != nil),
                    lastUpdated: gradeInfoLastUpdated,
                    isRefreshing: refreshing,
                    error: loadError
                ) {
                    await load(force: true)
                } control: {
                    TermSelector(selection: $store.selectedTerm, grades: liveCourse.termScores,
                                 allowedTerms: liveCourse.availableTerms) { showingTermSelector = $0 }
                }

                gradeSection
                    .padding(.top, 12)

                gradeGoalRow
                    .padding(.top, sectionSpacing - 8)
                InsetDivider()

                whatIfSection

                if loading {
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { index in
                            if index > 0 { InsetDivider() }
                            AssignmentRowPlaceholder(index: index)
                        }
                    }
                    .padding(.top, sectionSpacing)
                    .loadingPlaceholder("Loading assignments")
                } else if let loadError, !hasCurrentGradeInfo {
                    InlineErrorState(title: "Couldn't load assignments", message: loadError) {
                        await load(force: true)
                    }
                    .padding(.top, sectionSpacing)
                } else {
                    categoriesSection
                    if store.selectedTerm.isSemester {
                        finalExamSection
                    }
                    assignmentsSection
                }
            }
            .padding(.horizontal, Metrics.page)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(courseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(courseName)
                    .font(.headline)
                    .lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .opacity(titleInBar ? 1 : 0)
                    .accessibilityHidden(!titleInBar)
                    .accessibilityIdentifier("course.compactTitle")
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: titleInBar)
            }
        }
        .coordinateSpace(name: "assignmentEditing")
        .onPreferenceChange(EditableScoreFramesKey.self) { scoreRowFrames = $0 }
        .simultaneousGesture(SpatialTapGesture().onEnded { tap in
            // Editable rows decide their own taps (see `AssignmentRow.rowTapped`);
            // the rest of the page ends editing.
            guard !scoreRowFrames.values.contains(where: { $0.contains(tap.location) }) else { return }
            finishScoreEditing()
        })
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackRevision)
        .accessibilityIdentifier("course.detail")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { gradeViewport = $0 }
        .onChange(of: gradeViewingObservation) { _, _ in observeVisibleOfficialGrade() }
        .sheet(isPresented: $showingAddSheet) {
            AddAssignmentSheet(
                categoriesByTerm: addAssignmentCategoriesByTerm,
                term: store.selectedTerm
            ) { assignment in
                var a = assignment
                a.className = course.courseName
                WhatIfStore.add(a, classKey: classKey)
                animateWhatIfChange { reloadWhatIf() }
                feedbackRevision += 1
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $reminder) { request in
            ReminderSheet(request: request)
        }
        .sheet(item: $scenarioSheet) { context in
            WhatIfScenariosSheet(
                context: context,
                source: context.term == store.selectedTerm ? whatIfSource(for: context.term) : nil,
                current: scenarioCurrentState,
                onApplied: { scenarioApplied(context) }
            )
        }
        .sheet(item: $impactRequest) { request in
            let current = request.term == store.selectedTerm
            AssignmentImpactSheet(
                request: request,
                quarterSources: current ? impactQuarterSources : [:],
                semesterSource: current && request.term.isSemester ? whatIfSource(for: request.term) : nil,
                whatIfIsOn: isWhatIfActive,
                canTryInWhatIf: semesterCalculationAvailable,
                localOverrides: gradeOverrides,
                onTry: { candidate, earned in tryImpact(request, candidate: candidate, earned: earned) }
            )
        }
        .onChange(of: store.accountRevision) { _, _ in
            openedAssignmentID = nil
            highlightsLinkedAssignment = false
            assignmentLinkUnavailable = false
            reminder = nil
            scenarioSheet = nil
            impactRequest = nil
        }
        // Both sheets are scoped to the term they opened on.
        .onChange(of: store.selectedTerm) { _, _ in
            scenarioSheet = nil
            impactRequest = nil
        }
        .onAppear {
            if navigationAccountRevision == nil { navigationAccountRevision = store.accountRevision }
            if openedAssignmentID == nil, let targetTerm, liveCourse.availableTerms.contains(targetTerm) {
                store.selectedTerm = targetTerm
            }
            // A grade goal's "Try in What-if" saves local edits while this
            // screen is covered; show them on return.
            guard liveCourse.availableTerms.contains(store.selectedTerm) else { return }
            reconcileCachedGradeInfo()
            showCalculated = targetAssignmentID != nil && openedAssignmentID == nil ? false : WhatIfStore.showCalculated(classKey: classKey)
            reloadWhatIf()
        }
        .task(id: "\(store.selectedTerm.bucket)-\(liveCourse.semester.rawValue)") {
            guard liveCourse.availableTerms.contains(store.selectedTerm) else {
                // A foreground calendar rollover must not switch a half-year
                // gradebook to the other course's semester.
                store.selectedTerm = store.selectedTerm.isFall
                    ? liveCourse.availableTerms[0]
                    : liveCourse.availableTerms[liveCourse.availableTerms.count - 1]
                return
            }
            categoryFilter.removeAll()
            assignmentFilter.removeAll()
            gradeFilter.removeAll()
            showCalculated = targetAssignmentID != nil && openedAssignmentID == nil ? false : WhatIfStore.showCalculated(classKey: classKey)
            reloadWhatIf()
            // A linked assignment may be newer than this class's saved cache.
            await load(force: targetAssignmentID != nil && openedAssignmentID == nil)
        }
        .task(id: "\(scenePhase)-\(store.selectedTerm.bucket)-\(store.accountRevision)") {
            guard scenePhase == .active, liveCourse.availableTerms.contains(store.selectedTerm) else { return }
            while !Task.isCancelled {
                if !refreshing, focusedScoreRows.isEmpty, !keyboardIsVisible, !showingAddSheet,
                   !store.isAuthenticating, store.canShowData,
                   AutomaticRefreshPolicy.isDue(
                       lastUpdated: gradeInfoLastUpdated,
                       lastAttempt: gradeInfoLastAttempt,
                       now: Date(), interval: store.automaticRefreshInterval
                   ) {
                    await load(force: true, automatic: true)
                }
                do { try await Task.sleep(for: .seconds(min(15, store.automaticRefreshInterval))) }
                catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardIsVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardIsVisible = false
        }
        .visibleRefreshable {
            await load(force: true)
        }
        .task(id: "\(loading)-\(loadedBucket ?? "")-\(gradeInfoLastUpdated?.timeIntervalSince1970 ?? 0)-\(store.selectedTerm.bucket)") {
            guard let targetAssignmentID, let targetTerm, store.selectedTerm == targetTerm,
                  navigationAccountRevision == store.accountRevision, !loading, hasCurrentGradeInfo,
                  openedAssignmentID == nil, let gradeInfo else { return }
            guard let id = AssignmentLink.calcAssignmentID(for: targetAssignmentID, course: liveCourse,
                                                          term: targetTerm, gradeInfo: gradeInfo) else {
                assignmentLinkUnavailable = true
                return
            }
            clearAssignmentControls()
            showCalculated = false
            assignmentLinkUnavailable = false
            openedAssignmentID = id
            highlightsLinkedAssignment = true
            await Task.yield()
            guard !Task.isCancelled, navigationAccountRevision == store.accountRevision else { return }
            scroll.scrollTo(id, anchor: .center)
            accessibilityAssignmentID = id
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            withAnimation(Motion.replace(reduceMotion)) { highlightsLinkedAssignment = false }
        }
        }
    }

    /// Navigation keeps the original course identity; refreshed posted scores
    /// come from the account's current unified course record.
    private var liveCourse: UnifiedCourseData {
        store.courses?.first { $0.id == course.id } ?? course
    }

    private var courseName: String {
        ClassNameFormatter.format(course.courseName.replacingOccurrences(of: " ", with: "_"))
    }

    private func animateWhatIfChange(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.snappy(duration: 0.3)) { change() }
        }
    }

    // MARK: - Data

    /// Matches the request `DataService.gradeInfo(params:)` caches under, so the
    /// persisted record (and its real fetch time) can be read back.
    private func gradeInfoParams(for term: TermLabel) -> GradeInfoParams {
        GradeInfoParams(
            stuId: course.stuId,
            corNumId: course.corNumId,
            gbId: course.gbId,
            section: course.section,
            bucket: term.bucket
        )
    }

    /// A covered planner can refresh these same gradebooks. Reuse its latest
    /// account cache before applying saved edits on return, without another fetch.
    private func reconcileCachedGradeInfo() {
        let term = store.selectedTerm
        guard loadedBucket == term.bucket else { return }
        if let saved = DataService.shared.cachedGradeInfo(params: gradeInfoParams(for: term)) {
            gradeInfo = saved.value
            if gradeInfoLastUpdated.map({ saved.updatedAt > $0 }) ?? true {
                gradeInfoLastUpdated = saved.updatedAt
                loadError = nil
                loadErrorBucket = nil
            }
        }
        if term.isSemester {
            for quarter in term.whatIfQuarterTerms {
                if let saved = DataService.shared.cachedGradeInfo(params: gradeInfoParams(for: quarter)) {
                    quarterGradeInfo[quarter.shortName] = saved.value
                }
            }
        }
    }

    private func load(force: Bool = false, automatic: Bool = false) async {
        guard liveCourse.availableTerms.contains(store.selectedTerm) else { return }
        let selectedTerm = store.selectedTerm
        let bucket = selectedTerm.bucket
        let revision = store.accountRevision
        let previousCacheTimestamp = DataService.shared
            .cachedGradeInfo(params: gradeInfoParams(for: selectedTerm))?.updatedAt
        if loadErrorBucket != bucket {
            loadError = nil
            loadErrorBucket = nil
        }
        if !force, loadedBucket == bucket, gradeInfo != nil {
            loading = false
            return
        }
        let loadID = UUID()
        gradeInfoLoadID = loadID
        gradeInfoLastAttempt = Date()
        loading = gradeInfo == nil || loadedBucket != bucket
        refreshing = true
        defer { if gradeInfoLoadID == loadID { refreshing = false } }
        loadError = nil
        loadErrorBucket = nil
        do {
            let result: GradeInfoResult
            var loadedQuarters: [String: GradeInfoResult] = [:]
            var quarterLoadError: String?

            if selectedTerm.isSemester {
                let quarterTerms = selectedTerm.whatIfQuarterTerms
                async let mainResponse = gradeInfoResponse(for: selectedTerm, force: force)
                async let firstResponse = gradeInfoResponse(for: quarterTerms[0], force: force)
                async let secondResponse = gradeInfoResponse(for: quarterTerms[1], force: force)
                let responses = await (mainResponse, firstResponse, secondResponse)
                result = try responses.0.get()

                for (term, response) in [(quarterTerms[0], responses.1), (quarterTerms[1], responses.2)] {
                    switch response {
                    case .success(let info):
                        loadedQuarters[term.shortName] = info
                    case .failure(let error):
                        quarterLoadError = quarterLoadError ?? error.localizedDescription
                        // Keep a quarter that was saved earlier rather than dropping the prediction.
                        if quarterGradeInfo[term.shortName] == nil,
                           let saved = DataService.shared.cachedGradeInfo(params: gradeInfoParams(for: term)) {
                            loadedQuarters[term.shortName] = saved.value
                        }
                    }
                }
            } else {
                result = try await gradeInfoResponse(for: selectedTerm, force: force).get()
            }

            guard await waitForGradeRefreshApplication(
                bucket: bucket, revision: revision, loadID: loadID, automatic: automatic
            ) else { return }
            semesterCalculationError = quarterLoadError
            gradeInfo = result
            for (term, info) in loadedQuarters {
                quarterGradeInfo[term] = info
            }
            // A cache hit reports when the data was actually fetched, never now.
            gradeInfoLastUpdated = DataService.shared
                .cachedGradeInfo(params: gradeInfoParams(for: selectedTerm))?
                .updatedAt ?? (store.isUsingSampleData ? Date() : nil)
            if !force, semesterCalculationError == nil,
               let previousCacheTimestamp, gradeInfoLastUpdated == previousCacheTimestamp {
                // Opening an existing disk record did not make a network
                // attempt. Its original timestamp determines the next refresh.
                gradeInfoLastAttempt = nil
            }
            loadedBucket = bucket
            trimCategoryFilter()
        } catch is CancellationError {
            return
        } catch {
            guard await waitForGradeRefreshApplication(
                bucket: bucket, revision: revision, loadID: loadID, automatic: automatic
            ) else { return }
            gradeInfoLastAttempt = Date()
            loadError = error.localizedDescription
            loadErrorBucket = bucket
            // Show the last saved gradebook for this term, clearly marked as not refreshed.
            if !hasCurrentGradeInfo,
               let saved = DataService.shared.cachedGradeInfo(params: gradeInfoParams(for: selectedTerm)) {
                gradeInfo = saved.value
                gradeInfoLastUpdated = saved.updatedAt
                loadedBucket = bucket
                trimCategoryFilter()
            }
        }
        guard !Task.isCancelled, store.selectedTerm.bucket == bucket,
                  store.accountRevision == revision, gradeInfoLoadID == loadID else { return }
        loading = false
    }

    /// Hardware keyboards need not post visibility notifications. Both manual
    /// and automatic results wait for actual score focus to end before replacing
    /// rows; every suspension rechecks request ownership before applying data.
    private func waitForGradeRefreshApplication(
        bucket: String, revision: Int, loadID: UUID, automatic: Bool
    ) async -> Bool {
        while true {
            guard !Task.isCancelled, store.selectedTerm.bucket == bucket,
                  store.accountRevision == revision, gradeInfoLoadID == loadID else { return false }
            let shouldWait = !focusedScoreRows.isEmpty
                || (automatic && (keyboardIsVisible || showingAddSheet))
            guard shouldWait else { return true }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return false }
        }
    }

    private func scoreFocusChanged(_ focused: Bool, rowID: String) {
        if focused { focusedScoreRows.insert(rowID) }
        else { focusedScoreRows.remove(rowID) }
    }

    /// Asks every focused score field to commit and resign. Reads actual field
    /// focus, not keyboard visibility, so hardware keyboards behave the same.
    /// Returns false when no score was being edited.
    @discardableResult
    private func finishScoreEditing() -> Bool {
        guard !focusedScoreRows.isEmpty else { return false }
        finishScoreTargets = focusedScoreRows
        finishScoreRequest += 1
        return true
    }

    private func trimCategoryFilter() {
        let availableCategories = Set(
            gradeInfo?.gradebook.map(\.category).filter { $0 != "Final Exam" } ?? []
        )
        categoryFilter.formIntersection(availableCategories)
    }

    private func gradeInfoResponse(
        for term: TermLabel,
        force: Bool
    ) async -> Result<GradeInfoResult, Error> {
        do {
            return .success(try await DataService.shared.gradeInfo(params: gradeInfoParams(for: term), forceRefresh: force))
        } catch {
            return .failure(error)
        }
    }

    private var hasCurrentGradeInfo: Bool {
        gradeInfo != nil && loadedBucket == store.selectedTerm.bucket
    }

    private func reloadWhatIf() {
        whatIfAssignments = WhatIfStore.assignments(classKey: classKey, term: store.selectedTerm)
        gradeOverrides = WhatIfStore.gradeOverrides(classKey: classKey, term: store.selectedTerm)
        finalExamGrades = WhatIfStore.finalExamGrades(classKey: classKey)
    }

    private func resetWhatIf() {
        WhatIfStore.reset(classKey: classKey, term: store.selectedTerm)
        reloadWhatIf()
    }

    private var hasFinalExamEstimateForSelectedTerm: Bool {
        store.selectedTerm.isSemester && finalExamGrades[examType] != nil
    }

    // MARK: - Local edits to existing assignment scores

    private func overrideScore(of assignment: CalcAssignment, to grade: Double?) {
        guard let original = editableOfficialAssignments.first(where: { $0.id == assignment.id }) else { return }
        if grade == original.grade, gradeOverrides[assignment.id]?.noCount == nil {
            WhatIfStore.removeGradeOverride(assignment: original, classKey: classKey)
        } else {
            WhatIfStore.setGradeOverride(grade, assignment: original, classKey: classKey)
        }
        animateWhatIfChange { reloadWhatIf() }
    }

    private func restoreSkywardValue(of assignment: CalcAssignment) {
        guard let original = editableOfficialAssignments.first(where: { $0.id == assignment.id }) else { return }
        // Restoring the score must not undo an independent no-count choice.
        overrideScore(of: assignment, to: original.grade)
    }

    private func skywardOriginal(of assignment: CalcAssignment) -> (grade: Double?, outOf: Double)? {
        guard let edit = gradeOverrides[assignment.id],
              let original = editableOfficialAssignments.first(where: { $0.id == assignment.id }),
              edit.changesScore(of: original) else { return nil }
        return (original.grade, original.outOf)
    }

    // MARK: - Computation

    private var semesterCalculationAvailable: Bool {
        !store.selectedTerm.isSemester
            || store.selectedTerm.whatIfQuarterTerms.allSatisfy {
                quarterGradeInfo[$0.shortName] != nil
            }
    }

    private var isWhatIfActive: Bool {
        showCalculated && semesterCalculationAvailable
    }

    private var addAssignmentCategoriesByTerm: [String: [String]] {
        Dictionary(uniqueKeysWithValues: store.selectedTerm.whatIfQuarterTerms.map { term in
            let info = store.selectedTerm.isSemester
                ? quarterGradeInfo[term.shortName]
                : gradeInfo
            let categories = Set(
                info?.gradebook.map(\.category)
                    .filter { !$0.isEmpty && $0 != "Final Exam" } ?? []
            )
            return (term.shortName, categories.sorted())
        })
    }

    private var apiAssignments: [CalcAssignment] {
        guard let gradeInfo else { return [] }
        return calcAssignments(from: gradeInfo, term: store.selectedTerm)
    }

    private func calcAssignments(from info: GradeInfoResult, term: TermLabel) -> [CalcAssignment] {
        AssignmentGradeEdits.assignments(from: info, className: course.courseName, term: term)
    }

    /// Semester edits belong to the source quarter, so the same saved score
    /// is used on the quarter screen and in its 40% semester component.
    private var editableOfficialAssignments: [CalcAssignment] {
        guard store.selectedTerm.isSemester else { return apiAssignments }
        return store.selectedTerm.whatIfQuarterTerms.flatMap { term in
            guard let info = quarterGradeInfo[term.shortName] else { return [CalcAssignment]() }
            return calcAssignments(from: info, term: term).filter { $0.category != "Final Exam" }
        }
    }

    private var meshedAssignments: [CalcAssignment] {
        guard isWhatIfActive else { return apiAssignments }
        return whatIfAssignments.map(calcAssignment(from:))
            + AssignmentGradeEdits.applying(gradeOverrides, to: editableOfficialAssignments)
    }

    private func calcAssignment(from assignment: WhatIfAssignment) -> CalcAssignment {
        WhatIfQuarterMath.assignment(from: assignment)
    }

    private var effectiveFinalExamGrade: Double? {
        if isWhatIfActive, let estimate = finalExamGrades[examType], estimate.isFinite {
            return estimate
        }
        return officialFinalExamGrade
    }

    private var officialFinalExamGrade: Double? {
        WhatIfQuarterMath.postedExamGrade(semesterInfo: gradeInfo, course: liveCourse, examType: examType)
    }

    private var quarterTotals: (first: Double?, second: Double?) {
        func score(_ bucket: String) -> Double? {
            liveCourse.currentScores.first { $0.bucket == bucket }?.score
        }
        return store.selectedTerm == .sm1
            ? (score("Q1"), score("Q2"))
            : (score("Q3"), score("Q4"))
    }

    private var hasEffectiveWhatIfChanges: Bool {
        guard isWhatIfActive else { return false }
        if hasUnavailableEditedQuarter { return true }
        if !whatIfAssignments.isEmpty { return true }
        if AssignmentGradeEdits.hasEffectiveChanges(gradeOverrides, to: editableOfficialAssignments) { return true }
        guard store.selectedTerm.isSemester, let exam = finalExamGrades[examType], exam.isFinite else { return false }
        return exam != officialFinalExamGrade
    }

    private var hasUnavailableEditedQuarter: Bool {
        guard store.selectedTerm.isSemester else { return false }
        return store.selectedTerm.whatIfQuarterTerms.contains { term in
            quarterGradeInfo[term.shortName] == nil && hasSavedQuarterChanges(term)
        }
    }

    private func hasSavedQuarterChanges(_ term: TermLabel) -> Bool {
        whatIfAssignments.contains { $0.term == term.shortName }
            || !WhatIfStore.gradeOverrides(classKey: classKey, term: term).isEmpty
    }

    private var predictedQuarterTotals: (first: Double?, second: Double?) {
        guard isWhatIfActive, store.selectedTerm.isSemester else { return quarterTotals }
        let terms = store.selectedTerm.whatIfQuarterTerms
        return (
            recalculatedQuarterTotal(for: terms[0]),
            recalculatedQuarterTotal(for: terms[1])
        )
    }

    private func recalculatedQuarterTotal(for term: TermLabel) -> Double? {
        WhatIfQuarterMath.quarterTotal(
            term: term,
            info: quarterGradeInfo[term.shortName],
            className: course.courseName,
            postedCourseGrade: liveCourse.currentScores.first(where: { $0.bucket == term.shortName })?.score,
            whatIfAssignments: whatIfAssignments,
            overrides: gradeOverrides,
            hasSavedChanges: hasSavedQuarterChanges(term)
        )
    }

    private var summary: GradeSummary {
        let countable = meshedAssignments.filter { $0.category != "Final Exam" }
        let weights = GradeCalculator.normalizedWeights(categories: gradeInfo?.gradebook ?? [], assignments: countable)
        var result = GradeCalculator.summary(
            assignments: countable,
            categoryWeights: weights,
            sourceCategories: gradeInfo?.gradebook ?? [],
            quarterTotals: store.selectedTerm.isSemester ? predictedQuarterTotals : nil,
            selectedTerm: store.selectedTerm,
            finalExamGrade: store.selectedTerm.isSemester ? effectiveFinalExamGrade : nil
        )
        if !store.selectedTerm.isSemester, weights.isEmpty {
            result.courseTotal = GradeCalculator.pointsTotal(assignments: countable)
        }
        return result
    }

    private var gradePresentation: WhatIfGradePresentation {
        let calculated = summary.courseTotal
        let historical = calculated == nil
            ? AcademicScoreValue.finiteDouble(liveCourse.historicalGrades[store.selectedTerm.historicalKey])
            : nil
        return .resolve(
            official: gradeInfo?.score ?? historical,
            calculated: calculated,
            hasEffectiveChanges: hasEffectiveWhatIfChanges,
            calculationUnavailable: hasUnavailableEditedQuarter
        )
    }

    private var displayGrade: Double? {
        guard hasCurrentGradeInfo else { return nil }
        return gradePresentation.value
    }

    private var displayedAssignments: [CalcAssignment] {
        var list = meshedAssignments.filter { $0.category != "Final Exam" }
        if !categoryFilter.isEmpty {
            list = list.filter { categoryFilter.contains($0.category) }
        }
        if !assignmentFilter.isEmpty {
            list = list.filter { assignment in
                (assignmentFilter.contains(.missing) && assignment.isMissing)
                    || (assignmentFilter.contains(.noCount) && assignment.isNoCount)
                    || (assignmentFilter.contains(.absent) && assignment.isAbsent)
            }
        }
        if !gradeFilter.isEmpty {
            list = list.filter { assignment in
                gradeFilter.contains { $0.contains(assignment) }
            }
        }
        let parsedDates = Dictionary(
            list.map { ($0.id, parseDate($0.dueDate)) },
            uniquingKeysWith: { first, _ in first }
        )
        list.sort { a, b in
            switch sortOption {
            case .category:
                return sortAscending ? a.category < b.category : a.category > b.category
            case .date:
                let first = parsedDates[a.id] ?? .distantPast
                let second = parsedDates[b.id] ?? .distantPast
                return sortAscending ? first < second : first > second
            case .grade:
                let first = (a.grade ?? -1) / max(a.outOf, 1)
                let second = (b.grade ?? -1) / max(b.outOf, 1)
                return sortAscending ? first < second : first > second
            }
        }
        return list
    }

    private func parseDate(_ string: String) -> Date {
        let parts = string.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantPast }
        var components = DateComponents()
        components.month = parts[0]
        components.day = parts[1]
        components.year = parts[2] < 100 ? 2000 + parts[2] : parts[2]
        return Calendar.current.date(from: components) ?? .distantPast
    }

    // MARK: - Header

    /// A person's name: `PersonName`, never the course-title formatter.
    private var instructor: String? {
        guard let instructor = course.instructor.map(PersonName.display), !instructor.isEmpty else { return nil }
        return instructor
    }

    /// The grade with its source, the course beneath it, and for a semester
    /// the quarters and exam it is built from.
    private var gradeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            gradeBlock
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { displayedGradeFrame = $0 }
            courseLines
            if store.selectedTerm.isSemester, hasCurrentGradeInfo {
                semesterComposition
                    .padding(.top, 4)
            }
        }
    }

    private var visibleOfficialGrade: Double? {
        hasCurrentGradeInfo && gradePresentation.source == .official ? displayGrade : nil
    }

    private struct GradeViewingObservation: Equatable {
        var courseID: String
        var term: TermLabel
        var score: Double?
        var sourceDate: Date?
        var accountScope: String?
        var isVisible: Bool
    }

    private var gradeViewingObservation: GradeViewingObservation {
        GradeViewingObservation(courseID: liveCourse.id, term: store.selectedTerm,
            score: visibleOfficialGrade, sourceDate: gradeInfoLastUpdated,
            accountScope: store.localAccountScope, isVisible: canObserveOfficialGrade)
    }

    private var canObserveOfficialGrade: Bool {
        let isTopCourse: Bool
        switch router.coursesPath.last {
        case .course(let shown), .assignment(let shown, _, _, _): isTopCourse = shown.id == course.id
        default: isTopCourse = false
        }
        return scenePhase == .active && router.selectedTab == .courses && isTopCourse
            && isMainContentVisible && !router.isShowingSettings && !showingAddSheet
            && !showingTermSelector && reminder == nil && scenarioSheet == nil && impactRequest == nil
            && displayedGradeFrame.height > 0
            && gradeViewport.contains(CGPoint(x: displayedGradeFrame.midX, y: displayedGradeFrame.midY))
    }

    private func observeVisibleOfficialGrade() {
        guard canObserveOfficialGrade, let score = visibleOfficialGrade,
              let sourceDate = gradeInfoLastUpdated, let scope = store.localAccountScope else { return }
        store.notifications.markGradeViewed(course: liveCourse, term: store.selectedTerm,
            score: score, sourceDate: sourceDate, accountScope: scope)
    }

    /// The teacher on a full-width line, so a long name never squeezes the
    /// period beneath it. Course level stays in the GPA math, not on screen.
    private var courseLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let instructor {
                Text(instructor)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Teacher")
                    .accessibilityValue(instructor)
            }
            if let period = course.period {
                Text("Period \(period)")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The two quarter grades and the exam the semester grade combines,
    /// including any what-if changes, each with the district share it
    /// counts for: three open figures side by side, a list at large sizes.
    private var semesterComposition: some View {
        let quarters = store.selectedTerm.whatIfQuarterTerms
        let totals = predictedQuarterTotals
        let exam = effectiveFinalExamGrade
        let parts: [(name: String, value: Double?, share: String)] = [
            (quarters[0].displayName, totals.first, "40%"),
            (quarters[1].displayName, totals.second, "40%"),
            ("Exam", exam, "20%"),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                            if index > 0 { InsetDivider() }
                            compositionCell(part.name, value: part.value, share: part.share)
                                .padding(.vertical, 10)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            compositionCell(part.name, value: part.value, share: part.share)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Semester components")

            if exam == nil {
                Text(totals.first == nil || totals.second == nil ? "Waiting for both quarter grades." : "No exam posted. Using the quarter average.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func compositionCell(_ name: String, value: Double?, share: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.footnote)
                .foregroundStyle(Color.muted)
            Text(GradeFormat.twoDecimals(value))
                .font(.figure(.body))
                .foregroundStyle(GradeTier(value).textColor)
                .contentTransition(.numericText(value: value ?? 0))
            Text(value == nil ? "Not posted" : "Counts \(share)")
                .font(.figure(.caption, weight: .regular))
                .foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(GradeFormat.spokenCourseGrade(value)), counts \(share)")
    }

    private var gradeBlock: some View {
        let grade = displayGrade
        let qualifier = gradeQualifier
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if loading && !hasCurrentGradeInfo && grade == nil {
                    SkeletonText(.display(size: min(heroGradeSize, 66)), length: 4)
                } else {
                    Text(GradeFormat.twoDecimals(grade))
                        .font(.display(size: min(heroGradeSize, 66)))
                        .tracking(-1)
                        .foregroundStyle(grade == nil ? Color.muted : GradeTier(grade).textColor)
                        .contentTransition(.numericText(value: grade ?? 0))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if grade != nil {
                    Text("%")
                        .font(.title3)
                        .foregroundStyle(Color.muted)
                }
                if let qualifier, !dynamicTypeSize.isAccessibilitySize {
                    qualifierText(qualifier)
                        .padding(.leading, 10)
                }
            }
            .animation(Motion.value(reduceMotion), value: grade)

            if let qualifier, dynamicTypeSize.isAccessibilitySize {
                qualifierText(qualifier)
            }

            if let gradeCaption {
                Text(gradeCaption)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gradeSourceLabel)
        .accessibilityValue(gradeAccessibilityValue)
        .accessibilityIdentifier("course.grade")
    }

    /// A word beside the number when it is not Skyward's posted grade. An
    /// estimate is named in the action color, the same color as what-if
    /// rows, so it never reads as the official grade. Skyward's own grade
    /// needs no label.
    private var gradeQualifier: (text: String, isEstimate: Bool)? {
        guard hasCurrentGradeInfo else { return nil }
        if displayGrade == nil {
            if let start = futureQuarterStart { return ("Starts \(schoolDayLabel(start))", false) }
            return ("No grade yet", false)
        }
        switch gradePresentation.source {
        case .estimate: return ("Estimate", true)
        case .calculated: return gradePresentation.value == nil ? nil : ("Calculated", false)
        case .official: return nil
        }
    }

    private func qualifierText(_ qualifier: (text: String, isEstimate: Bool)) -> some View {
        Text(qualifier.text)
            .font(.subheadline.weight(qualifier.isEstimate ? .semibold : .regular))
            .foregroundStyle(qualifier.isEstimate ? Color.themeAccent : Color.muted)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.opacity)
    }

    /// How far a what-if estimate is from Skyward's posted grade, so a
    /// hypothetical value is never presented as the real one.
    private var gradeCaption: String? {
        guard hasCurrentGradeInfo, let whatIfDelta, let official = gradeInfo?.score else { return nil }
        let direction = whatIfDelta > 0 ? "above" : "below"
        return "\(GradeFormat.twoDecimals(abs(whatIfDelta))) \(direction) Skyward's \(GradeFormat.twoDecimals(official))"
    }

    private var gradeSourceLabel: String {
        guard hasCurrentGradeInfo else { return loading ? "Loading grade" : "Grade" }
        switch gradePresentation.source {
        case .estimate: return "What-if estimate"
        case .official: return "Skyward grade"
        case .calculated: return gradePresentation.value == nil ? "Grade" : "Calculated from assignments"
        }
    }

    private var whatIfDelta: Double? {
        guard hasEffectiveWhatIfChanges, hasCurrentGradeInfo,
              let official = gradeInfo?.score, official.isFinite,
              let estimate = gradePresentation.value, estimate.isFinite else { return nil }
        let delta = estimate - official
        return abs(delta) >= 0.005 ? delta : nil
    }

    private var gradeAccessibilityValue: String {
        if loading && !hasCurrentGradeInfo { return store.selectedTerm.displayName }
        var parts = [store.selectedTerm.displayName, GradeFormat.spokenCourseGrade(displayGrade)]
        if displayGrade == nil, let start = futureQuarterStart { parts.append("Starts \(schoolDayLabel(start))") }
        if let whatIfDelta {
            parts.append((whatIfDelta > 0 ? "+" : "−") + GradeFormat.twoDecimals(abs(whatIfDelta)) + " compared with Skyward")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Grade goal

    /// Opens planning for this class in the term shown. Available with or
    /// without what-if; planning never changes a score.
    private var gradeGoalRow: some View {
        NavigationLink(value: CoursesRoute.gradeGoal(course, store.selectedTerm)) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grade goal")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.ink)
                    Text(store.selectedTerm.isSemester
                         ? "Find the exam score a target semester grade needs."
                         : "Find the score a target grade needs.")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.faint)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(!liveCourse.availableTerms.contains(store.selectedTerm))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plans a target grade for \(store.selectedTerm.displayName)")
        .accessibilityIdentifier("course.gradeGoal")
    }

    // MARK: - Reminders

    /// A personal reminder for a real Skyward assignment. Skyward's date is
    /// offered only when it is a valid school date.
    private func remind(_ assignment: CalcAssignment) {
        let candidates = store.selectedTerm.isSemester ? impactCandidates(for: assignment) : []
        let source = candidates.count == 1 ? candidates[0].assignment : assignment
        let term = candidates.count == 1 ? candidates[0].quarter
            : (TermLabel.allCases.first { $0.shortName == assignment.term } ?? store.selectedTerm)
        reminder = ReminderRequest(
            accountScope: store.notifications.accountScope ?? "", course: liveCourse, term: term,
            assignmentID: loadedGradebook(for: term).flatMap {
                AssignmentLink.sourceAssignmentID(for: source.id, course: liveCourse, term: term, gradeInfo: $0)
            } ?? source.id,
            title: assignment.name, dueDay: SchoolCalendarDate.normalize(assignment.dueDate)
        )
    }

    private func remindAboutExam(name: String, dueDate: String) {
        reminder = ReminderRequest(
            accountScope: store.notifications.accountScope ?? "", course: liveCourse, term: store.selectedTerm, assignmentID: "final-exam-\(examType)",
            title: name, dueDay: SchoolCalendarDate.normalize(dueDate)
        )
    }

    // MARK: - Scenarios and impact

    /// Skyward's live gradebooks and posted values for `term`, the selected
    /// term or one of its quarters. No local edits; nil until this term's
    /// gradebook has loaded.
    private func whatIfSource(for term: TermLabel) -> WhatIfScenarioSource? {
        let selected = store.selectedTerm
        guard hasCurrentGradeInfo, let gradeInfo,
              term == selected || selected.whatIfQuarterTerms.contains(term) else { return nil }
        var gradebooks: [String: GradeInfoResult] = [:]
        var posted: [String: Double] = [:]
        for quarter in term.whatIfQuarterTerms {
            let info = selected.isSemester ? quarterGradeInfo[quarter.shortName] : gradeInfo
            if let info { gradebooks[quarter.shortName] = info }
            if let score = liveCourse.currentScores.first(where: { $0.bucket == quarter.shortName })?.score {
                posted[quarter.shortName] = score
            }
        }
        let official = term == selected
            ? gradeInfo.score
            : quarterGradeInfo[term.shortName]?.score ?? posted[term.shortName]
        return WhatIfScenarioSource(
            classKey: classKey,
            className: course.courseName,
            term: term,
            quarterGradebooks: gradebooks,
            postedQuarterGrades: posted,
            officialGrade: official,
            officialExamGrade: term.isSemester ? officialFinalExamGrade : nil
        )
    }

    private var impactQuarterSources: [String: WhatIfScenarioSource] {
        store.selectedTerm.whatIfQuarterTerms.reduce(into: [:]) { sources, quarter in
            sources[quarter.shortName] = whatIfSource(for: quarter)
        }
    }

    /// "Current changes" in Scenarios uses this screen's own estimate.
    private var scenarioCurrentState: WhatIfScenarioCurrentState {
        let hasChanges = hasEffectiveWhatIfChanges
        return WhatIfScenarioCurrentState(
            officialValue: gradeInfo?.score,
            hasEffectiveChanges: hasChanges,
            estimate: hasChanges ? gradePresentation.value : nil
        )
    }

    private func openScenarios() {
        // Commit the active field synchronously, so Save reads the stored edit.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard let scope = store.localAccountScope, hasCurrentGradeInfo else { return }
        scenarioSheet = WhatIfScenarioSheetContext(
            accountScope: scope, classKey: classKey, term: store.selectedTerm, courseTitle: courseName
        )
    }

    private func scenarioApplied(_ context: WhatIfScenarioSheetContext) {
        guard context.classKey == classKey, context.term == store.selectedTerm,
              store.localAccountScope == context.accountScope else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showCalculated = WhatIfStore.showCalculated(classKey: classKey)
        }
        animateWhatIfChange { reloadWhatIf() }
    }

    /// The gradebook a quarter's official rows come from on this screen.
    private func loadedGradebook(for quarter: TermLabel) -> GradeInfoResult? {
        guard hasCurrentGradeInfo else { return nil }
        return store.selectedTerm.isSemester ? quarterGradeInfo[quarter.shortName] : gradeInfo
    }

    /// Official quarter rows the tapped row stands for. Quarter rows match by
    /// ID. Semester rows have semester IDs, so they match quarter rows by
    /// name, category, date and possible points; any repeat is left for an
    /// explicit choice.
    private func impactCandidates(for assignment: CalcAssignment) -> [AssignmentImpactCandidate] {
        guard hasCurrentGradeInfo, !assignment.artificial, assignment.category != "Final Exam" else { return [] }
        let official = editableOfficialAssignments.filter { $0.category != "Final Exam" }
        let exact = official.filter { $0.id == assignment.id }
        let matches = exact.isEmpty
            ? official.filter {
                $0.name == assignment.name && $0.category == assignment.category
                    && $0.dueDate == assignment.dueDate && $0.outOf == assignment.outOf
            }
            : exact
        return matches.compactMap { row in
            TermLabel.allCases.first { !$0.isSemester && $0.shortName == row.term }
                .map { AssignmentImpactCandidate(assignment: row, quarter: $0) }
        }
    }

    private func showImpact(for assignment: CalcAssignment) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard let scope = store.localAccountScope else { return }
        let term = store.selectedTerm
        let candidates = impactCandidates(for: assignment)
        var unavailable: String?
        if candidates.isEmpty {
            if let missing = term.whatIfQuarterTerms.first(where: { loadedGradebook(for: $0) == nil }) {
                unavailable = "\(missing.displayName)'s gradebook hasn't loaded, so Elevate can't find this assignment there. Refresh the class and try again."
            } else {
                unavailable = "This assignment isn't in the loaded quarter gradebook. Refresh the class and try again."
            }
        }
        impactRequest = AssignmentImpactRequest(
            accountScope: scope, classKey: classKey, term: term,
            title: assignment.name, category: assignment.category, dueDate: assignment.dueDate,
            candidates: candidates, unavailableMessage: unavailable
        )
    }

    /// Impact's "Try in What-if": one local override on the official row,
    /// keeping any independent no-count choice, then What-if on.
    private func tryImpact(
        _ request: AssignmentImpactRequest, candidate: AssignmentImpactCandidate, earned: Double
    ) -> String? {
        guard request.classKey == classKey, request.term == store.selectedTerm,
              let scope = store.localAccountScope, scope == request.accountScope,
              WhatIfStore.accountScope == scope else {
            return "The account or term changed while this was open. Nothing was changed."
        }
        guard WhatIfScenarioEvaluator.validNumber(earned) else { return "Enter a number of points." }
        guard semesterCalculationAvailable,
              let original = editableOfficialAssignments.first(where: { $0.id == candidate.assignment.id }) else {
            return "This assignment is no longer in the loaded gradebook. Refresh the class and try again."
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if !isWhatIfActive {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { showCalculated = true }
            WhatIfStore.setShowCalculated(true, classKey: classKey)
        }
        overrideScore(of: original, to: earned)
        feedbackRevision += 1
        return nil
    }

    // MARK: - What-if

    private var whatIfSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: Binding(
                get: { isWhatIfActive },
                set: { newValue in
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    // Switching modes changes every lazy row's width and height.
                    // Apply that layout atomically so offscreen row estimates do
                    // not churn while the scroll view interpolates its content size.
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showCalculated = newValue
                    }
                    WhatIfStore.setShowCalculated(newValue, classKey: classKey)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What-if")
                        .font(.body.weight(.medium))
                    Text(isWhatIfActive
                        ? "Change any score below or add an assignment. Saved on this iPhone only; Skyward is never changed."
                        : "Try scores without changing Skyward.")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.themeAccent)
            .disabled(!semesterCalculationAvailable)
            .sensoryFeedback(.selection, trigger: showCalculated)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .accessibilityIdentifier("whatif.toggle")

            if store.selectedTerm.isSemester, !semesterCalculationAvailable {
                whatIfNote("What-if needs both quarter gradebooks. Refresh to try loading them again.")
            } else if store.selectedTerm.isSemester, semesterCalculationError != nil {
                whatIfNote("Using previously saved quarter details for this prediction.")
            }

            if isWhatIfActive {
                whatIfActions
            }
        }
    }

    private func whatIfNote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Reset, once there is something to reset, and Scenarios, which stays
    /// available without changes so saved scenarios can still be applied.
    /// Adding an assignment lives with the assignments it adds to.
    private var whatIfActions: some View {
        let canReset = !whatIfAssignments.isEmpty || !gradeOverrides.isEmpty || hasFinalExamEstimateForSelectedTerm
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            if canReset {
                resetWhatIfButton
            }
            scenariosButton
        }
    }

    private var scenariosButton: some View {
        Button(action: openScenarios) {
            Label {
                Text("Scenarios")
            } icon: {
                Image(systemName: "square.stack")
                    .font(.caption.weight(.bold))
            }
        }
        .buttonStyle(QuietButtonStyle())
        .disabled(!hasCurrentGradeInfo || store.localAccountScope == nil)
        .accessibilityLabel("What-if scenarios")
        .accessibilityHint("Save, compare and apply named what-if changes")
        .accessibilityIdentifier("scenario.open")
    }

    /// Opens the add sheet from the Assignments heading, in what-if mode.
    private var addWhatIfButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Label {
                Text("Add")
            } icon: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
            }
        }
        .buttonStyle(QuietButtonStyle())
        .accessibilityLabel("Add what-if assignment")
        .accessibilityIdentifier("whatif.add")
    }

    private var resetWhatIfButton: some View {
        Button {
            // Commit the active field synchronously before clearing the store;
            // a later blur must not bring an old edit back after reset.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            animateWhatIfChange { resetWhatIf() }
            feedbackRevision += 1
        } label: {
            Label {
                Text("Reset changes")
            } icon: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption.weight(.bold))
            }
        }
        .buttonStyle(QuietButtonStyle())
        .accessibilityLabel("Reset what-if changes")
        .accessibilityIdentifier("whatif.reset")
    }

    // MARK: - Breakdown

    private func schoolDayLabel(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .omitted,
                                      timeZone: TimeZone(identifier: "America/Chicago")!).month(.abbreviated).day())
    }

    private var futureQuarterStart: Date? {
        SchoolCalendar.upcomingQuarterStart(term: store.selectedTerm)
    }

    @ViewBuilder
    private var categoriesSection: some View {
        let categories = gradeInfo?.gradebook.filter { $0.category != "Final Exam" } ?? []
        if !categories.isEmpty {
            let results = summary.categories
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if reduceMotion {
                        showsBreakdown.toggle()
                    } else {
                        withAnimation(.snappy(duration: 0.25)) { showsBreakdown.toggle() }
                    }
                } label: {
                    SectionHeading(title: "Grade breakdown", count: "\(categories.count)") {
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.muted)
                            .rotationEffect(.degrees(showsBreakdown ? 0 : -90))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Grade breakdown, \(categories.count) categories")
                .accessibilityValue(showsBreakdown ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("course.breakdown")

                if showsBreakdown {
                    // Open rows like the rest of the screen: each category's
                    // share of the grade and its points beneath the name,
                    // the average as the one trailing figure.
                    VStack(spacing: 0) {
                        ForEach(Array(categories.enumerated()), id: \.element.category) { index, category in
                            if index > 0 { InsetDivider() }
                            categoryRow(category, result: results[category.category])
                        }
                    }
                }
            }
            .padding(.top, sectionSpacing)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeading("Grade breakdown")
                Text(futureQuarterStart == nil ? "No category grades posted yet." : "Available when this quarter's grades are posted.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, sectionSpacing)
            .accessibilityIdentifier("course.breakdown.empty")
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: GradeCategory, result: GradeSummary.CategoryResult?) -> some View {
        let baseWeight = category.weight ?? 0
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.category)
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    Text(categoryAverage(result))
                        .font(.figure(.title3))
                        .foregroundStyle(GradeTier(result?.average).textColor)
                    Text(categoryDetail(result: result, baseWeight: baseWeight))
                        .font(.figure(.footnote, weight: .regular))
                        .foregroundStyle(Color.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.category)
                            .font(.body)
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                        Text(categoryDetail(result: result, baseWeight: baseWeight))
                            .font(.figure(.footnote, weight: .regular))
                            .foregroundStyle(Color.muted)
                            .lineLimit(2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(categoryAverage(result))
                        .font(.figure(.body))
                        .foregroundStyle(GradeTier(result?.average).textColor)
                        .contentTransition(.numericText(value: result?.average ?? 0))
                        .lineLimit(1)
                        .frame(minWidth: averageColumn, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.category)
        .accessibilityValue(categoryAccessibilityValue(result: result, baseWeight: baseWeight))
    }

    private func categoryAverage(_ result: GradeSummary.CategoryResult?) -> String {
        GradeFormat.twoDecimals(result?.average)
    }

    /// The category's share of the grade, the weight in effect when other
    /// categories have nothing graded yet, and the points behind the
    /// average: "30% of grade, 19/20 pts", "20% of grade (counts 40% now),
    /// 19/20 pts", "0% of grade, 4/5 pts", "20% of grade, nothing graded".
    private func categoryDetail(result: GradeSummary.CategoryResult?, baseWeight: Double) -> String {
        let share = "\(GradeFormat.upToTwoDecimals(baseWeight))% of grade"
        guard let result else { return share + ", nothing graded" }
        let points = "\(GradeFormat.upToTwoDecimals(result.rawPoints))/\(GradeFormat.upToTwoDecimals(result.rawTotal)) pts"
        if abs(result.weight - baseWeight) >= 0.05 {
            return share + " (counts \(GradeFormat.upToTwoDecimals(result.weight))% now), " + points
        }
        return share + ", " + points
    }

    private func categoryAccessibilityValue(result: GradeSummary.CategoryResult?, baseWeight: Double) -> String {
        guard let result else {
            return "\(GradeFormat.upToTwoDecimals(baseWeight)) percent weight, nothing graded yet"
        }
        var parts = [
            GradeFormat.spokenCourseGrade(result.average),
            "\(GradeFormat.upToTwoDecimals(baseWeight)) percent weight",
            "\(GradeFormat.upToTwoDecimals(result.rawPoints)) of \(GradeFormat.upToTwoDecimals(result.rawTotal)) points",
        ]
        if abs(result.weight - baseWeight) >= 0.05 {
            parts.append("counts \(GradeFormat.upToTwoDecimals(result.weight)) percent until other categories are graded")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Final exam

    private var finalExamSection: some View {
        let focusID = "\(store.selectedTerm.bucket)|exam|\(examType)"
        let examName = store.selectedTerm == .sm1 ? "Exam 1" : "Exam 2"
        let realAssignment = apiAssignments.first { $0.category == "Final Exam" }
        let dueDate = realAssignment?.dueDate ?? ""
        let estimate = finalExamGrades[examType]
        let realGrade = effectiveFinalExamGrade
        let shown: Double? = (isWhatIfActive && estimate != nil) ? estimate : realGrade

        let canRemind = officialFinalExamGrade == nil
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Semester exam", count: nil) {
                if canRemind {
                    Button {
                        remindAboutExam(name: examName, dueDate: dueDate)
                    } label: {
                        Label {
                            Text("Remind me")
                        } icon: {
                            Image(systemName: "bell")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityLabel("Remind me about \(examName)")
                    .accessibilityIdentifier("exam.remind")
                }
            }
            Text(verbatim: "Counts for 20% of the semester grade when an exam score exists. Each quarter counts 40%.")
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            AssignmentRow(
                assignment: CalcAssignment(
                    id: "final-exam-\(examType)", className: course.courseName, name: examName,
                    term: examType, category: "Final Exam", grade: shown, outOf: 100,
                    dueDate: dueDate, artificial: isWhatIfActive && estimate != nil, meta: []
                ),
                marker: isWhatIfActive && estimate != nil ? .estimate : nil,
                editable: isWhatIfActive,
                onEditGrade: { newGrade in
                    guard isWhatIfActive else { return }
                    WhatIfStore.setFinalExamGrade(newGrade, examType: examType, classKey: classKey)
                    animateWhatIfChange { reloadWhatIf() }
                },
                onRemind: canRemind ? { remindAboutExam(name: examName, dueDate: dueDate) } : nil,
                finishScoreRequest: finishScoreTargets.contains(focusID) ? finishScoreRequest : 0,
                finishActiveScoreEditing: { finishScoreEditing() },
                onFocusChange: { focused in
                    scoreFocusChanged(focused, rowID: focusID)
                }
            )
            .id(focusID)
        }
        .padding(.top, sectionSpacing)
    }

    // MARK: - Assignments

    private var assignmentsSection: some View {
        let assignments = displayedAssignments
        let hasUnfilteredAssignments = meshedAssignments.contains { $0.category != "Final Exam" }
        // In what-if mode, Add sits with the list it adds to: beside the
        // filter on the heading line, on its own line at accessibility sizes.
        let showsAdd = isWhatIfActive
        let addOnOwnLine = dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "Assignments", count: "\(assignments.count)") {
                HStack(spacing: 4) {
                    if showsAdd && !addOnOwnLine {
                        addWhatIfButton
                    }
                    if hasUnfilteredAssignments || hasActiveAssignmentControls {
                        filterMenu
                    }
                }
            }

            if showsAdd && addOnOwnLine {
                addWhatIfButton
            }

            if let description = activeControlsDescription {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Clear", action: clearAssignmentControls)
                        .buttonStyle(ActionTextButtonStyle())
                        .frame(minWidth: 44)
                        .accessibilityLabel("Clear sort and filters")
                        .accessibilityIdentifier("assignments.clearFilters")
                }
            }

            if assignmentLinkUnavailable {
                Text("This assignment is no longer in this quarter's gradebook.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
                    .accessibilityIdentifier("assignment.linkUnavailable")
            }
            if assignments.isEmpty {
                Group {
                    if hasUnfilteredAssignments {
                        EmptyStateView(title: "No assignments match these filters")
                    } else {
                        EmptyStateView(title: futureQuarterStart == nil ? "No assignments posted" : "\(store.selectedTerm.shortName) hasn't started",
                                       message: futureQuarterStart.map { "Begins \(schoolDayLabel($0)). Assignments will appear when posted." })
                    }
                }
                .accessibilityIdentifier("assignments.empty")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(assignments) { assignment in
                        // Keep one lazy child per assignment. The divider must
                        // travel with its row when keyboard dismissal changes
                        // which editable rows are inside the viewport.
                        VStack(spacing: 0) {
                            if assignment.id != assignments.first?.id { InsetDivider() }
                            assignmentRow(assignment)
                        }
                        .id(assignment.id)
                        .background(highlightsLinkedAssignment && openedAssignmentID == assignment.id ? Color.well : Color.clear)
                        .accessibilityFocused($accessibilityAssignmentID, equals: assignment.id)
                        .accessibilityIdentifier(openedAssignmentID == assignment.id ? "assignment.linked" : "assignment.row")
                    }
                }
                // Each mode has different score widths and row heights. Start
                // with fresh lazy layout estimates when switching between them.
                .id(isWhatIfActive)
            }
        }
        .padding(.top, sectionSpacing)
    }

    private func assignmentRow(_ assignment: CalcAssignment) -> some View {
        let focusID = "\(store.selectedTerm.bucket)|assignment|\(assignment.id)"
        let added = whatIfAssignments.first { $0.id == assignment.id }
        let original = isWhatIfActive && added == nil ? skywardOriginal(of: assignment) : nil
        let marker: AssignmentRow.Marker?
        if let added {
            marker = .added(term: store.selectedTerm.isSemester ? added.term : nil)
        } else if let original {
            marker = .edited(original: original.grade, outOf: original.outOf)
        } else {
            marker = nil
        }

        return AssignmentRow(
            assignment: assignment,
            marker: marker,
            editable: isWhatIfActive,
            onEditGrade: { newGrade in
                // A replaced editable row can still receive a disappearance or
                // focus callback after the mode has already been turned off.
                guard isWhatIfActive else { return }
                if var match = added {
                    match.grade = newGrade
                    WhatIfStore.update(match, classKey: classKey)
                    animateWhatIfChange { reloadWhatIf() }
                } else {
                    overrideScore(of: assignment, to: newGrade)
                }
            },
            onChangeStatus: added == nil ? nil : { status in
                if var match = added {
                    match.resolvedStatus = status
                    WhatIfStore.update(match, classKey: classKey)
                    animateWhatIfChange { reloadWhatIf() }
                }
            },
            onChangeNoCount: added != nil ? nil : { noCount in
                guard isWhatIfActive else { return }
                WhatIfStore.setNoCountOverride(noCount, assignment: assignment, classKey: classKey)
                animateWhatIfChange { reloadWhatIf() }
            },
            categoryChoices: addAssignmentCategoriesByTerm[assignment.term] ?? [],
            onChangeCategory: added == nil ? nil : { category in
                guard isWhatIfActive, var match = added else { return }
                match.category = category
                WhatIfStore.update(match, classKey: classKey)
                animateWhatIfChange { reloadWhatIf() }
            },
            onDelete: added == nil ? nil : {
                WhatIfStore.remove(id: assignment.id, classKey: classKey, term: store.selectedTerm)
                animateWhatIfChange { reloadWhatIf() }
            },
            onRestore: original == nil ? nil : {
                restoreSkywardValue(of: assignment)
            },
            // Reminders belong to real Skyward work, never to added what-if rows.
            onRemind: added != nil ? nil : { remind(assignment) },
            // Impact uses Skyward's rows, so added what-if rows have none.
            onShowImpact: added != nil ? nil : { showImpact(for: assignment) },
            finishScoreRequest: finishScoreTargets.contains(focusID) ? finishScoreRequest : 0,
            finishActiveScoreEditing: { finishScoreEditing() },
            onFocusChange: { focused in
                scoreFocusChanged(focused, rowID: focusID)
            }
        )
    }

    private func clearAssignmentControls() {
        sortOption = .date
        sortAscending = false
        categoryFilter.removeAll()
        assignmentFilter.removeAll()
        gradeFilter.removeAll()
    }

    /// "Sorted by grade, lowest first. Showing Missing, Tests."
    private var activeControlsDescription: String? {
        guard hasActiveAssignmentControls else { return nil }
        var sentences: [String] = []
        if sortOption != .date || sortAscending {
            sentences.append("Sorted by \(sortOption.rawValue.lowercased()), \((sortAscending ? ascendingLabel : descendingLabel).lowercased()).")
        }
        let filters = assignmentFilter.map(\.rawValue).sorted()
            + categoryFilter.sorted()
            + AssignmentGradeRange.allCases.filter(gradeFilter.contains).map(\.rawValue)
        if !filters.isEmpty {
            sentences.append("Showing \(filters.joined(separator: ", ")).")
        }
        return sentences.joined(separator: " ")
    }

    /// Native menus keep sorting and filtering beside the assignment list.
    private var filterMenu: some View {
        Menu {
            Menu {
                Menu {
                    ForEach(AssignmentSortOption.allCases) { option in
                        Button {
                            sortOption = option
                            sortAscending = option == .category
                        } label: {
                            if sortOption == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(sortOption.rawValue, systemImage: "arrow.up.arrow.down")
                }

                Menu {
                    Button {
                        sortAscending = true
                    } label: {
                        if sortAscending {
                            Label(ascendingLabel, systemImage: "checkmark")
                        } else {
                            Text(ascendingLabel)
                        }
                    }
                    Button {
                        sortAscending = false
                    } label: {
                        if !sortAscending {
                            Label(descendingLabel, systemImage: "checkmark")
                        } else {
                            Text(descendingLabel)
                        }
                    }
                } label: {
                    Label(
                        sortAscending ? ascendingLabel : descendingLabel,
                        systemImage: "arrow.up.arrow.down.circle"
                    )
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }

            Menu {
                if !availableFilterCategories.isEmpty {
                    Menu {
                        ForEach(availableFilterCategories, id: \.self) { category in
                            Button {
                                if categoryFilter.contains(category) {
                                    categoryFilter.remove(category)
                                } else {
                                    categoryFilter.insert(category)
                                }
                            } label: {
                                if categoryFilter.contains(category) {
                                    Label(category, systemImage: "checkmark")
                                } else {
                                    Text(category)
                                }
                            }
                        }
                    } label: {
                        Label(
                            categoryFilter.isEmpty ? "Categories" : "Categories (\(categoryFilter.count))",
                            systemImage: "tag"
                        )
                    }
                }

                Menu {
                    ForEach(AssignmentFilterOption.allCases) { option in
                        Button {
                            if assignmentFilter.contains(option) {
                                assignmentFilter.remove(option)
                            } else {
                                assignmentFilter.insert(option)
                            }
                        } label: {
                            if assignmentFilter.contains(option) {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(
                        assignmentFilter.isEmpty
                            ? "Assignment types"
                            : "Assignment types (\(assignmentFilter.count))",
                        systemImage: "checklist"
                    )
                }

                Menu {
                    ForEach(AssignmentGradeRange.allCases) { range in
                        Button {
                            if gradeFilter.contains(range) {
                                gradeFilter.remove(range)
                            } else {
                                gradeFilter.insert(range)
                            }
                        } label: {
                            if gradeFilter.contains(range) {
                                Label(range.rawValue, systemImage: "checkmark")
                            } else {
                                Text(range.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(
                        gradeFilter.isEmpty ? "Grade" : "Grade (\(gradeFilter.count))",
                        systemImage: "percent"
                    )
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease")
            }

            if hasActiveAssignmentControls {
                Divider()
                Button("Reset sort and filters", systemImage: "arrow.counterclockwise") {
                    clearAssignmentControls()
                }
            }
        } label: {
            Image(systemName: hasActiveAssignmentControls
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
                .font(.title3)
                .foregroundStyle(hasActiveAssignmentControls ? Color.themeAccent : Color.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScopePressStyle())
        .accessibilityLabel("Sort and filter assignments")
        .accessibilityValue(hasActiveAssignmentControls ? "Active" : "")
        .accessibilityIdentifier("assignments.filter")
    }

    private var availableFilterCategories: [String] {
        Array(Set(gradeInfo?.gradebook.map(\.category).filter { $0 != "Final Exam" } ?? []))
            .sorted()
    }

    private var ascendingLabel: String {
        switch sortOption {
        case .date: return "Oldest first"
        case .grade: return "Lowest first"
        case .category: return "A–Z"
        }
    }

    private var descendingLabel: String {
        switch sortOption {
        case .date: return "Newest first"
        case .grade: return "Highest first"
        case .category: return "Z–A"
        }
    }

    private var hasActiveAssignmentControls: Bool {
        sortOption != .date
            || sortAscending
            || !categoryFilter.isEmpty
            || !assignmentFilter.isEmpty
            || !gradeFilter.isEmpty
    }
}

/// Local what-if quarter math shared by class detail and grade goals, so a
/// goal planned "with what-if" uses exactly the estimate the class shows.
enum WhatIfQuarterMath {
    static func assignment(from assignment: WhatIfAssignment) -> CalcAssignment {
        CalcAssignment(
            id: assignment.id,
            className: assignment.className,
            name: assignment.name,
            term: assignment.term,
            category: assignment.category,
            grade: assignment.grade,
            outOf: assignment.outOf,
            dueDate: assignment.dueDate,
            artificial: true,
            meta: metadata(for: assignment.resolvedStatus)
        )
    }

    static func metadata(for status: WhatIfAssignmentStatus) -> [AssignmentMeta] {
        switch status {
        case .counted:
            return []
        case .noCount:
            return [AssignmentMeta(type: "noCount", note: "Excluded from grade")]
        case .missing:
            return [AssignmentMeta(type: "missing", note: "Missing")]
        case .absent:
            return [AssignmentMeta(type: "absent", note: "Absent")]
        }
    }

    /// Skyward's posted semester exam: the semester gradebook's first counted
    /// exam entry, otherwise the course record's EX score. Nil means none posted.
    static func postedExamGrade(semesterInfo: GradeInfoResult?, course: UnifiedCourseData, examType: String) -> Double? {
        if let assignment = semesterInfo?.gradebook
            .first(where: { $0.category == "Final Exam" })?
            .assignments.first(where: { !$0.meta.contains { $0.type == "noCount" } }) {
            if let percentage = GradeCalculator.percentage(
                earned: assignment.pointsEarned,
                outOf: assignment.pointsTotal
            ) {
                return percentage
            }
            if let score = assignment.score, score.isFinite { return score }
            if let grade = assignment.grade { return Double(grade) }
        }
        return course.currentScores.first { $0.bucket == examType && $0.score.isFinite }?.score
    }

    /// One quarter's grade with saved local edits applied. Without the
    /// quarter's source, saved edits cannot be reconstructed or proven
    /// redundant, so the result is unavailable; an untouched quarter can
    /// still use its posted grade.
    static func quarterTotal(
        term: TermLabel,
        info: GradeInfoResult?,
        className: String,
        postedCourseGrade: Double?,
        whatIfAssignments: [WhatIfAssignment],
        overrides: [String: AssignmentGradeOverride],
        hasSavedChanges: @autoclosure () -> Bool
    ) -> Double? {
        guard let info else {
            return WhatIfGradePresentation.resolve(
                official: postedCourseGrade, calculated: nil, hasEffectiveChanges: hasSavedChanges()
            ).value
        }
        let official = AssignmentGradeEdits.assignments(from: info, className: className, term: term)
            .filter { $0.category != "Final Exam" }
        let hasChanges = whatIfAssignments.contains { $0.term == term.shortName }
            || AssignmentGradeEdits.hasEffectiveChanges(overrides, to: official)
        if !hasChanges, let posted = info.score ?? postedCourseGrade {
            return posted
        }
        let real = AssignmentGradeEdits.applying(overrides, to: official)
        let hypothetical = whatIfAssignments
            .filter { $0.term == term.shortName }
            .map(assignment(from:))
            .filter { $0.category != "Final Exam" }
        let assignments = real + hypothetical
        let weights = GradeCalculator.normalizedWeights(categories: info.gradebook, assignments: assignments)
        let hypotheticalCategories = Set(
            hypothetical
                .filter { !$0.isNoCount && $0.grade != nil && $0.outOf > 0 }
                .map(\.category)
        )
        let everyHypotheticalHasWeight = hypotheticalCategories.allSatisfy { weights[$0] != nil }
        if everyHypotheticalHasWeight {
            if let weighted = GradeCalculator.summary(
                assignments: assignments,
                categoryWeights: weights,
                sourceCategories: info.gradebook
            ).courseTotal {
                return weighted
            }
        }

        // Some Skyward gradebooks are points-based and omit category weights.
        // In that case, preserve a predictable what-if result using total points.
        let countable = assignments.filter { !$0.isNoCount && $0.grade != nil && $0.outOf > 0 }
        return GradeCalculator.pointsTotal(assignments: countable)
    }
}

private struct EditableScoreFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Assignment row

/// One ruled assignment line. In what-if mode every row's score becomes a
/// field and its options menu changes status; added rows can be deleted and
/// edited Skyward rows can be restored.
struct AssignmentRow: View {
    enum Marker: Equatable {
        /// A hypothetical assignment; the quarter is named on semester views.
        case added(term: String?)
        /// A real assignment whose score was changed locally.
        case edited(original: Double?, outOf: Double)
        /// A what-if semester exam estimate.
        case estimate
    }

    var assignment: CalcAssignment
    var marker: Marker? = nil
    var editable: Bool
    var onEditGrade: ((Double?) -> Void)?
    var onChangeStatus: ((WhatIfAssignmentStatus) -> Void)? = nil
    var onChangeNoCount: ((Bool) -> Void)? = nil
    var categoryChoices: [String] = []
    var onChangeCategory: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil
    /// A personal reminder; offered in the options and context menus and
    /// as an accessibility action, in either mode.
    var onRemind: (() -> Void)? = nil
    /// How a score on this real Skyward row moves the grade; offered in the
    /// options and context menus and as an accessibility action.
    var onShowImpact: (() -> Void)? = nil
    var finishScoreRequest = 0
    /// Ends whichever score is being edited, returning false if none is.
    /// Read at tap time so the decision uses current field focus.
    var finishActiveScoreEditing: (() -> Bool)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    @State private var editingGradeText = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingStatusChoices = false
    @State private var showingCategoryChoices = false
    @State private var gradeFieldFocused = false
    @State private var scoreSelectionRequest = 0
    @State private var scoreCommitRevision = 0
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Editable score lanes: options, then points earned (right-aligned
    /// against the slash) and the denominator. Every editable row reserves
    /// all three, so the slash and field sit at the same place whether a
    /// row is out of 100, 15 or 0, and whether or not it has options.
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 60
    @ScaledMetric(relativeTo: .subheadline) private var denominatorWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var wellHeight: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var scoreColumn: CGFloat = 104
    private static let optionsLane: CGFloat = 44

    private var editableScoreColumn: CGFloat { fieldWidth + denominatorWidth + Self.optionsLane }
    /// The field's hit height; the drawn well is `wellHeight`, centered in it.
    private var fieldHeight: CGFloat { max(44, wellHeight) }

    private var usesStackedLayout: Bool { dynamicTypeSize >= .xxLarge }

    private var percentage: Double? {
        GradeCalculator.percentage(earned: assignment.grade, outOf: assignment.outOf)
    }

    private var isEditing: Bool { editable && onEditGrade != nil }
    private var showsOptions: Bool { onRemind != nil || onShowImpact != nil || (editable && (onChangeStatus != nil || onChangeNoCount != nil || onChangeCategory != nil || onDelete != nil || onRestore != nil)) }

    var body: some View {
        // Fixed score-column widths and the fixed metadata stack keep this
        // row's height deterministic; no size probing inside the row.
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: 8) {
                    details
                    trailingControls
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailingControls
                        .frame(width: isEditing ? editableScoreColumn : scoreColumn + (showsOptions ? Self.optionsLane : 0), alignment: .trailing)
                }
            }
        }
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .overlay(alignment: .leading) {
            if marker != nil {
                // A solid accent edge in the page margin marks local,
                // hypothetical values without moving the text.
                Rectangle()
                    .fill(Color.themeAccent)
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .offset(x: -(Metrics.page / 2 + 1.5))
                    .accessibilityHidden(true)
            }
        }
        .background {
            if isEditing {
                GeometryReader { geometry in
                    Color.clear.preference(key: EditableScoreFramesKey.self,
                        value: [assignment.id: geometry.frame(in: .named("assignmentEditing"))])
                }
            }
        }
        .background {
            // The background handles gaps and padding without intercepting
            // the field's caret gestures or the options button.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { rowTapped() }
        }
        .contentShape(Rectangle())
        .onAppear {
            editingGradeText = assignment.grade.map { trimNumber($0) } ?? ""
            if gradeFieldFocused { onFocusChange?(true) }
        }
        .onChange(of: assignment.grade) { _, grade in
            // Restore/reset can change the source while this field still has
            // focus. Reflect that value so a later blur cannot recommit the old edit.
            editingGradeText = grade.map { trimNumber($0) } ?? ""
        }
        .onChange(of: gradeFieldFocused) { _, focused in
            onFocusChange?(focused)
        }
        .onDisappear {
            onFocusChange?(false)
        }
        .contextMenu {
            if editable, let onRestore {
                Button(action: onRestore) {
                    Label("Restore Skyward Score", systemImage: "arrow.uturn.backward")
                }
            }
            if editable, onDelete != nil {
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            if let onShowImpact {
                Button(action: onShowImpact) {
                    Label("See Impact…", systemImage: "function")
                }
            }
            if let onRemind {
                Button(action: onRemind) {
                    Label("Remind Me…", systemImage: "bell")
                }
            }
        }
        .sheet(isPresented: $showingStatusChoices) {
            ChoiceSheet(
                title: "Assignment status",
                groups: [ChoiceGroup(title: nil, options: WhatIfAssignmentStatus.allCases.map { status in
                    ChoiceOption(value: status, title: status.rawValue, identifier: "whatif.status.\(status.rawValue)")
                })],
                selection: Binding(get: { currentStatus }, set: { onChangeStatus?($0) })
            )
        }
        .sheet(isPresented: $showingCategoryChoices) {
            ChoiceSheet(
                title: "Assignment category",
                groups: [ChoiceGroup(title: nil, options: Array(Set(categoryChoices + [assignment.category])).sorted().map {
                    ChoiceOption(value: $0, title: $0, identifier: "whatif.category.\($0)")
                })],
                selection: Binding(get: { assignment.category }, set: { onChangeCategory?($0) })
            )
        }
        .alert("Delete what-if assignment?", isPresented: $showingDeleteConfirmation) {
            Button("Delete assignment", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.selection, trigger: scoreCommitRevision)
        .accessibilityElement(children: editable || onRemind != nil || onShowImpact != nil ? .contain : .combine)
        .accessibilityLabel(assignment.name)
        .accessibilityValue(assignmentAccessibilityValue)
        .accessibilityActions {
            if let onShowImpact {
                Button("See impact", action: onShowImpact)
            }
            if let onRemind {
                Button("Remind me", action: onRemind)
            }
        }
    }

    // MARK: Details

    private var categoryHighlight: some View {
        Text(verbatim: assignment.category)
            .font(.footnote.weight(.medium))
            .foregroundStyle(assignment.isNoCount ? Color.muted : Color.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.selection, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color.muted, lineWidth: Metrics.line)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Regular weight: names are read, and the semibold section
            // heading above the list stays the only heavy line.
            Text(assignment.name)
                .font(.body)
                .strikethrough(assignment.isNoCount)
                .foregroundStyle(assignment.isNoCount ? Color.muted : Color.ink)
                .lineLimit(usesStackedLayout ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if usesStackedLayout {
                VStack(alignment: .leading, spacing: 2) {
                    statusText
                    categoryHighlight
                    if !assignment.dueDate.isEmpty {
                        Text("Due \(assignment.dueDate)").monospacedDigit()
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.muted)
            } else {
                // Keep metadata height deterministic as the score column changes.
                VStack(alignment: .leading, spacing: 2) {
                    statusText
                    categoryHighlight
                    dateText
                }
                .font(.footnote)
                .foregroundStyle(Color.muted)
            }

            if let markerText {
                Text(markerText)
                    .font(.footnote)
                    .foregroundStyle(Color.themeAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .layoutPriority(1)
        .contentShape(Rectangle())
        .onTapGesture { rowTapped() }
    }

    /// Status as plain words; only Missing is colored.
    @ViewBuilder
    private var statusText: some View {
        if assignment.isMissing {
            Text("Missing")
                .fontWeight(.semibold)
                .foregroundStyle(Color.gradeAttention)
        } else if assignment.isAbsent {
            Text("Absent")
                .fontWeight(.semibold)
                .foregroundStyle(Color.gradeWarning)
        } else if assignment.isNoCount {
            Text("No count")
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private var dateText: some View {
        if !assignment.dueDate.isEmpty {
            Text(assignment.dueDate)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var markerText: String? {
        switch marker {
        case .added(let term):
            return term.map { "What-if, added to \($0)" } ?? "What-if, added"
        case .edited(let original, let outOf):
            let score = original.map { "\(GradeFormat.upToTwoDecimals($0))/\(GradeFormat.upToTwoDecimals(outOf))" } ?? "no score"
            return "What-if, Skyward has \(score)"
        case .estimate:
            return "What-if estimate"
        case nil:
            return nil
        }
    }

    // MARK: Score

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 0) {
            if isEditing || showsOptions {
                // Options sit before the well so the well's right edge meets
                // the page margin. The lane is held empty on rows without
                // options (official rows, the exam) to keep the column fixed.
                Group {
                    if showsOptions {
                        optionsMenu
                    } else {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { rowTapped() }
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: Self.optionsLane, height: 44)
            }
            scoreView
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var scoreView: some View {
        if isEditing {
            // One quiet well holds the score as it reads, "12.5/15": the
            // typed points end at the slash, and the original denominator,
            // including a bonus /0, stays beside it. No outline; focus
            // shifts the well to the selection fill.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                AssignmentScoreField(
                    text: $editingGradeText,
                    displayText: assignment.grade.map { GradeFormat.upToTwoDecimals($0) } ?? "",
                    focused: $gradeFieldFocused,
                    selectionRequest: scoreSelectionRequest,
                    finishRequest: finishScoreRequest,
                    onCommit: commitGrade
                )
                    .padding(.leading, 8)
                    .frame(width: fieldWidth, height: fieldHeight)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        let font = UIFontMetrics(forTextStyle: .body).scaledFont(
                            for: .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
                        )
                        return (dimensions.height - font.lineHeight) / 2 + font.ascender
                    }
                    .accessibilityLabel("Points earned")
                    .accessibilityHint("Out of \(outOfText) points")
                    .accessibilityIdentifier("whatif.grade.\(assignment.id)")

                Text("/\(outOfText)")
                    .font(.figure(.subheadline, weight: .regular))
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, 1)
                    .padding(.trailing, 8)
                    .frame(width: denominatorWidth, height: fieldHeight, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { focusScore() }
                    // Spoken in the field's hint and the row's value.
                    .accessibilityHidden(true)
            }
            .background {
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(Color.well)
                    .padding(.vertical, (fieldHeight - wellHeight) / 2)
            }
            .background {
                // The whole well, including the field's leading inset, is an
                // explicit score target: it selects this score even while
                // another is being edited. The field above keeps its caret.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { focusScore() }
                    .accessibilityHidden(true)
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(gradeText)
                        .font(.figure(.body))
                        .foregroundStyle(assignment.grade == nil ? Color.muted : Color.ink)
                    Text("/\(outOfText)")
                        .font(.figure(.footnote, weight: .regular))
                        .foregroundStyle(Color.muted)
                }
                .contentTransition(.numericText(value: assignment.grade ?? 0))

                if let percentage, !assignment.isNoCount, assignment.outOf != 100 {
                    Text(GradeFormat.twoDecimals(percentage) + "%")
                        .font(.figure(.caption, weight: .regular))
                        .foregroundStyle(GradeTier(percentage) == .attention ? Color.gradeAttention : Color.muted)
                }
            }
            .lineLimit(1)
        }
    }

    private var optionsMenu: some View {
        Menu {
            if editable {
            if let onChangeNoCount {
                Button { onChangeNoCount(!assignment.isNoCount) } label: {
                    Label(assignment.isNoCount ? "Count in estimate" : "Make no count", systemImage: assignment.isNoCount ? "checkmark.circle" : "minus.circle")
                }
                .accessibilityIdentifier("whatif.noCount.\(assignment.id)")
            }
            if onChangeCategory != nil {
                Button { showingCategoryChoices = true } label: {
                    Label("Change category", systemImage: "folder")
                }
                .accessibilityIdentifier("whatif.changeCategory.\(assignment.id)")
            }
            if onChangeStatus != nil {
                Button { showingStatusChoices = true } label: {
                    Label("Change status", systemImage: "checkmark.circle")
                }
                .accessibilityIdentifier("whatif.changeStatus.\(assignment.id)")
            }
            if let onRestore {
                Divider()
                Button(action: onRestore) {
                    Label("Restore Skyward Score", systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("whatif.restore.\(assignment.id)")
            }
            }
            if onShowImpact != nil || onRemind != nil {
                if editable { Divider() }
                if let onShowImpact {
                    Button(action: onShowImpact) {
                        Label("See Impact…", systemImage: "function")
                    }
                    .accessibilityIdentifier("impact.open.\(assignment.id)")
                }
                if let onRemind {
                    Button(action: onRemind) {
                        Label("Remind Me…", systemImage: "bell")
                    }
                    .accessibilityIdentifier("assignment.remind.\(assignment.id)")
                }
            }
            if editable, onDelete != nil {
                Divider()
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Label("Delete Assignment", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Assignment options")
        .accessibilityValue(currentStatus.rawValue)
        .accessibilityIdentifier("whatif.options.\(assignment.id)")
    }

    private var currentStatus: WhatIfAssignmentStatus {
        if assignment.isMissing { return .missing }
        if assignment.isAbsent { return .absent }
        if assignment.isNoCount { return .noCount }
        return .counted
    }

    /// Title, metadata, padding and the empty options lane. While any score
    /// is being edited these only commit and dismiss it; one tap never also
    /// starts editing here. Score wells are the explicit way to move on.
    private func rowTapped() {
        guard isEditing else { return }
        if finishActiveScoreEditing?() == true { return }
        focusScore()
    }

    /// Explicit score intent: the field's well and its denominator.
    private func focusScore() {
        guard isEditing else { return }
        scoreSelectionRequest += 1
        gradeFieldFocused = true
    }

    private func commitGrade(_ text: String) {
        guard editable else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if assignment.grade != nil { scoreCommitRevision += 1 }
            onEditGrade?(nil)
        } else if let grade = validNumber(trimmed) {
            if assignment.grade != grade { scoreCommitRevision += 1 }
            onEditGrade?(grade)
        } else {
            editingGradeText = assignment.grade.map { trimNumber($0) } ?? ""
        }
    }

    private var gradeText: String {
        guard let grade = assignment.grade, grade.isFinite else { return "--" }
        return GradeFormat.upToTwoDecimals(grade)
    }

    private var outOfText: String { GradeFormat.upToTwoDecimals(assignment.outOf) }

    private var assignmentAccessibilityValue: String {
        var values = [assignment.category]
        if assignment.grade?.isFinite == true {
            values.append("\(gradeText) out of \(outOfText)")
        } else {
            values.append("No grade, \(outOfText) points possible")
        }
        if assignment.isMissing { values.append("Missing") }
        if assignment.isNoCount { values.append("No count") }
        if assignment.isAbsent { values.append("Absent") }
        if let markerText { values.append(markerText) }
        if !assignment.dueDate.isEmpty {
            values.append("due \(assignment.dueDate)")
        }
        return values.joined(separator: ", ")
    }

    private func trimNumber(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        if value == value.rounded(),
           value >= Double(Int.min), value <= Double(Int.max) {
            return String(Int(value))
        }
        return String(value)
    }

    private func validNumber(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite, abs(value) <= 1_000_000 else {
            return nil
        }
        return value
    }
}

/// A loading assignment in the official row's columns: the name, then the
/// category and due date lines, with the score at the top of the trailing
/// column. Hidden from accessibility; the list announces it is loading.
private struct AssignmentRowPlaceholder: View {
    var index: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scoreColumn: CGFloat = 104

    private static let names = [16, 12, 19, 10, 14, 17]
    private static let categories = [7, 9, 6, 8, 7, 9]

    var body: some View {
        Group {
            if dynamicTypeSize >= .xxLarge {
                VStack(alignment: .leading, spacing: 8) {
                    details
                    score
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                    score
                        .frame(width: scoreColumn, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            SkeletonText(.body, length: Self.names[index % Self.names.count])
            VStack(alignment: .leading, spacing: 2) {
                // The category label's own inset keeps its line height.
                SkeletonText(.footnote.weight(.medium), length: Self.categories[index % Self.categories.count],
                             tone: .secondary)
                    .padding(.vertical, 2)
                SkeletonText(.footnote, length: dynamicTypeSize >= .xxLarge ? 12 : 8, tone: .secondary)
            }
        }
    }

    private var score: some View {
        SkeletonText(.figure(.body), length: 4)
    }
}

// MARK: - Add what-if assignment sheet

struct AddAssignmentSheet: View {
    var categoriesByTerm: [String: [String]]
    var term: TermLabel
    var onAdd: (WhatIfAssignment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = ""
    @State private var gradeText = ""
    @State private var outOfText = "100"
    @State private var status: WhatIfAssignmentStatus = .counted
    @State private var assignmentTerm: TermLabel
    @FocusState private var focusedField: Field?

    init(
        categoriesByTerm: [String: [String]],
        term: TermLabel,
        onAdd: @escaping (WhatIfAssignment) -> Void
    ) {
        self.categoriesByTerm = categoriesByTerm
        self.term = term
        self.onAdd = onAdd
        _assignmentTerm = State(initialValue: term.whatIfQuarterTerms.last ?? term)
    }

    private enum Field: Hashable {
        case name
        case grade
        case points
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Assignment") {
                    TextField("Assignment name", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .grade }

                    Picker("Category", selection: $category) {
                        ForEach(availableCategories, id: \.self) { Text($0).tag($0) }
                    }
                }

                if term.isSemester {
                    Section {
                        Picker("Counts toward", selection: $assignmentTerm) {
                            ForEach(term.whatIfQuarterTerms) { quarter in
                                Text(quarter.shortName).tag(quarter)
                            }
                        }
                    } footer: {
                        Text("Semester predictions recalculate the selected quarter, then apply the 40/40/20 semester formula.")
                    }
                }

                Section {
                    Picker("Status", selection: $status) {
                        ForEach(WhatIfAssignmentStatus.allCases) { option in
                            Label(option.rawValue, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }

                    LabeledContent("Points earned") {
                        TextField("Optional", text: $gradeText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .grade)
                    }

                    LabeledContent("Points possible") {
                        TextField("100", text: $outOfText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .points)
                    }
                } header: {
                    Text("Score")
                } footer: {
                    Text(statusDescription)
                        .contentTransition(.opacity)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let pointsPossible = parsedPointsPossible else { return }
                        let formatter = DateFormatter()
                        formatter.dateFormat = "M/d/yy"
                        onAdd(WhatIfAssignment(
                            className: "",
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            term: assignmentTerm.shortName,
                            category: category,
                            grade: parsedGrade,
                            outOf: pointsPossible,
                            dueDate: formatter.string(from: Date()),
                            status: status
                        ))
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
            .onAppear {
                if category.isEmpty { category = availableCategories.first ?? "Assignments" }
            }
            .onChange(of: assignmentTerm) {
                if !availableCategories.contains(category) {
                    category = availableCategories.first ?? "Assignments"
                }
            }
        }
    }

    private var availableCategories: [String] {
        let unique = Array(Set(
            (categoriesByTerm[assignmentTerm.shortName] ?? []).filter { !$0.isEmpty }
        )).sorted()
        return unique.isEmpty ? ["Assignments"] : unique
    }

    private var parsedGrade: Double? {
        let value = gradeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              let parsed = Double(value), parsed.isFinite, abs(parsed) <= 1_000_000 else {
            return nil
        }
        return parsed
    }

    private var parsedPointsPossible: Double? {
        let value = outOfText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(value), parsed.isFinite,
              parsed > 0, parsed <= 1_000_000 else {
            return nil
        }
        return parsed
    }

    private var canAdd: Bool {
        let gradeIsEmpty = gradeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !category.isEmpty
            && (gradeIsEmpty || parsedGrade != nil)
            && parsedPointsPossible != nil
    }

    private var statusDescription: String {
        switch status {
        case .counted:
            return "Leave points earned empty for an ungraded assignment."
        case .noCount:
            return "Visible in the list, but excluded from the calculated grade."
        case .missing:
            return "Flags this assignment as missing."
        case .absent:
            return "Flags this assignment as absent."
        }
    }
}

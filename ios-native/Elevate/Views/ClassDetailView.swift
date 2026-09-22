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

                .fixedSize(horizontal: false, vertical: true)

            if let instructor = course.instructor, !instructor.isEmpty {
                Text(ClassNameFormatter.format(instructor.replacingOccurrences(of: " ", with: "_")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var displayGradeLabel: some View {
        if let displayGrade {
            (Text(displayGrade, format: .number.precision(.fractionLength(1))) + Text("%"))
                .font(.title2.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(value: displayGrade))
        }
    }

    private var categoriesSection: some View {
        let categories = gradeInfo?.gradebook.filter { $0.category != "Final Exam" } ?? []
        return Group {
            if !categories.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        if reduceMotion {
                            showsBreakdown.toggle()
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                showsBreakdown.toggle()
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text("Grade breakdown")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showsBreakdown ? 180 : 0))
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showsBreakdown ? "Expanded" : "Collapsed")

                    if showsBreakdown {
                        Rectangle()
                            .fill(Color(uiColor: .separator).opacity(0.32))
                            .frame(height: 0.5)

                        ForEach(Array(categories.enumerated()), id: \.element.category) { index, category in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color(uiColor: .separator).opacity(0.32))
                                    .frame(height: 0.5)
                            }
                            categoryRow(category)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: GradeCategory) -> some View {
        let result = summary.categories[category.category]
        let baseWeight = category.weight ?? 0
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                Text(category.category)
                    .font(.subheadline.weight(.medium))
                Text(categoryAverage(result))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(categoryWeight(result: result, baseWeight: baseWeight))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else {
            HStack(alignment: .center, spacing: 12) {
                Text(category.category)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(categoryAverage(result))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(categoryWeight(result: result, baseWeight: baseWeight))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 46)
        }
    }

    private func categoryAverage(_ result: GradeSummary.CategoryResult?) -> String {
        result.map { String(format: "%.1f%%", $0.average) } ?? "Ungraded"
    }

    private func categoryWeight(result: GradeSummary.CategoryResult?, baseWeight: Double) -> String {
        guard let result else { return String(format: "%.0f%% weight, inactive", baseWeight) }
        if abs(result.weight - baseWeight) >= 0.05 {
            return String(format: "%.0f%% weight, %.1f%% active", baseWeight, result.weight)
        }
        return String(format: "%.0f%% weight", baseWeight)
    }

    private var finalExamSection: some View {
        let examName = store.selectedTerm == .sm1 ? "Exam 1" : "Exam 2"
        let realAssignment = apiAssignments.first { $0.category == "Final Exam" }
        let dueDate = realAssignment?.dueDate ?? ""
        let estimate = finalExamGrades[examType]
        let realGrade = effectiveFinalExamGrade
        let shown: Double? = (isWhatIfActive && estimate != nil) ? estimate : realGrade

        return AssignmentRow(
            assignment: CalcAssignment(
                id: "final-exam-\(examType)", className: course.courseName, name: examName,
                term: examType, category: "Final Exam", grade: shown, outOf: 100,
                dueDate: dueDate, artificial: isWhatIfActive && estimate != nil, meta: []
            ),
            editable: isWhatIfActive,
            onEditGrade: { newGrade in
                WhatIfStore.setFinalExamGrade(newGrade, examType: examType, classKey: classKey)
                reloadWhatIf()
            },
            onDelete: nil
        )
        .padding(.horizontal, 20)
    }

    private var assignmentsSection: some View {
        let assignments = displayedAssignments
        let hasUnfilteredAssignments = meshedAssignments.contains { $0.category != "Final Exam" }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Assignments")
                    .font(.title3.weight(.semibold))
                Spacer()
                if hasUnfilteredAssignments || hasActiveAssignmentControls {
                    filterMenu
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)

            if assignments.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No assignments found",
                    subtitle: categoryFilter.isEmpty
                        && assignmentFilter.isEmpty
                        && gradeFilter.isEmpty
                        ? "No assignments available for this term"
                        : "Try adjusting your filters to see more results"
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(assignments) { assignment in
                        AssignmentRow(
                            assignment: assignment,
                            editable: isWhatIfActive && assignment.artificial,
                            onEditGrade: assignment.artificial ? { newGrade in
                                if var match = whatIfAssignments.first(where: { $0.id == assignment.id }) {
                                    match.grade = newGrade
                                    WhatIfStore.update(match, classKey: classKey)
                                    reloadWhatIf()
                                }
                            } : nil,
                            onChangeStatus: assignment.artificial ? { status in
                                if var match = whatIfAssignments.first(where: { $0.id == assignment.id }) {
                                    match.resolvedStatus = status
                                    WhatIfStore.update(match, classKey: classKey)
                                    reloadWhatIf()
                                }
                            } : nil,
                            onDelete: assignment.artificial ? {
                                WhatIfStore.remove(id: assignment.id, classKey: classKey, term: store.selectedTerm)
                                reloadWhatIf()
                            } : nil
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

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
                    sortOption = .date
                    sortAscending = false
                    categoryFilter.removeAll()
                    assignmentFilter.removeAll()
                    gradeFilter.removeAll()
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.medium))
                .foregroundStyle(hasActiveAssignmentControls ? Color.themeAccent : Color.primary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .overlay(alignment: .topTrailing) {
                    if hasActiveAssignmentControls {
                        Circle()
                            .fill(Color.themeAccent)
                            .frame(width: 7, height: 7)
                    }
                }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Sort and filter assignments")
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

// MARK: - Assignment row

struct AssignmentRow: View {
    var assignment: CalcAssignment
    var editable: Bool
    var onEditGrade: ((Double?) -> Void)?
    var onChangeStatus: ((WhatIfAssignmentStatus) -> Void)? = nil
    var onDelete: (() -> Void)?

    @State private var editingGradeText = ""
    @State private var showingDeleteConfirmation = false
    @FocusState private var gradeFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesStackedLayout: Bool { dynamicTypeSize >= .xxxLarge }

    private var badge: (label: String, color: Color)? {
        if assignment.isMissing { return ("MISSING", .red) }
        if assignment.isNoCount { return ("NO COUNT", .gray) }
        if assignment.isAbsent { return ("ABSENT", .orange) }
        if assignment.artificial { return ("WHAT-IF · \(assignment.term)", Color.themeAccent) }
        return nil
    }

    var body: some View {
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: 10) {
                    assignmentDetails
                    HStack {
                        Spacer(minLength: 0)
                        trailingControls
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    assignmentDetails
                    Spacer(minLength: 8)
                    trailingControls
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.32))
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onAppear {
            editingGradeText = assignment.grade.map { trimNumber($0) } ?? ""
        }
        .onChange(of: assignment.grade) { _, grade in
            guard !gradeFieldFocused else { return }
            editingGradeText = grade.map { trimNumber($0) } ?? ""
        }
        .onChange(of: gradeFieldFocused) { _, focused in
            if !focused { commitGrade() }
        }
        .onDisappear {
            if gradeFieldFocused { commitGrade() }
        }
        .contextMenu {
            if onDelete != nil {
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .alert("Delete what-if assignment?", isPresented: $showingDeleteConfirmation) {
            Button("Delete assignment", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: editable ? .contain : .combine)
        .accessibilityLabel(assignment.name)
        .accessibilityValue(assignmentAccessibilityValue)
    }

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 2) {
            gradeControl
            if assignment.artificial, onChangeStatus != nil {
                statusMenu
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var gradeControl: some View {
        if editable, onEditGrade != nil {
            HStack(spacing: 5) {
                TextField("--", text: $editingGradeText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($gradeFieldFocused)
                    .frame(width: 52, height: 34)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .frame(minHeight: 44)
                    .accessibilityLabel("Points earned")

                Text("/")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(outOfText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 5) {
                Text(gradeText)
                    .foregroundStyle(assignment.grade == nil ? .secondary : .primary)
                Text("/")
                    .foregroundStyle(.tertiary)
                Text(outOfText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .lineLimit(1)
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(WhatIfAssignmentStatus.allCases) { status in
                Button {
                    onChangeStatus?(status)
                } label: {
                    if currentStatus == status {
                        Label(status.rawValue, systemImage: "checkmark")
                    } else {
                        Label(status.rawValue, systemImage: status.systemImage)
                    }
                }
            }
            if onDelete != nil {
                Divider()
                Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                    Label("Delete Assignment", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Assignment options")
        .accessibilityValue(currentStatus.rawValue)
    }

    private var currentStatus: WhatIfAssignmentStatus {
        if assignment.isMissing { return .missing }
        if assignment.isAbsent { return .absent }
        if assignment.isNoCount { return .noCount }
        return .counted
    }

    private func commitGrade() {
        let trimmed = editingGradeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onEditGrade?(nil)
        } else if let grade = validNumber(trimmed) {
            onEditGrade?(grade)
        } else {
            editingGradeText = assignment.grade.map { trimNumber($0) } ?? ""
        }
    }

    private var assignmentDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(assignment.name)
                .font(.body.weight(.semibold))
                .strikethrough(assignment.isNoCount)
                .foregroundStyle(assignment.isNoCount ? .secondary : .primary)
                .lineLimit(usesStackedLayout ? nil : 1)
                .layoutPriority(1)

            Group {
                if usesStackedLayout {
                    VStack(alignment: .leading, spacing: 3) {
                        badgeView
                        Text(assignment.category)
                        if !assignment.dueDate.isEmpty {
                            Text("Due \(assignment.dueDate)")
                        }
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            badgeView
                            Text(assignment.category)
                            if !assignment.dueDate.isEmpty {
                                Text("Due \(assignment.dueDate)")
                            }
                        }

                        HStack(spacing: 8) {
                            badgeView
                            if !assignment.dueDate.isEmpty {
                                Text(assignment.dueDate)
                            } else {
                                Text(assignment.category)
                            }
                        }

                        badgeView
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Text(badge.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badge.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var gradeText: String {
        guard let grade = assignment.grade, grade.isFinite else { return "--" }
        return grade >= 100 ? String(format: "%.0f", grade) : String(format: "%.1f", grade)
    }

    private var outOfText: String { trimNumber(assignment.outOf) }

    private var assignmentAccessibilityValue: String {
        var values = [assignment.category]
        if assignment.grade?.isFinite == true {
            values.append("\(gradeText) out of \(outOfText)")
        } else {
            values.append("No grade, \(outOfText) points possible")
        }
        if let badge {
            values.append(badge.label.capitalized)
        }
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

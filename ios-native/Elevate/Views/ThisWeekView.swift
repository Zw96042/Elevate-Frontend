import SwiftUI
import UIKit

/// Today and the next six days for Calendar's quarter: Skyward's dated
/// assignments, every assignment Skyward marks Missing in that quarter, the
/// account's reminders by the day they fire, and undated work. Days and
/// times are America/Chicago school days, as `SchoolWeek` builds them.
/// Done is a personal mark only; it never changes Skyward's statuses or
/// reminders. Checked-off work moves from every group into Done at the end.
struct ThisWeekView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Recomputed on activation and at each new school day.
    @State private var now = Date()
    /// The account this page opened for. Marks and reminders are written
    /// only while it is still the current account.
    @State private var openedScope: String?
    @State private var didCaptureScope = false
    @State private var reminder: ReminderRequest?
    @State private var showsUndated = false
    @State private var showsDoneList = false
    /// The first check-off on this page opens Done, so the student sees
    /// where the assignment went; later ones respect their choice.
    @State private var didRevealDoneList = false
    @State private var confirmingClearMarks = false
    @State private var doneError: String?
    @State private var doneRevision = 0

    /// Changes whenever loading should start over or stop: another account,
    /// sign-in state, quarter, this tab leaving view, or the app backgrounding.
    private struct LoadIdentity: Hashable {
        var accountRevision: Int
        var coursesRevision: Int
        var canShowData: Bool
        var term: TermLabel
        var isSelected: Bool
        var isActive: Bool
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(
            accountRevision: store.accountRevision,
            coursesRevision: store.coursesRefreshRevision,
            canShowData: store.canShowData,
            term: store.calendarTerm,
            isSelected: router.selectedTab == .calendar,
            isActive: scenePhase == .active
        )
    }

    var body: some View {
        let plan = SchoolWeekPlan(data: loadedData, reminders: weekReminders, completedIDs: activeDoneIDs,
                                  now: now) { Self.isLinked($0, to: $1) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if currentScope == nil {
                    EmptyStateView(
                        title: "This week isn't available",
                        message: "Connect your Skyward account to see assignments and reminders."
                    )
                    .padding(.horizontal, Metrics.page)
                    .accessibilityIdentifier("week.unavailable")
                } else {
                    statusStrip
                        .padding(.horizontal, Metrics.page)
                    scopeLines(plan.week)
                        .padding(.horizontal, Metrics.page)
                    content(plan)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 32)
        }
        .softScrollEdges()
        .visibleRefreshable { await store.refreshCalendar(force: true) }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("This Week")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("week.screen")
        .onAppear {
            if !didCaptureScope {
                openedScope = store.localAccountScope
                didCaptureScope = true
            }
            now = Date()
        }
        // Calendar's root pauses its own loading while this page is pushed,
        // so this is the page's only refresh owner.
        .task(id: loadIdentity) {
            let identity = loadIdentity
            guard identity.isSelected, identity.isActive, identity.canShowData else { return }
            await store.refreshCalendar()
        }
        .task(id: plan.week.firstDay) { await advanceAtNextSchoolDay() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = Date() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        .sheet(item: $reminder) { request in ReminderSheet(request: request) }
        .alert("Clear Done marks?", isPresented: $confirmingClearMarks) {
            Button("Clear", role: .destructive, action: clearDoneMarks)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved Done marks for this account will be removed. Skyward isn't changed.")
        }
        .sensoryFeedback(.success, trigger: doneRevision)
        .onChange(of: store.accountRevision) { _, _ in
            reminder = nil
            confirmingClearMarks = false
            showsUndated = false
            showsDoneList = false
            didRevealDoneList = false
            doneError = nil
        }
    }

    /// Sleeps until the next America/Chicago day, then moves the week.
    private func advanceAtNextSchoolDay() async {
        let calendar = ThisWeekScope.calendar
        guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return }
        do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow + 1))) } catch { return }
        now = Date()
    }

    // MARK: - Scope

    /// The current account, while it is the one this page opened for.
    private var currentScope: String? {
        guard store.canShowData, let scope = store.localAccountScope else { return nil }
        if didCaptureScope, openedScope != scope { return nil }
        return scope
    }

    /// Writes need the opened account to still be current everywhere.
    private var writableScope: String? {
        guard didCaptureScope, let scope = openedScope, store.localAccountScope == scope,
              store.planning.accountScope == scope else { return nil }
        return scope
    }

    private var showsDone: Bool {
        guard let scope = currentScope else { return false }
        return store.planning.accountScope == scope && !store.planning.completionUnavailable
    }

    /// Marks move work only while they belong to this account and can be
    /// changed; otherwise every assignment stays in its active group.
    private var activeDoneIDs: Set<String> {
        showsDone ? store.planning.completedIDs : []
    }

    private var canRemind: Bool {
        guard let scope = currentScope else { return false }
        return store.notifications.accountScope == scope
    }

    private var weekReminders: [LocalReminder] {
        currentScope == nil ? [] : ThisWeekScope.reminders(store)
    }

    // MARK: - Sources

    private enum SourceState: Equatable {
        case loading
        case failed(String)
        case loaded
    }

    /// Saved assignments for Calendar's quarter only.
    private var calendarData: SchoolCalendarData? {
        guard currentScope != nil, let data = store.calendarData, data.term == store.calendarTerm else { return nil }
        return data
    }

    /// Data in which no class resolved shows nothing, so it is a failure
    /// rather than an empty week.
    private var assignmentState: SourceState {
        guard let data = calendarData,
              data.resolvedCourseCount > 0 || data.failedCourseNames.isEmpty else {
            if let error = store.calendarError, !store.calendarLoading { return .failed(error) }
            return .loading
        }
        return .loaded
    }

    private var loadedData: SchoolCalendarData? {
        assignmentState == .loaded ? calendarData : nil
    }

    private var eligible: [UnifiedCourseData] {
        SchoolCalendar.eligibleCourses(store.courses ?? [], term: store.calendarTerm)
    }

    // MARK: - Status and scope

    private var statusStrip: some View {
        StatusStrip(
            lastUpdated: assignmentState == .loaded ? store.calendarLastUpdated : nil,
            isRefreshing: store.calendarLoading && assignmentState == .loaded,
            error: assignmentState == .loaded ? store.calendarError : nil
        ) {
            await store.refreshCalendar(force: true)
        } control: {
            ScopePicker(
                title: "Assignment quarter",
                valueName: store.calendarTerm.displayName,
                hint: "Selects the quarter whose assignments are listed",
                identifier: "week.quarter",
                groups: [
                    ChoiceGroup(title: "Fall semester", options: [TermLabel.q1, .q2].map(quarterOption)),
                    ChoiceGroup(title: "Spring semester", options: [TermLabel.q3, .q4].map(quarterOption)),
                ],
                selection: Binding(get: { store.calendarTerm }, set: { chooseQuarter($0) })
            )
        }
    }


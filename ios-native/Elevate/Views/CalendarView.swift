import SwiftUI
import UIKit

/// The school year as scrolling months, as in Calendar. Each day's number
/// is shaded by how much Skyward work is due; a dot marks an attendance
/// record; events from the person's own calendars run beneath the numbers.
/// Pinching shows more or less of those events. Tapping a day opens it.
/// A quarter's assignments are requested only once its days are on screen.
/// Attendance marks a recorded exception only: a day without one is never
/// called present, and an absence never makes an assignment missing. Only
/// Skyward's own descriptions, titles, categories and statuses are shown.
struct CalendarView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CalendarDensity.storageKey) private var densityValue = CalendarDensity.bars.rawValue
    @State private var showingConnect = false
    @State private var today = CalendarDay.today()
    /// The grid's rows, zoom and scroll position. Only the month list
    /// reads the zoom, so a pinch never re-renders the rest of the page.
    @State private var grid = CalendarGridModel(
        level: CalendarDensity(rawValue: UserDefaults.standard.object(forKey: CalendarDensity.storageKey) as? Int
                               ?? CalendarDensity.bars.rawValue) ?? .bars
    )
    /// The list scrolls to this month once; Back and tab switches keep
    /// the person's place.
    @State private var didPositionList = false
    /// The day an open day view shows, so its data keeps loading.
    @State private var focusDay: CalendarDay?
    @State private var snapshot = CalendarSnapshot.empty
    @State private var scrollRequest: CalendarMonth?
    @State private var reminder: ReminderRequest?
    @State private var personal = PersonalCalendarStore.shared
    @State private var showingCalendars = false
    @State private var eventDetail: PersonalEventDetails?
    @State private var showingUndated = false
    @State private var showingMissing = false
    @State private var doneRevision = 0
    @State private var doneError: String?

    private var calendar: Calendar { CalendarAgenda.calendar }

    /// The saved level, so the page itself doesn't follow a pinch frame by frame.
    private var density: CalendarDensity { CalendarDensity(rawValue: densityValue) ?? .bars }

    // MARK: - Loading

    /// Changes whenever loading should start over or stop: another account,
    /// sign-in state, this tab leaving view, the app backgrounding, or a
    /// page other than a day view pushed over the month.
    private struct LoadIdentity: Hashable {
        var accountRevision: Int
        var coursesRevision: Int
        var canShowData: Bool
        var isSelected: Bool
        var isActive: Bool
        var isOnCalendar: Bool

        var isLive: Bool { isSelected && isActive && canShowData && isOnCalendar }
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(
            accountRevision: store.accountRevision,
            coursesRevision: store.coursesRefreshRevision,
            canShowData: store.canShowData,
            isSelected: router.selectedTab == .calendar,
            // Not background, rather than active: pulling down Notification
            // Center or a Face ID prompt shouldn't restart loading or drop
            // events, which would shift the page twice.
            isActive: scenePhase != .background,
            isOnCalendar: router.calendarPath.allSatisfy {
                if case .day = $0 { return true } else { return false }
            }
        )
    }

    private struct PersonalLoad: Hashable {
        var base: LoadIdentity
        var months: [CalendarMonth]
    }

    /// Every month in the grid. Calendar loads all of it when it opens, so
    /// nothing arrives or shifts while scrolling.
    private var gridMonths: [CalendarMonth] {
        guard let first = grid.items.first?.month, let last = grid.items.last?.month else { return [] }
        return CalendarMonth.months(in: first...last)
    }

    /// What the grid summary depends on. Cheap to compare; the summary is
    /// rebuilt only when this changes, never per scroll or frame.
    private struct SnapshotKey: Hashable {
        var calendarData: Int
        var attendanceCount: Int
        var attendanceUpdated: Date?
        var eventsRevision: Int
        var shownCalendars: [String]
        var calendarColors: [String: PersonalCalendarColor]
        var accountRevision: Int
        var today: CalendarDay
    }

    private var snapshotKey: SnapshotKey {
        SnapshotKey(
            calendarData: store.calendarDataRevision,
            attendanceCount: attendanceState == .loaded ? store.attendance?.records.count ?? 0 : -1,
            attendanceUpdated: store.attendanceLastUpdated,
            eventsRevision: personal.eventsRevision,
            shownCalendars: personal.shownCalendars.map(\.id),
            calendarColors: calendarColors,
            accountRevision: store.accountRevision,
            today: today
        )
    }

    private func rebuildSnapshot() {
        let assignments = SchoolCalendar.quarters.flatMap { store.calendarQuarter($0).loadedData?.assignments ?? [] }
        let records = attendanceState == .loaded ? store.attendance?.records ?? [] : []
        let index = CalendarDayIndex(attendance: records, assignments: assignments)
        let range = CalendarMonth.browseRange(today: today, entryMonths: index.months)
        // Only shown calendars, even before a re-read finishes after one is
        // turned off.
        let shown = Set(personal.shownCalendars.map(\.id))
        let events: [String: [PersonalEvent]] = shown.isEmpty ? [:] : personal.eventsByDay.compactMapValues { list in
            let kept = list.filter { shown.contains($0.calendarID) }
            return kept.isEmpty ? nil : kept
        }
        snapshot = CalendarSnapshot(
            assignments: assignments, attendance: records, eventsByDay: events,
            weeks: CalendarWeek.weeks(in: range, calendar: calendar)
        )
        let items = CalendarGridItem.items(for: CalendarMonth.months(in: range), calendar: calendar)
        let weeks = CalendarMonthWeek.inputs(for: items, snapshot: snapshot, today: today,
                                             showsEvents: !shown.isEmpty, calendars: calendarColors)
        grid.update(items: items, weeks: weeks)
    }

    private var calendarColors: [String: PersonalCalendarColor] {
        Dictionary(personal.calendars.map { ($0.id, $0.color) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.calendarPath) {
            Group {
                if !store.canShowData {
                    LoginPromptView(message: "Connect your Skyward account to see attendance records and assignment due dates from your school.") {
                        showingConnect = true
                    }
                } else {
                    calendarPage
                }
            }
            .screenTitle("Calendar") { router.isShowingSettings = true }
            .background(Color.appBackground.ignoresSafeArea())
            .accessibilityIdentifier("calendar.screen")
            .navigationDestination(for: CalendarRoute.self) { route in
                // The root hides the bar for its own header; pushed screens
                // keep their centered inline titles and Back.
                Group {
                    switch route {
                    case .thisWeek:
                        ThisWeekView()
                    case .day(let iso):
                        CalendarDayView(context: context, day: CalendarDay(iso: iso) ?? today, focusDay: $focusDay)
                    }
                }
                .toolbar(.visible, for: .navigationBar)
            }
        }
        // On the stack, so they present over a pushed day view too.
        .sheet(isPresented: $showingConnect) { SkywardConnectSheet() }
        .sheet(item: $reminder) { request in ReminderSheet(request: request) }
        .sheet(isPresented: $showingCalendars) { PersonalCalendarsSheet(store: personal) }
        .sheet(item: $eventDetail) { details in
            PersonalEventDetailSheet(details: details, calendar: personal.calendar(id: details.event.calendarID))
        }
        .sheet(isPresented: $showingUndated) { undatedSheet }
        .sheet(isPresented: $showingMissing) { missingSheet }
        .task(id: loadIdentity) {
            // Attendance keeps its own due-refresh loop. A new identity
            // cancels it.
            guard loadIdentity.isLive else { return }
            await store.runAttendanceRefreshLoop()
        }
        .task(id: loadIdentity) {
            // Every quarter, one after another, as soon as Calendar opens;
            // saved quarters refresh only when due.
            guard loadIdentity.isLive else { return }
            await store.refreshCalendar(terms: SchoolCalendar.quarters)
        }
        .task(id: PersonalLoad(base: loadIdentity, months: gridMonths)) {
            let months = gridMonths
            guard loadIdentity.isLive, !months.isEmpty else {
                personal.deactivate(keepingEvents: loadIdentity.canShowData && loadIdentity.isActive)
                return
            }
            personal.refreshAccess()
            await personal.load(months: months, today: today.calendarMonth)
        }
        .onChange(of: snapshotKey, initial: true) { _, _ in rebuildSnapshot() }
        .onChange(of: personal.changeCount) { _, _ in
            // An open event follows edits made in Calendar, and closes
            // once the event is deleted.
            if let open = eventDetail { eventDetail = personal.details(for: open.event) }
        }
        .onChange(of: personal.needsCalendarChoice, initial: true) { _, needed in
            // Every calendar starts hidden: right after access is granted,
            // the person picks the ones to show.
            guard needed else { return }
            personal.calendarChoiceShown()
            showingCalendars = true
        }
        .onChange(of: store.accountRevision) { _, _ in
            reminder = nil
            eventDetail = nil
            showingCalendars = false
            showingUndated = false
            showingMissing = false
            doneError = nil
            focusDay = nil
            today = CalendarDay.today()
            // Repositions now if the page is showing, or when it next appears.
            didPositionList = false
            scrollRequest = today.calendarMonth
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = CalendarDay.today()
        }
        .sensoryFeedback(.success, trigger: doneRevision)
        .sensoryFeedback(.selection, trigger: densityValue)
    }

    // MARK: - Shared context

    private var context: CalendarContext {
        CalendarContext(
            store: store,
            personal: personal,
            snapshot: snapshot,
            today: today,
            ambiguousIDs: snapshot.ambiguousIDs,
            onOpen: { open($0) },
            onRemind: { remind($0) },
            onOpenEvent: { eventDetail = personal.details(for: $0) },
            onToggleDone: { toggleDone($0) }
        )
    }

    // MARK: - Sources

    private enum SourceState: Equatable {
        case loading
        case failed(String)
        case unavailable
        case loaded
    }

    /// Nothing saved and no failure yet counts as loading, including before
    /// the first request starts.
    private var attendanceState: SourceState {
        guard let attendance = store.attendance else {
            if let error = store.attendanceError, !store.attendanceLoading { return .failed(error) }
            return .loading
        }
        return attendance.availability == .unavailable ? .unavailable : .loaded
    }

    private func refreshAll(force: Bool) async {
        let store = store
        let terms = SchoolCalendar.quarters
        async let attendance: Void = store.refreshAttendance(force: force)
        async let assignments: Void = store.refreshCalendar(terms: terms, force: force)
        _ = await (attendance, assignments)
    }

    // MARK: - Page

    private var calendarPage: some View {
        let context = context
        return ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                toolbarRow(proxy: proxy)
                    .padding(.horizontal, Metrics.page)
                statusArea(context: context)
                    .padding(.horizontal, Metrics.page)
                weekdayInitials
                CalendarMonthList(grid: grid, today: today, reduceMotion: reduceMotion,
                                  onSelect: { router.calendarPath.append(.day($0.iso)) },
                                  onSettle: { densityValue = $0.rawValue },
                                  onRefresh: { await refreshAll(force: true) })
            }
            .onAppear {
                grid.proxy = proxy
                // First appearance, or the first after an account change
                // (which may have happened while this page was hidden).
                guard !didPositionList || scrollRequest != nil else { return }
                let month = scrollRequest ?? today.calendarMonth
                didPositionList = true
                scrollRequest = nil
                grid.position(at: month.id)
            }
            .onChange(of: scrollRequest) { _, month in
                guard let month else { return }
                scroll(proxy, to: month, animated: true)
                scrollRequest = nil
            }

        }
        // A container of its own, so the screen's identifier stays on it
        // rather than replacing every control's.
        .accessibilityElement(children: .contain)
    }

    /// Every row has an exact height, so one scroll lands where it should.
    private func scroll(_ proxy: ScrollViewProxy, to month: CalendarMonth, animated: Bool) {
        grid.scroll(to: month.id, animation: animated ? Motion.replace(reduceMotion) : nil)
    }

    private func toolbarRow(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            Button("Today") { scroll(proxy, to: today.calendarMonth, animated: true) }
                .buttonStyle(QuietButtonStyle())
                .accessibilityHint("Scrolls to this month")
                .accessibilityIdentifier("calendar.today")
            Spacer(minLength: 8)
            densityButton
            PersonalCalendarsButton(store: personal) { showingCalendars = true }
        }
    }

    /// The pinch, as a control: VoiceOver and anyone who doesn't pinch can
    /// step through the same levels.
    private var densityButton: some View {
        Menu {
            Picker("Detail", selection: Binding(get: { density }, set: { setDensity($0) })) {
                Label("Compact", systemImage: "rectangle.compress.vertical").tag(CalendarDensity.compact)
                Label("Bars", systemImage: "line.3.horizontal").tag(CalendarDensity.bars)
                Label("Titles", systemImage: "list.bullet.rectangle").tag(CalendarDensity.titles)
                Label("Details", systemImage: "rectangle.expand.vertical").tag(CalendarDensity.details)
            }
        } label: {
            Image(systemName: "arrow.up.and.down.text.horizontal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(minWidth: 20)
        }
        .menuStyle(.button)
        .buttonStyle(QuietButtonStyle())
        .accessibilityLabel("Detail")
        .accessibilityValue(density.spokenName)
        .accessibilityHint("Pinch the months to change this too")
        .accessibilityIdentifier("calendar.density")
    }

    /// A level from the menu: the zoom animates there through every frame
    /// in between, with the week at the top of the screen held in place.
    private func setDensity(_ new: CalendarDensity) {
        guard Double(new.rawValue) != grid.zoom else { return }
        grid.anchorTop()
        grid.settle(on: new, animated: !reduceMotion)
        densityValue = new.rawValue
    }

    private var weekdayInitials: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(CalendarAgenda.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
            }
            .padding(.horizontal, Metrics.page)
            Rule()
        }
        .accessibilityHidden(true)
    }

    // MARK: - Done marks

    /// Duplicate source rows never take a mark, graded work is done by
    /// itself, and a page left open from another account never writes.
    private func toggleDone(_ assignment: CalendarAssignment) {
        guard context.canToggleDone(assignment) else { return }
        let done = !store.planning.completedIDs.contains(assignment.id)
        var saved = false
        Motion.perform(Motion.select(reduceMotion)) {
            saved = store.planning.setCompleted(done, assignmentID: assignment.id,
                                                expectedAccountScope: store.localAccountScope)
        }
        guard saved else {
            doneError = "Couldn't save this Done mark. Try again."
            return
        }
        doneError = nil
        doneRevision += 1
    }

    // MARK: - Status area

    /// The quarters on screen as the page can show them.
    private func onScreenStatuses(_ context: CalendarContext) -> [CalendarQuarterStatus] {
        SchoolCalendar.quarters.map(context.quarterStatus)
    }

    private func loadedQuarters(_ context: CalendarContext) -> [CalendarQuarterStatus] {
        SchoolCalendar.quarters.map(context.quarterStatus).filter { $0.data != nil }
    }

    /// The older of every saved time on screen, so the line never claims
    /// fresher data than is shown. Nil while any shown source lacks one.
    private func shownDataUpdated(_ statuses: [CalendarQuarterStatus]) -> Date? {
        var dates: [Date] = []
        if store.attendance != nil {
            guard let updated = store.attendanceLastUpdated else { return nil }
            dates.append(updated)
        }
        for status in statuses where status.data != nil {
            guard let updated = status.state.lastUpdated else { return nil }
            dates.append(updated)
        }
        return dates.min()
    }

    private func isRefreshingSavedData(_ statuses: [CalendarQuarterStatus]) -> Bool {
        (store.attendanceLoading && store.attendance != nil)
            || statuses.contains { $0.state.isLoading && $0.data != nil }
    }

    /// Failed refreshes by source; the coverage line says what is shown.
    private func refreshError(_ statuses: [CalendarQuarterStatus]) -> String? {
        var reasons: [String] = []
        if let error = store.attendanceError, !store.attendanceLoading {
            reasons.append("Attendance: \(Self.trimmed(error))")
        }
        for status in statuses {
            if let error = status.state.error, !status.state.isLoading {
                reasons.append("\(status.term.displayName): \(Self.trimmed(error))")
            }
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: ". ")
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private struct CoverageLine: Equatable {
        var text: String
        var spokenText: String?
        var isLoading = false
        var offersRetry = false
    }

    /// One line, the highest priority item only. Retry appears here only
    /// when the freshness row above does not already offer it.
    private func coverageLine(_ statuses: [CalendarQuarterStatus]) -> CoverageLine? {
        let freshnessOffersRetry = refreshError(statuses) != nil && !isRefreshingSavedData(statuses)
        func names(_ list: [String]) -> String {
            ListFormatter.localizedString(byJoining: list.map(CourseTitle.display))
        }
        // One or two classes by name; more as a count, so the line keeps
        // what happened instead of truncating it. VoiceOver reads the names.
        func classes(_ list: [String]) -> String {
            list.count <= 2 ? names(list) : "\(list.count) classes"
        }
        if store.courses == nil, let error = store.coursesError, !store.coursesLoading {
            return CoverageLine(text: "Classes didn't load, so assignments can't",
                                spokenText: "Classes didn't load, so assignments can't. \(error)", offersRetry: true)
        }
        if let failed = statuses.first(where: \.isFailed) {
            return CoverageLine(text: "\(failed.term.displayName) assignments didn't load",
                                spokenText: failed.state.failure.map { "\(failed.term.displayName) assignments didn't load. \($0)" },
                                offersRetry: !freshnessOffersRetry)
        }
        if case .failed(let error) = attendanceState {
            return CoverageLine(text: "Attendance didn't load", spokenText: "Attendance didn't load. \(error)",
                                offersRetry: !freshnessOffersRetry)
        }
        if let loading = statuses.first(where: \.isUnknown) {
            return CoverageLine(text: "Loading \(loading.term.displayName)", isLoading: true)
        }
        let missing = statuses.flatMap(\.missing).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if !missing.isEmpty {
            return CoverageLine(text: "\(classes(missing)) didn't load",
                                spokenText: "\(names(missing)) didn't load", offersRetry: !freshnessOffersRetry)
        }
        let saved = statuses.flatMap(\.saved).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if !saved.isEmpty {
            let asOf = statuses.compactMap { $0.saved.isEmpty ? nil : $0.state.lastUpdated }.min()
                .map { " as saved \(UpdatedText.short($0))" } ?? ""
            return CoverageLine(text: "\(classes(saved)) shown\(asOf)",
                                spokenText: "\(names(saved)) shown\(asOf)", offersRetry: !freshnessOffersRetry)
        }
        // A whole-quarter refresh that failed with its earlier data kept.
        if let stale = statuses.first(where: { $0.data != nil && $0.state.error != nil && !$0.state.isLoading }) {
            if let updated = stale.state.lastUpdated {
                return CoverageLine(text: "Showing assignments saved \(Self.savedTime(updated))", offersRetry: !freshnessOffersRetry)
            }
            return CoverageLine(text: "Showing saved assignments", offersRetry: !freshnessOffersRetry)
        }
        // Attendance that couldn't refresh still shows its saved records.
        if store.attendance != nil, store.attendanceError != nil, !store.attendanceLoading {
            if let updated = store.attendanceLastUpdated {
                return CoverageLine(text: "Attendance saved \(Self.savedTime(updated))", offersRetry: !freshnessOffersRetry)
            }
            return CoverageLine(text: "Showing saved attendance", offersRetry: !freshnessOffersRetry)
        }
        if let upcoming = statuses.compactMap({ status in status.upcomingStart.map { (status.term, $0) } }).first {
            return CoverageLine(text: "\(upcoming.0.displayName) begins \(Self.schoolDay(upcoming.1)). Nothing posted yet.")
        }
        if attendanceState == .unavailable {
            return CoverageLine(text: "Attendance isn't available for this account")
        }
        return nil
    }


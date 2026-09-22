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


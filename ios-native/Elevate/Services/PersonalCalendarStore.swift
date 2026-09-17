import EventKit
import Foundation
import Observation

/// The iPhone's own calendars (iCloud, Google, Outlook, subscriptions) for
/// the Calendar page. Events are read from EventKit for the month on screen,
/// kept only in memory, and never sent anywhere. Google appears once its
/// account is added to the iPhone's Calendar; Elevate has no Google sign-in.
@Observable @MainActor
final class PersonalCalendarStore {
    static let shared = PersonalCalendarStore()

    enum Access: Equatable {
        case notDetermined
        case full
        /// Elevate may add events but not read them, so nothing can show.
        case writeOnly
        case denied
        case restricted
    }

    private(set) var access: Access
    private(set) var calendars: [PersonalCalendarInfo] = []
    private(set) var selection: PersonalCalendarSelection
    /// The loaded months' events by yyyy-MM-dd day.
    private(set) var eventsByDay: [String: [PersonalEvent]] = [:] {
        didSet { eventsRevision &+= 1 }
    }
    /// Bumped whenever `eventsByDay` is replaced, so the page rebuilds its
    /// grid summary once per read rather than on every scroll.
    private(set) var eventsRevision = 0
    /// Access was just granted: the page opens the Calendars sheet so the
    /// person picks which calendars to show (every one starts hidden).
    private(set) var needsCalendarChoice = false
    private(set) var isLoading = false
    private(set) var isRequestingAccess = false
    private(set) var error: String?
    /// Counts changes to the iPhone's calendars, so an open event refreshes.
    private(set) var changeCount = 0

    @ObservationIgnored private let reader = EventReader()
    /// The first loaded month and how many whole months follow it.
    @ObservationIgnored private var loadedMonths: (year: Int, month: Int, count: Int)?
    @ObservationIgnored private var generation = 0
    /// Events are read only while Calendar is on screen.
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private let sample: SampleCalendars?
    @ObservationIgnored private var needsSave = false

    /// Events can show only with full access; each calendar is opt-in.
    var showsEvents: Bool { access == .full }

    /// The Calendar page invites the person once, before iOS has asked.
    var showsInvitation: Bool { access == .notDetermined && !selection.dismissedPrompt }

    var shownCalendars: [PersonalCalendarInfo] {
        showsEvents ? calendars.filter { selection.isShown($0) } : []
    }

    func calendar(id: String) -> PersonalCalendarInfo? {
        calendars.first { $0.id == id }
    }

    private init() {
        if let sample = SampleCalendars.fromLaunchArguments() {
            // Synthetic calendars for previews and screenshots; the person's
            // real calendars and saved choices are never touched.
            self.sample = sample
            access = sample.startsUninvited ? .notDetermined : .full
            // Screenshots show the sample calendars turned on, except
            // Birthdays; the invitation flow starts with all of them off,
            // as a real first connection does.
            var choice = PersonalCalendarSelection()
            if !sample.startsUninvited {
                for calendar in sample.calendars where !calendar.isHiddenByDefault {
                    choice.setShown(true, for: calendar)
                }
            }
            selection = choice
        } else {
            sample = nil
            access = Self.currentAccess()
            let (loaded, isNew) = Self.loadSelection()
            selection = loaded
            // Calendars became opt-in (v2). Someone who already allowed access
            // under v1 sees the sheet once to choose, instead of every event
            // silently disappearing.
            if isNew, access == .full { needsCalendarChoice = true }
            needsSave = isNew
            changeObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: reader.store, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.storeChanged() }
            }
        }
        reloadCalendars()
        // Writes the v2 choice once, so the migration prompt shows only once.
        if needsSave { saveSelection() }
    }

    // MARK: - Access

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .full
        case .writeOnly: return .writeOnly
        case .restricted: return .restricted
        case .denied: return .denied
        // `.authorized` is the pre-iOS 17 spelling of full access.
        default: return .full
        }
    }

    /// iOS Settings may have changed access while Elevate was away.
    func refreshAccess() {
        guard sample == nil else { return }
        let current = Self.currentAccess()
        guard current != access else { return }
        access = current
        reloadCalendars()
        reloadMonth()
        changeCount += 1
    }

    func requestAccess() async {
        guard access == .notDetermined, !isRequestingAccess else { return }
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        if sample != nil {
            access = .full
        } else {
            do {
                _ = try await reader.store.requestFullAccessToEvents()
                error = nil
            } catch {
                self.error = "Couldn't ask for calendar access. Try again in a moment."
            }
            access = Self.currentAccess()
        }
        if access == .full { needsCalendarChoice = true }
        reloadCalendars()
        reloadMonth()
    }

    func calendarChoiceShown() {
        needsCalendarChoice = false
    }

    // MARK: - Choices

    func setShown(_ shown: Bool, for calendar: PersonalCalendarInfo) {
        selection.setShown(shown, for: calendar)
        saveSelection()
        reloadMonth()
    }

    func dismissInvitation() {
        selection.dismissedPrompt = true
        saveSelection()
    }

    /// The saved choice, and whether none was saved under v2 yet. A v1
    /// opt-out list isn't carried over, only whether the invitation was
    /// dismissed; the v1 value is removed.
    private static func loadSelection() -> (PersonalCalendarSelection, isNew: Bool) {
        let defaults = UserDefaults.standard
        let legacyKey = "personalCalendars.selection.v1"
        if let data = defaults.data(forKey: PersonalCalendarSelection.storageKey) {
            guard data.count <= 200_000,
                  let value = try? JSONDecoder().decode(PersonalCalendarSelection.self, from: data)
            else { return (PersonalCalendarSelection(), false) }
            return (value, false)
        }
        var fresh = PersonalCalendarSelection()
        if let legacy = defaults.data(forKey: legacyKey), legacy.count <= 200_000,
           let object = try? JSONSerialization.jsonObject(with: legacy) as? [String: Any],
           object["dismissedPrompt"] as? Bool == true {
            fresh.dismissedPrompt = true
        }
        defaults.removeObject(forKey: legacyKey)
        return (fresh, true)
    }

    private func saveSelection() {
        guard sample == nil, let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: PersonalCalendarSelection.storageKey)
    }

    // MARK: - Loading

    private func reloadCalendars() {
        guard access == .full else { calendars = []; return }
        calendars = sample?.calendars ?? reader.calendars()
    }

    private func storeChanged() {
        guard isActive else { return }
        reloadCalendars()
        reloadMonth()
        changeCount += 1
    }

    /// Reads the loaded months again, unless the page leaves or another read
    /// starts before this one runs.
    private func reloadMonth() {
        guard isActive, let months = loadedMonths else { return }
        let expected = generation
        Task {
            guard isActive, generation == expected else { return }
            await fetch(year: months.year, month: months.month, count: months.count)
        }
    }

    /// Calendar left the screen, the app moved to the background, or Skyward
    /// was disconnected: stop reading and drop any read still in flight.
    /// Events stay in memory only for a tab switch or a pushed page
    /// (`keepingEvents`), so coming back doesn't empty and refill the grid;
    /// the next load reads them again either way.
    func deactivate(keepingEvents: Bool = false) {
        isActive = false
        generation += 1
        loadedMonths = nil
        if !keepingEvents { eventsByDay = [:] }
        isLoading = false
    }

    /// Reads the months on screen (the one holding the visible days, and
    /// the next when they straddle a month end) from the shown calendars
    /// while Calendar is on screen. A newer request, a change of access or
    /// choices, or leaving the page meanwhile replaces this one's result.
    func load(year: Int, month: Int, monthCount: Int = 1) async {
        if !isActive {
            // Calendars or an open event may have changed while away.
            isActive = true
            reloadCalendars()
            changeCount += 1
        }
        await fetch(year: year, month: month, count: monthCount)
    }

    /// The months the grid shows, read as one span from the earliest through
    /// the latest. A span longer than the cap keeps the months around today.
    func load(months: [CalendarMonth], today: CalendarMonth) async {
        guard let first = months.min(), let last = months.max() else { return }
        let firstIndex = first.year * 12 + first.month - 1
        let lastIndex = last.year * 12 + last.month - 1
        let todayIndex = today.year * 12 + today.month - 1
        let start = max(firstIndex, min(todayIndex - Self.monthCap / 2, lastIndex - Self.monthCap + 1))
        let count = min(lastIndex - start + 1, Self.monthCap)
        await load(year: start / 12, month: start % 12 + 1, monthCount: count)
    }

    /// The most months read at once.
    static let monthCap = 14

    private func fetch(year: Int, month: Int, count: Int) async {
        // The whole school year Calendar shows, read once while it's open.
        let count = max(1, min(count, Self.monthCap))
        loadedMonths = (year, month, count)
        generation += 1
        let request = generation
        let shownIDs = Set(shownCalendars.map(\.id))
        guard !shownIDs.isEmpty,
              let interval = PersonalEventDays.monthsInterval(year: year, month: month, count: count,
                                                              calendar: PersonalEventDays.dayCalendar)
        else {
            eventsByDay = [:]
            isLoading = false
            return
        }
        isLoading = true
        let events: [PersonalEvent]
        if let sample {
            events = sample.events(in: interval).filter { shownIDs.contains($0.calendarID) }
        } else {
            let reader = reader
            // EventKit's fetch is synchronous; Apple recommends running it
            // off the main thread.
            events = await Task.detached(priority: .userInitiated) {
                reader.events(in: interval, calendarIDs: shownIDs)
            }.value
        }
        guard request == generation, isActive else { return }
        eventsByDay = PersonalEventDays.index(events, calendar: PersonalEventDays.dayCalendar, within: interval)
        isLoading = false
        error = nil
    }

    /// The event as it is now, with its notes and link, for the detail sheet;
    /// nil once it has been deleted. Sample events have no notes.
    func details(for event: PersonalEvent) -> PersonalEventDetails? {
        guard access == .full else { return nil }
        guard sample == nil else { return PersonalEventDetails(event: event) }
        return reader.details(of: event)
    }
}

/// EventKit access off the main actor. `EKEventStore` may be used from any
/// thread; it only returns value copies to the main actor.
private final class EventReader: @unchecked Sendable {
    let store = EKEventStore()

    func calendars() -> [PersonalCalendarInfo] {
        store.calendars(for: .event).map { calendar in
            PersonalCalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                accountTitle: calendar.source?.title ?? "",
                color: Self.color(calendar.cgColor),
                isHiddenByDefault: calendar.type == .birthday
            )
        }
    }

    func events(in interval: DateInterval, calendarIDs: Set<String>) -> [PersonalEvent] {
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate).compactMap(Self.personalEvent)
    }

    private static func personalEvent(_ event: EKEvent) -> PersonalEvent? {
        guard let start = event.startDate, let end = event.endDate,
              let calendar = event.calendar else { return nil }
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PersonalEvent(
            eventIdentifier: identifier, calendarID: calendar.calendarIdentifier,
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            location: location?.isEmpty == false ? location : nil,
            start: start, end: end, isAllDay: event.isAllDay
        )
    }

    /// The exact occurrence, so a repeating event shows the chosen day's
    /// notes. A one-time event edited elsewhere is found by its identifier;
    /// every shown field comes from the fresh copy.
    func details(of event: PersonalEvent) -> PersonalEventDetails? {
        var match: EKEvent?
        if let calendar = store.calendar(withIdentifier: event.calendarID) {
            let predicate = store.predicateForEvents(
                withStart: event.start, end: event.end.addingTimeInterval(1), calendars: [calendar])
            match = store.events(matching: predicate).first {
                ($0.eventIdentifier ?? $0.calendarItemIdentifier) == event.eventIdentifier && $0.startDate == event.start
            }
        }
        if match == nil, let single = store.event(withIdentifier: event.eventIdentifier), !single.hasRecurrenceRules {
            match = single
        }
        guard let match, let fresh = Self.personalEvent(match) else { return nil }
        return PersonalEventDetails(event: fresh, notes: match.notes, url: match.url)
    }

    private static func color(_ color: CGColor?) -> PersonalCalendarColor {
        guard let color,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count >= 3
        else { return PersonalCalendarColor(red: 0.5, green: 0.55, blue: 0.62) }
        return PersonalCalendarColor(red: Double(parts[0]), green: Double(parts[1]), blue: Double(parts[2]))
    }
}

#if DEBUG
/// Synthetic calendars for `-SampleData` runs, around the current month.
/// `-SampleCalendarInvitation` starts before access, to show the invitation;
/// `-SystemCalendars` reads the simulator's real calendars beside sample data.
private struct SampleCalendars {
    var startsUninvited = false

    static func fromLaunchArguments() -> SampleCalendars? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-SampleData"), !arguments.contains("-SystemCalendars") else { return nil }
        return SampleCalendars(startsUninvited: arguments.contains("-SampleCalendarInvitation"))
    }

    let calendars: [PersonalCalendarInfo] = [
        PersonalCalendarInfo(id: "sample.robotics", title: "Robotics", accountTitle: "Gmail",
                             color: .init(red: 0.04, green: 0.50, blue: 0.26)),
        PersonalCalendarInfo(id: "sample.school", title: "Eanes Events", accountTitle: "Gmail",
                             color: .init(red: 0.25, green: 0.32, blue: 0.71)),
        PersonalCalendarInfo(id: "sample.personal", title: "Personal", accountTitle: "iCloud",
                             color: .init(red: 0.56, green: 0.27, blue: 0.68)),
        PersonalCalendarInfo(id: "sample.birthdays", title: "Birthdays", accountTitle: "Other",
                             color: .init(red: 0.55, green: 0.58, blue: 0.62), isHiddenByDefault: true),
    ]

    func events(in interval: DateInterval) -> [PersonalEvent] {
        let calendar = PersonalEventDays.dayCalendar
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        func event(_ id: String, _ calendarID: String, _ title: String, _ location: String?,
                   _ start: Date, _ end: Date, allDay: Bool = false) -> PersonalEvent {
            PersonalEvent(eventIdentifier: id, calendarID: calendarID, title: title, location: location,
                          start: start, end: end, isAllDay: allDay)
        }
        var events = [
            event("s1", "sample.school", "Pep rally", "Main gym", day(0, 14, 45), day(0, 15, 30)),
            event("s2", "sample.personal", "Orthodontist", nil, day(0, 16, 30), day(0, 17, 15)),
            event("s3", "sample.school", "Early release", nil, day(2), day(3), allDay: true),
            event("s4", "sample.robotics", "Regional competition", "Austin Convention Center",
                  day(9, 15), day(11, 12)),
            event("s5", "sample.personal", "SAT", "Westlake High School", day(16, 8), day(16, 12)),
            event("s6", "sample.birthdays", "Sam's birthday", nil, day(5), day(6), allDay: true),
        ]
        // Weekly robotics build on the next four Tuesdays and Thursdays.
        for offset in 0..<28 {
            let weekday = calendar.component(.weekday, from: day(offset))
            guard weekday == 3 || weekday == 5 else { continue }
            events.append(event("build", "sample.robotics", "Robotics build", "Room 214",
                                day(offset, 7, 15), day(offset, 8)))
        }
        return events.filter { $0.end > interval.start && $0.start < interval.end }
    }
}
#else
/// Release builds have no sample calendars.
private struct SampleCalendars {
    var startsUninvited: Bool { false }
    var calendars: [PersonalCalendarInfo] { [] }
    static func fromLaunchArguments() -> SampleCalendars? { nil }
    func events(in interval: DateInterval) -> [PersonalEvent] { [] }
}
#endif

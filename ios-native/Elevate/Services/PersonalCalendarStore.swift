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


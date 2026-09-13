import Foundation

/// A calendar on this iPhone (iCloud, Google, Outlook, a subscription),
/// read through EventKit. Elevate never saves its events, only which
/// calendars the person chose to show.
struct PersonalCalendarInfo: Hashable, Identifiable, Sendable {
    /// EventKit's calendar identifier.
    var id: String
    var title: String
    /// The account's name in iOS Settings, such as "iCloud" or "Gmail".
    var accountTitle: String
    var color: PersonalCalendarColor
    /// The Birthdays calendar, which iOS fills from contacts.
    var isHiddenByDefault = false
}

/// sRGB components, 0...1.
struct PersonalCalendarColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

/// One occurrence of an event. A repeating event has one value per
/// occurrence, each with its own `id`.
struct PersonalEvent: Hashable, Identifiable, Sendable {
    var id: String
    /// EventKit's identifier, shared by every occurrence of a repeating event.
    var eventIdentifier: String
    var calendarID: String
    var title: String
    var location: String?
    var start: Date
    var end: Date
    var isAllDay: Bool

    init(eventIdentifier: String, calendarID: String, title: String, location: String?,
         start: Date, end: Date, isAllDay: Bool) {
        self.id = "\(eventIdentifier)|\(start.timeIntervalSinceReferenceDate)"
        self.eventIdentifier = eventIdentifier
        self.calendarID = calendarID
        self.title = title
        self.location = location
        self.start = start
        self.end = max(start, end)
        self.isAllDay = isAllDay
    }
}

/// What the read-only event sheet shows beyond the row: bounded notes and
/// a web link. Read on demand and never saved.
struct PersonalEventDetails: Identifiable, Sendable {
    static let maximumNotes = 4_000

    var event: PersonalEvent
    var notes: String?
    var url: URL?
    /// Stable while the event is edited elsewhere, so an open sheet updates
    /// in place instead of closing.
    var id: String { event.eventIdentifier }

    init(event: PersonalEvent, notes: String? = nil, url: URL? = nil) {
        self.event = event
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.notes = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maximumNotes))
        // Only web links open from here.
        self.url = url.flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
    }

    /// The Calendar app at the event's start, through its `calshow:` link.
    var calendarAppURL: URL? {
        URL(string: "calshow:\(Int(event.start.timeIntervalSinceReferenceDate))")
    }
}

/// Which calendars to show. Stored on this device, not with a Skyward
/// account, since the calendars belong to the iPhone. Every calendar starts
/// hidden: the person turns on the ones they want, so a family or work
/// calendar never appears beside their schoolwork uninvited.
struct PersonalCalendarSelection: Codable, Equatable, Sendable {
    /// v2: calendars became opt-in; v1 choices (opt-out) are not carried over.
    static let storageKey = "personalCalendars.selection.v2"
    /// Bounds a damaged or hostile stored value.
    static let maximumIDs = 500

    /// Calendars the person turned on.
    var shownIDs: Set<String> = []
    /// The Calendar page's one-time invitation was dismissed.
    var dismissedPrompt = false

    init() {}


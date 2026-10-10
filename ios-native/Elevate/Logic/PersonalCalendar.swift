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

    private enum CodingKeys: String, CodingKey {
        case shownIDs, dismissedPrompt
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        dismissedPrompt = try values.decodeIfPresent(Bool.self, forKey: .dismissedPrompt) ?? false
        let shown = try values.decodeIfPresent([String].self, forKey: .shownIDs) ?? []
        guard shown.count <= Self.maximumIDs else {
            throw DecodingError.dataCorruptedError(forKey: .shownIDs, in: values,
                                                   debugDescription: "Too many calendar identifiers")
        }
        shownIDs = Set(shown)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(dismissedPrompt, forKey: .dismissedPrompt)
        try values.encode(shownIDs.sorted(), forKey: .shownIDs)
    }

    func isShown(_ calendar: PersonalCalendarInfo) -> Bool {
        shownIDs.contains(calendar.id)
    }

    mutating func setShown(_ shown: Bool, for calendar: PersonalCalendarInfo) {
        if shown {
            // A calendar can't be added past the bound; it stays hidden.
            guard shownIDs.count < Self.maximumIDs || shownIDs.contains(calendar.id) else { return }
            shownIDs.insert(calendar.id)
        } else {
            shownIDs.remove(calendar.id)
        }
    }
}

/// Calendars grouped by account for the Calendars sheet.
struct PersonalCalendarGroup: Hashable, Identifiable, Sendable {
    var title: String
    var calendars: [PersonalCalendarInfo]
    var id: String { title }

    /// Accounts by name, each with its calendars by name.
    static func groups(_ calendars: [PersonalCalendarInfo]) -> [PersonalCalendarGroup] {
        let byAccount = Dictionary(grouping: calendars) { calendar -> String in
            let title = calendar.accountTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "Other" : title
        }
        return byAccount
            .map { title, list in
                PersonalCalendarGroup(title: title, calendars: list.sorted {
                    let order = $0.title.localizedStandardCompare($1.title)
                    return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
                })
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// How an event sits on one day of the grid.
enum PersonalEventSpan: Equatable, Sendable {
    /// An all-day event, or a middle day of a longer one.
    case allDay
    /// Starts and ends on this day.
    case timed(start: Date, end: Date)
    /// Starts on this day and ends on a later one.
    case starts(Date)
    /// Started on an earlier day and ends on this one.
    case ends(Date)
}

/// Places events on calendar days (yyyy-MM-dd in the person's own calendar,
/// matching the grid). Pure, so the rules are testable without EventKit.
enum PersonalEventDays {
    /// A runaway event can't mark more than about two months of days.
    static let maximumDays = 62

    /// Gregorian days in the person's time zone, matching the grid's school
    /// dates whatever calendar system the iPhone uses.
    static var dayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = .current
        return calendar
    }

    static func iso(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// An event ending exactly at midnight doesn't reach the next day.
    static func lastInstant(_ event: PersonalEvent) -> Date {
        event.end > event.start ? event.end.addingTimeInterval(-1) : event.start
    }

    /// Every day the event touches, in order, within `interval` when given:
    /// a long event that began months earlier still marks the month on screen.
    static func days(for event: PersonalEvent, calendar: Calendar,
                     within interval: DateInterval? = nil) -> [String] {
        var first = calendar.startOfDay(for: event.start)
        var last = calendar.startOfDay(for: lastInstant(event))
        if let interval {
            first = max(first, calendar.startOfDay(for: interval.start))
            last = min(last, calendar.startOfDay(for: interval.end.addingTimeInterval(-1)))
        }
        var days: [String] = []
        var day = first
        while day <= last, days.count < maximumDays {
            days.append(iso(day, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    static func span(of event: PersonalEvent, on day: String, calendar: Calendar) -> PersonalEventSpan {
        if event.isAllDay { return .allDay }
        let first = iso(event.start, calendar: calendar)
        let last = iso(lastInstant(event), calendar: calendar)
        if first == last { return .timed(start: event.start, end: event.end) }
        if day == first { return .starts(event.start) }
        // Ending at midnight means it runs to the end of its last day.
        if day == last, calendar.startOfDay(for: event.end) != event.end { return .ends(event.end) }
        return .allDay
    }

    /// Events by day: all-day entries first, then by the time each one is
    /// under way on that day, then by title. Only days within `interval`,
    /// when given, are indexed.
    static func index(_ events: [PersonalEvent], calendar: Calendar,
                      within interval: DateInterval? = nil) -> [String: [PersonalEvent]] {
        var result: [String: [PersonalEvent]] = [:]
        for event in events {
            for day in days(for: event, calendar: calendar, within: interval) {
                result[day, default: []].append(event)
            }
        }
        for (day, list) in result {
            result[day] = list.sorted { lhs, rhs in
                let left = sortKey(lhs, day: day, calendar: calendar)
                let right = sortKey(rhs, day: day, calendar: calendar)
                if left.rank != right.rank { return left.rank < right.rank }
                if left.time != right.time { return left.time < right.time }
                let order = lhs.title.localizedStandardCompare(rhs.title)
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
        }
        return result
    }

    private static func sortKey(_ event: PersonalEvent, day: String,
                                calendar: Calendar) -> (rank: Int, time: Date) {
        switch span(of: event, on: day, calendar: calendar) {
        case .allDay: return (0, .distantPast)
        case .timed(let start, _), .starts(let start): return (1, start)
        // Already under way at the start of the day.
        case .ends: return (1, .distantPast)
        }
    }

    /// The month as the range EventKit is asked for: its first day through
    /// the start of the next month.
    static func monthInterval(year: Int, month: Int, calendar: Calendar) -> DateInterval? {
        monthsInterval(year: year, month: month, count: 1, calendar: calendar)
    }

    /// `count` whole months from the first day of the given month through
    /// the start of the month after the last, so the page can read the one
    /// or two months its visible days fall in with a single request.
    static func monthsInterval(year: Int, month: Int, count: Int, calendar: Calendar) -> DateInterval? {
        guard count >= 1,
              let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = calendar.date(byAdding: .month, value: count, to: start), end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}

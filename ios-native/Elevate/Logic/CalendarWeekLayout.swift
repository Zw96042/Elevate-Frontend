import Foundation

/// How much the month grid shows, changed by pinching as in Calendar:
/// a compact strip of color per day, then bars, then titled chips, then
/// chips with times.
enum CalendarDensity: Int, CaseIterable, Comparable, Sendable {
    case compact = 0
    case bars
    case titles
    case details

    static let storageKey = "calendar.density.v1"

    static func < (lhs: CalendarDensity, rhs: CalendarDensity) -> Bool { lhs.rawValue < rhs.rawValue }

    var denser: CalendarDensity? { CalendarDensity(rawValue: rawValue + 1) }
    var sparser: CalendarDensity? { CalendarDensity(rawValue: rawValue - 1) }

    /// Rows of events under a week's numbers before the rest become "+N".
    var laneCount: Int {
        switch self {
        case .compact: return 0
        case .bars, .titles: return 3
        case .details: return 4
        }
    }
}

/// One event's run across a week, in grid columns 0...6.
struct CalendarEventSpan: Hashable, Identifiable, Sendable {
    var event: PersonalEvent
    var startColumn: Int
    var endColumn: Int
    /// The row it sits in under the numbers; spans in one lane never overlap.
    var lane: Int
    /// The event began in an earlier week, or runs on into a later one.
    var continuesBefore: Bool
    var continuesAfter: Bool
    /// More than one day long, wherever it falls.
    var isMultiDay: Bool

    var id: String { event.id }
    var columnCount: Int { endColumn - startColumn + 1 }
}

/// The personal events of one week, placed for the month grid. Pure, so
/// the lane rules are testable without views.
struct CalendarWeekLayout: Equatable, Sendable {
    var spans: [CalendarEventSpan] = []
    /// Each column's events in day order, for the compact strip.
    var dayEvents: [[PersonalEvent]] = Array(repeating: [], count: 7)

    var isEmpty: Bool { spans.isEmpty }

    /// `days` are the week's seven days; events come from a day index that
    /// already lists a multi-day event on every day it touches.
    init(days: [CalendarDay], eventsByDay: [String: [PersonalEvent]]) {
        guard days.count == 7 else { return }
        var columns: [String: (event: PersonalEvent, first: Int, last: Int)] = [:]
        var order: [String] = []
        for (column, day) in days.enumerated() {
            let list = eventsByDay[day.iso] ?? []
            dayEvents[column] = list
            for event in list {
                if let found = columns[event.id] {
                    columns[event.id] = (event, min(found.first, column), max(found.last, column))
                } else {
                    columns[event.id] = (event, column, column)
                    order.append(event.id)
                }
            }
        }
        let calendar = PersonalEventDays.dayCalendar
        let firstISO = days[0].iso
        let lastISO = days[6].iso
        var unplaced: [CalendarEventSpan] = order.compactMap { id in
            guard let entry = columns[id] else { return nil }
            let startISO = PersonalEventDays.iso(entry.event.start, calendar: calendar)
            let endISO = PersonalEventDays.iso(PersonalEventDays.lastInstant(entry.event), calendar: calendar)
            return CalendarEventSpan(event: entry.event, startColumn: entry.first, endColumn: entry.last, lane: 0,
                                     continuesBefore: startISO < firstISO, continuesAfter: endISO > lastISO,
                                     isMultiDay: startISO != endISO)
        }
        // Long and all-day events first, so bars stay on the top lanes and
        // short events fill in beneath them, as Calendar does.
        unplaced.sort { lhs, rhs in
            if lhs.isMultiDay != rhs.isMultiDay { return lhs.isMultiDay }
            if lhs.columnCount != rhs.columnCount { return lhs.columnCount > rhs.columnCount }
            if lhs.startColumn != rhs.startColumn { return lhs.startColumn < rhs.startColumn }
            if lhs.event.isAllDay != rhs.event.isAllDay { return lhs.event.isAllDay }
            if lhs.event.start != rhs.event.start { return lhs.event.start < rhs.event.start }
            return lhs.event.id < rhs.event.id
        }
        var occupied: [[Bool]] = []
        for var span in unplaced {
            var lane = 0
            while lane < occupied.count,
                  (span.startColumn...span.endColumn).contains(where: { occupied[lane][$0] }) {
                lane += 1
            }
            if lane == occupied.count { occupied.append(Array(repeating: false, count: 7)) }
            for column in span.startColumn...span.endColumn { occupied[lane][column] = true }
            span.lane = lane
            spans.append(span)
        }
    }

    func visibleSpans(lanes: Int) -> [CalendarEventSpan] {
        spans.filter { $0.lane < lanes }
    }

    /// Events on a column that don't fit in the shown lanes.
    func hiddenCount(column: Int, lanes: Int) -> Int {
        spans.filter { $0.lane >= lanes && (($0.startColumn)...($0.endColumn)).contains(column) }.count
    }

    /// The highest lane used plus one: how many rows the week needs.
    var laneDepth: Int { (spans.map(\.lane).max() ?? -1) + 1 }
}

import SwiftUI

// The Calendar month grid. Each day's number sits on its busy shade (how
// much Skyward work is due), with a small dot for an attendance record;
// events from the person's own calendars run beneath the numbers. Pinching
// changes how much the events say: a strip of color per day, then bars
// that span the days an event covers, then titled chips, then chips with
// times. The bars, chips and timed chips are the same views at different
// sizes, so a density change morphs rather than swaps.

extension CalendarDensity {
    var spokenName: String {
        switch self {
        case .compact: return "Compact"
        case .bars: return "Bars"
        case .titles: return "Titles"
        case .details: return "Details"
        }
    }
}

/// One day cell's inputs, as plain values so a week row can skip redrawing
/// when nothing it shows changed.
struct CalendarCellInfo: Equatable, Sendable {
    var day: CalendarDay
    var level: Int
    var hasAttendance: Bool
    var isToday: Bool
    var isWeekend: Bool
    /// The day as VoiceOver reads it, with the year when it isn't this one.
    var spokenTitle: String
    var spokenValue: String
}

/// The grid as flat list items, a month header then each of its weeks, so
/// the list can track the exact week at its top and keep it there when
/// the density changes.
struct CalendarGridItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case header
        case week(Int)
    }

    var month: CalendarMonth
    var kind: Kind

    var id: String {
        switch kind {
        case .header: return month.id
        case .week(let row): return "\(month.id)-w\(row)"
        }
    }

    static func items(for months: [CalendarMonth], calendar: Calendar) -> [CalendarGridItem] {
        months.flatMap { month -> [CalendarGridItem] in
            let rows = month.cells(calendar: calendar).count / 7
            return [CalendarGridItem(month: month, kind: .header)]
                + (0..<rows).map { CalendarGridItem(month: month, kind: .week($0)) }
        }
    }
}

/// A month's name above its first week; the current month in the accent.
struct CalendarMonthHeader: View {
    var month: CalendarMonth
    var today: CalendarDay

    private var title: String {
        let calendar = CalendarAgenda.calendar
        if month.year == today.year {
            return month.firstDay.date(calendar: calendar).formatted(.dateTime.month(.wide))
        }
        return month.title(calendar: calendar)
    }

    var body: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(month == today.calendarMonth ? Color.themeAccent : Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("calendar.month.\(month.id)")
    }
}

/// Building the grid's week inputs from a snapshot, once per data change
/// rather than per frame. Days outside a week's month are blank.
enum CalendarMonthWeek {
    /// Every week item's input, by item id.
    static func inputs(
        for items: [CalendarGridItem], snapshot: CalendarSnapshot, today: CalendarDay,
        showsEvents: Bool, calendars: [String: PersonalCalendarColor]
    ) -> [String: CalendarWeekInput] {
        let calendar = CalendarAgenda.calendar
        var cellsByMonth: [CalendarMonth: [CalendarDay?]] = [:]
        var inputs: [String: CalendarWeekInput] = [:]
        for item in items {
            guard case .week(let row) = item.kind else { continue }
            let cells = cellsByMonth[item.month] ?? item.month.cells(calendar: calendar)
            cellsByMonth[item.month] = cells
            let days = Array(cells[(row * 7)..<min(cells.count, row * 7 + 7)])
            inputs[item.id] = CalendarWeekInput(
                cells: days.map { $0.map { info($0, snapshot: snapshot, today: today, showsEvents: showsEvents) } },
                layout: layout(for: days, snapshot: snapshot, showsEvents: showsEvents),
                calendars: calendars
            )
        }
        return inputs
    }

    private static func info(_ day: CalendarDay, snapshot: CalendarSnapshot, today: CalendarDay,
                             showsEvents: Bool) -> CalendarCellInfo {
        let calendar = CalendarAgenda.calendar
        let due = snapshot.assignments(on: day).count
        let events = showsEvents ? snapshot.events(on: day).count : 0
        let records = snapshot.attendance(on: day).count
        var spoken: [String] = []
        if day == today { spoken.append("Today") }
        if due > 0 { spoken.append(due == 1 ? "1 assignment due" : "\(due) assignments due") }
        if events > 0 { spoken.append(events == 1 ? "1 event" : "\(events) events") }
        if records > 0 { spoken.append(records == 1 ? "Attendance record" : "\(records) attendance records") }
        return CalendarCellInfo(
            day: day,
            level: snapshot.level(day),
            hasAttendance: snapshot.hasAttendance(day),
            isToday: day == today,
            isWeekend: calendar.isDateInWeekend(day.date(calendar: calendar)),
            spokenTitle: day.title(today: today, calendar: calendar),
            spokenValue: spoken.joined(separator: ", ")
        )
    }

    /// The week's events, clipped to the days this month shows.
    static func layout(for days: [CalendarDay?], snapshot: CalendarSnapshot, showsEvents: Bool) -> CalendarWeekLayout {
        let calendar = CalendarAgenda.calendar
        guard showsEvents, let anchor = days.compactMap({ $0 }).first else {
            return CalendarWeekLayout(days: [], eventsByDay: [:])
        }
        var layout = snapshot.layout(for: CalendarWeek.containing(anchor, calendar: calendar))
        guard !layout.isEmpty else { return layout }
        let shown = days.indices.filter { days[$0] != nil }
        guard let first = shown.first, let last = shown.last, first > 0 || last < 6 else { return layout }
        layout.spans = layout.spans.compactMap { span in
            guard span.endColumn >= first, span.startColumn <= last else { return nil }
            var clipped = span
            if span.startColumn < first { clipped.startColumn = first; clipped.continuesBefore = true }
            if span.endColumn > last { clipped.endColumn = last; clipped.continuesAfter = true }
            return clipped
        }
        for column in 0..<7 where !shown.contains(column) { layout.dayEvents[column] = [] }
        return layout
    }
}

/// Everything a week row draws except the zoom, as one comparable value,
/// with what a frame would otherwise work out again (hidden counts, event
/// times) computed once.
struct CalendarWeekInput: Equatable, Sendable {
    let cells: [CalendarCellInfo?]
    let layout: CalendarWeekLayout
    let calendars: [String: PersonalCalendarColor]
    /// "+N" per level (by raw value), then per column.
    let hidden: [[Int]]
    /// Every "+N" count any level shows, for drawing once.
    let hiddenCounts: [Int]
    /// Each span's start time, for timed single-day events.
    let times: [String?]
    let laneDepth: Int

    init(cells: [CalendarCellInfo?], layout: CalendarWeekLayout, calendars: [String: PersonalCalendarColor]) {
        self.cells = cells
        self.layout = layout
        self.calendars = calendars
        hidden = CalendarDensity.allCases.map { level in
            (0..<7).map { level == .compact ? 0 : layout.hiddenCount(column: $0, lanes: level.laneCount) }
        }
        hiddenCounts = Set(hidden.joined().filter { $0 > 0 }).sorted()
        times = layout.spans.map { span in
            span.isMultiDay || span.event.isAllDay ? nil : span.event.start.formatted(date: .omitted, time: .shortened)
        }
        laneDepth = layout.laneDepth
    }

    /// Whether a level leaves some of this week's events uncounted ("+N").
    func hasHidden(_ level: CalendarDensity) -> Bool {
        hidden[level.rawValue].contains { $0 > 0 }
    }
}

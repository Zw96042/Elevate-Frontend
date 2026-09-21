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


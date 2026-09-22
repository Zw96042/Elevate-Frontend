import SwiftUI

/// One week of the month grid, drawn in a single Canvas so a pinch can
/// redraw every visible week each frame without rebuilding views. Numbers
/// sit on their busy shade with an attendance dot; events morph with the
/// continuous zoom: each day's strip of colors stretches into lane bars,
/// bars thicken into tinted chips as titles fade in, and chips gain their
/// times. The grid model steps the zoom through every frame of a pinch or
/// a settle, so the drawing is a pure function of it.
struct CalendarWeekCanvas: View {
    let input: CalendarWeekInput
    var zoom: Double
    /// The number's circle and the caption scale, from the grid model so
    /// its height measurements agree with the drawing.
    let numberSize: CGFloat
    let scale: CGFloat

    private var layout: CalendarWeekLayout { input.layout }
    private var cells: [CalendarCellInfo?] { input.cells }

    /// Room for a number on its shade, and the hairline above it.
    private var numberArea: CGFloat { numberSize + 10 }

    var height: CGFloat {
        CalendarWeekCanvas.height(zoom: zoom, input: input, numberSize: numberSize, scale: scale)
    }

    /// The row's height at a zoom; the page uses the same function to keep
    /// the week under the fingers in place while zooming.
    static func height(zoom: Double, input: CalendarWeekInput, numberSize: CGFloat, scale: CGFloat) -> CGFloat {
        let events = CalendarZoom.eventsHeight(at: zoom, depth: input.laneDepth, hidden: input.hasHidden)
        return 0.5 + numberSize + 10 + CGFloat(events) * scale
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        } symbols: {
            symbols
        }
        .frame(height: height)
    }

    // MARK: - Symbols

    /// Text drawn once and reused every frame: day numbers, event titles,
    /// times and "+N" counts. Verbatim, so a frame's re-evaluated symbols
    /// compare equal to the last frame's and aren't laid out again.
    @ViewBuilder
    private var symbols: some View {
        ForEach(0..<7, id: \.self) { column in
            if let cell = cells[column] {
                Text(verbatim: String(cell.day.day))
                    .font(.figure(.body, weight: cell.isToday || cell.level >= 4 ? .semibold : .regular))
                    .foregroundStyle(numberColor(cell))
                    .tag("n\(column)")
            }
        }
        ForEach(Array(layout.spans.enumerated()), id: \.offset) { index, span in
            Text(verbatim: span.event.title.isEmpty ? "Untitled event" : span.event.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .fixedSize()
                .tag("t\(index)")
            if let time = input.times[index] {
                Text(verbatim: time)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                    .fixedSize()
                    .tag("m\(index)")
            }
        }
        ForEach(input.hiddenCounts, id: \.self) { count in
            Text(verbatim: "+\(count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.muted)
                .tag("p\(count)")
        }
    }

    private func numberColor(_ cell: CalendarCellInfo) -> Color {
        // Today's number takes the accent only on a light shade; on a
        // stronger one it keeps the readable ink and the ring marks today.
        if cell.isToday && cell.level <= 1 { return Color.themeAccent }
        if cell.level == 0 && cell.isWeekend { return Color.muted }
        return Color.dayLoadInk(level: cell.level)
    }


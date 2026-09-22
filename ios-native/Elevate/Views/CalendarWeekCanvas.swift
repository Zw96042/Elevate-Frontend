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

    // MARK: - Drawing

    private func color(_ event: PersonalEvent) -> Color {
        input.calendars[event.calendarID].map { Color(personal: $0) } ?? Color.muted
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let column = size.width / 7
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 0.5)), with: .color(Color.rule))

        for index in 0..<7 {
            guard let cell = cells[index] else { continue }
            let center = CGPoint(x: column * (CGFloat(index) + 0.5), y: 0.5 + 5 + numberSize / 2)
            let circle = CGRect(x: center.x - numberSize / 2, y: center.y - numberSize / 2,
                                width: numberSize, height: numberSize)
            if cell.level > 0 {
                context.fill(Path(ellipseIn: circle), with: .color(Color.dayLoad(level: cell.level)))
            }
            if cell.isToday {
                context.stroke(Path(ellipseIn: circle.insetBy(dx: -2, dy: -2)), with: .color(Color.themeAccent), lineWidth: 2)
            }
            if let number = context.resolveSymbol(id: "n\(index)") {
                context.draw(number, at: center, anchor: .center)
            }
            if cell.hasAttendance {
                let dot = CGRect(x: circle.maxX - 4, y: circle.minY - 1, width: 7, height: 7)
                context.fill(Path(ellipseIn: dot.insetBy(dx: -1.5, dy: -1.5)), with: .color(Color.appBackground))
                context.fill(Path(ellipseIn: dot), with: .color(Color.gradeWarning))
            }
        }

        guard !layout.spans.isEmpty else { return }
        let top = 0.5 + numberArea
        if zoom < 1 {
            drawCompactToBars(in: &context, column: column, top: top, progress: max(0, zoom))
        } else {
            drawLanes(in: &context, column: column, top: top)
        }
        drawMore(in: &context, column: column, top: top)
    }

    /// Compact: each day's events as a short strip of colors. Toward bars,
    /// every strip piece slides and stretches to its lane bar's place; pieces
    /// of the same event meet into one bar. Events past the bars' lanes fade.
    private func drawCompactToBars(in context: inout GraphicsContext, column: CGFloat, top: CGFloat, progress t: Double) {
        let barHeight = CGFloat(CalendarZoom.laneHeight(.bars)) * scale
        let spacing = CGFloat(CalendarZoom.laneSpacing) * scale
        for span in layout.spans {
            let shownAtBars = span.lane < CalendarDensity.bars.laneCount
            for day in span.startColumn...span.endColumn {
                let strip = compactRect(event: span.event, column: day, columnWidth: column, top: top)
                let bar = barPiece(span: span, column: day, columnWidth: column,
                                   y: top + CGFloat(span.lane) * (barHeight + spacing), height: barHeight)
                let rect: CGRect
                let opacity: Double
                if shownAtBars {
                    let from = strip ?? CGRect(x: bar.midX, y: bar.minY, width: 0, height: bar.height)
                    rect = Self.mix(from, bar, t)
                    opacity = strip == nil ? t : 1
                } else {
                    guard let strip else { continue }
                    rect = strip
                    opacity = 1 - t
                }
                guard opacity > 0.01, rect.width > 0.1 else { continue }
                let radius = min(2, rect.height / 2)
                context.fill(Path(roundedRect: rect, cornerRadius: radius),
                             with: .color(color(span.event).opacity(opacity)))
            }
        }
    }

    /// Bars through details: each event one shape across its days, its
    /// lane height growing with the zoom; titles and times fade in.
    private func drawLanes(in context: inout GraphicsContext, column: CGFloat, top: CGFloat) {
        let laneHeight = CGFloat(CalendarZoom.laneHeight(at: zoom)) * scale
        let spacing = CGFloat(CalendarZoom.laneSpacing) * scale
        let titleProgress = CalendarZoom.progress(zoom, from: 1)
        let timeProgress = CalendarZoom.progress(zoom, from: 2)
        let radius = CGFloat(CalendarZoom.mix(2.5, 4, titleProgress))
        for (index, span) in layout.spans.enumerated() {
            let opacity = CalendarZoom.laneOpacity(lane: span.lane, at: zoom)
            guard opacity > 0.01 else { continue }
            let leading = span.continuesBefore ? 0 : 2.0
            let trailing = span.continuesAfter ? 0 : 2.0
            let rect = CGRect(x: column * CGFloat(span.startColumn) + leading,
                              y: top + CGFloat(span.lane) * (laneHeight + spacing),
                              width: column * CGFloat(span.columnCount) - leading - trailing,
                              height: laneHeight)
            let isBlock = span.isMultiDay || span.event.isAllDay
            let tint = CalendarZoom.mix(1, isBlock ? 0.30 : 0.18, titleProgress)
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: span.continuesBefore ? 0 : radius,
                bottomLeadingRadius: span.continuesBefore ? 0 : radius,
                bottomTrailingRadius: span.continuesAfter ? 0 : radius,
                topTrailingRadius: span.continuesAfter ? 0 : radius,
                style: .continuous
            ).path(in: rect)
            let base = color(span.event)
            context.fill(shape, with: .color(base.opacity(tint * opacity)))
            guard titleProgress > 0.01 else { continue }
            var chip = context
            chip.clip(to: shape)
            if !isBlock && !span.continuesBefore {
                // A timed event keeps a color edge, so its tinted chip
                // still reads as its calendar.
                chip.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: 2.5, height: rect.height)),
                          with: .color(base.opacity(opacity * titleProgress)))
            }
            let textX = rect.minX + (isBlock || span.continuesBefore ? 5 : 6)
            chip.opacity = opacity * titleProgress
            if let title = chip.resolveSymbol(id: "t\(index)") {
                chip.draw(title, at: CGPoint(x: textX, y: rect.minY + 1.5), anchor: .topLeading)
            }
            if timeProgress > 0.01, let time = chip.resolveSymbol(id: "m\(index)") {
                chip.opacity = opacity * timeProgress
                chip.draw(time, at: CGPoint(x: textX, y: rect.minY + 1.5 + 13 * scale), anchor: .topLeading)
            }
        }
    }

    /// "+N" beneath the lanes for events a level doesn't show, crossfading
    /// between the counts of the levels either side of the zoom.
    private func drawMore(in context: inout GraphicsContext, column: CGFloat, top: CGFloat) {
        let (lower, upper, t) = CalendarZoom.bracket(zoom)
        for (level, weight) in [(lower, 1 - t), (upper, t)] where weight > 0.01 && level != .compact {
            let lanes = CalendarZoom.lanes(level, depth: input.laneDepth)
            let y = top + CGFloat(lanes) * CGFloat(CalendarZoom.laneHeight(level) + CalendarZoom.laneSpacing) * scale
            for index in 0..<7 {
                let hidden = input.hidden[level.rawValue][index]
                guard hidden > 0 else { continue }
                guard let symbol = context.resolveSymbol(id: "p\(hidden)") else { continue }
                var more = context
                more.opacity = weight
                more.draw(symbol, at: CGPoint(x: column * (CGFloat(index) + 0.5), y: y), anchor: .top)
            }
        }
    }

    /// Where one event sits in a day's compact strip, or nil past its fifth.
    private func compactRect(event: PersonalEvent, column: Int, columnWidth: CGFloat, top: CGFloat) -> CGRect? {
        let list = layout.dayEvents[column].prefix(5)
        guard let position = list.firstIndex(where: { $0.id == event.id }) else { return nil }
        let count = CGFloat(list.count)
        let width: CGFloat = list.count == 1 ? 14 : 7
        let start = columnWidth * (CGFloat(column) + 0.5) - count * width / 2
        return CGRect(x: start + CGFloat(position - list.startIndex) * width, y: top + 3, width: width - 1, height: 4)
    }

    /// One day's part of an event's bar; parts of one event meet.
    private func barPiece(span: CalendarEventSpan, column: Int, columnWidth: CGFloat, y: CGFloat, height: CGFloat) -> CGRect {
        let leading = column == span.startColumn && !span.continuesBefore ? 2.0 : -0.5
        let trailing = column == span.endColumn && !span.continuesAfter ? 2.0 : -0.5
        return CGRect(x: columnWidth * CGFloat(column) + leading, y: y,
                      width: columnWidth - leading - trailing, height: height)
    }

    private static func mix(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        let t = CGFloat(t)
        return CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                      width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}

/// A week row: the canvas, with the days' tap targets over it. The
/// targets sit outside the canvas so a zoom frame updates only the drawing;
/// they don't change with the zoom. Far from the screen the row keeps its
/// exact height and its targets (for VoiceOver and scrolling to a day) but
/// draws nothing, so a pinch redraws only the weeks that can be seen.
struct CalendarWeekRow: View {
    let input: CalendarWeekInput
    let zoom: Double
    let numberSize: CGFloat
    let scale: CGFloat
    /// How far beyond the visible area, in points, rows still draw.
    let reach: CGFloat
    let onSelect: (CalendarDay) -> Void

    @State private var isNear = true

    var body: some View {
        Group {
            if isNear {
                CalendarWeekCanvas(input: input, zoom: zoom, numberSize: numberSize, scale: scale)
            } else {
                Color.clear.frame(height: CalendarWeekCanvas.height(zoom: zoom, input: input,
                                                                     numberSize: numberSize, scale: scale))
            }
        }
        .overlay { CalendarDayTargets(cells: input.cells, onSelect: onSelect).equatable() }
        .onGeometryChange(for: Bool.self) { proxy in
            // In the scroll view's space the visible area starts at 0 and
            // is `reach` tall (the list passes its own height).
            let frame = proxy.frame(in: .scrollView)
            return frame.maxY > -reach && frame.minY < reach * 2
        } action: { near in
            isNear = near
        }
    }
}

/// One tap target per day over its whole column, numbers and events alike.
/// A tap rather than a Button: a Button fires when a finger lifts inside
/// it, so ending a pinch would open a day; a tap fails once a finger moves.
struct CalendarDayTargets: View, Equatable {
    let cells: [CalendarCellInfo?]
    let onSelect: (CalendarDay) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.cells == rhs.cells }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { column in
                if let cell = cells[column] {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(cell.day) }
                        .accessibilityElement()
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onSelect(cell.day) }
                        .accessibilityLabel(cell.spokenTitle)
                        .accessibilityValue(cell.spokenValue)
                        .accessibilityHint("Opens this day")
                        .accessibilityIdentifier("calendar.day.\(cell.day.iso)")
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
        }
    }
}

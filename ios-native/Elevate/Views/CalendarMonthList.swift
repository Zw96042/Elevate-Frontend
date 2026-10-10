import SwiftUI

/// The scrolling months. The only view that follows the zoom: a pinch
/// re-evaluates this list and redraws the week canvases near the screen
/// from inputs built beforehand, and nothing else on the page.
struct CalendarMonthList: View {
    var grid: CalendarGridModel
    var today: CalendarDay
    var reduceMotion: Bool
    var onSelect: (CalendarDay) -> Void
    /// A pinch settled on a level, to save.
    var onSettle: (CalendarDensity) -> Void
    var onRefresh: () async -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @GestureState private var isPinching = false

    var body: some View {
        let zoom = grid.zoom
        let numberSize = grid.numberSize
        let scale = grid.scale
        // The visible height, which rows also draw beyond each edge, so ones
        // a pinch or a fling is about to show are already drawn.
        let reach = max(grid.viewportHeight, 400)
        ScrollView {
            // Not lazy: every row exists with its exact height, so a jump or
            // a zoom lands precisely and nothing reflows while scrolling.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(grid.items) { item in
                    Group {
                        switch item.kind {
                        case .header:
                            CalendarMonthHeader(month: item.month, today: today)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { grid.headerHeight = $0 }
                        case .week:
                            if let input = grid.weeks[item.id] {
                                CalendarWeekRow(input: input, zoom: zoom, numberSize: numberSize,
                                                scale: scale, reach: reach, onSelect: onSelect)
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.page)
                    .id(item.id)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { grid.contentMinY = $0 }
            .padding(.bottom, 96)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        // Two fingers zoom rather than also scrolling, which would fight
        // the anchor and coast on after they lift.
        .scrollDisabled(isPinching)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { grid.viewportHeight = $0 }
        .onChange(of: dynamicTypeSize, initial: true) { _, size in grid.setTextSize(size) }
        .softScrollEdges()
        .visibleRefreshable {
            await onRefresh()
        }
        // Pinch out for more detail, in for less, as in Calendar. The zoom
        // follows the fingers continuously, the point under them stays put,
        // and lifting them settles on the nearest level (a quick pinch
        // carries on to the next).
        .simultaneousGesture(
            MagnifyGesture(minimumScaleDelta: 0.01)
                .updating($isPinching) { _, pinching, _ in pinching = true }
                .onChanged { value in
                    grid.pinchChanged(magnification: value.magnification, startY: value.startLocation.y)
                }
                .onEnded { value in
                    settle(on: grid.pinchEnded(magnification: value.magnification, velocity: value.velocity))
                }
        )
        .onChange(of: isPinching) { _, pinching in
            // A cancelled pinch never ends; settle it here instead.
            if !pinching, let level = grid.pinchCancelled() { settle(on: level) }
        }
        .accessibilityAction(named: "Show more detail") { step(to: CalendarZoom.settle(grid.zoom).denser) }
        .accessibilityAction(named: "Show less detail") { step(to: CalendarZoom.settle(grid.zoom).sparser) }
        .accessibilityIdentifier("calendar.months")
    }

    private func settle(on level: CalendarDensity) {
        grid.settle(on: level, animated: !reduceMotion)
        onSettle(level)
    }

    private func step(to level: CalendarDensity?) {
        guard let level else { return }
        grid.anchorTop()
        settle(on: level)
    }
}

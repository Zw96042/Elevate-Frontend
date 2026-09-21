import SwiftUI
import UIKit

/// The month grid's zoom and everything a pinch needs, kept apart from
/// the page. Only the month list reads `zoom`, so a pinch redraws the
/// weeks and nothing else, and every week's drawing input is built once
/// per data change, so a frame never looks anything up.
///
/// The zoom never animates through SwiftUI: a pinch sets it per touch
/// update and a settle steps it per display frame, each time scrolling so
/// the anchored point stays put. Animating row heights and a scroll
/// together would let the two drift apart.
@MainActor @Observable
final class CalendarGridModel {
    struct Anchor {
        var id: String
        /// How far down its row the anchored point is, 0...1.
        var fraction: CGFloat
        /// Where on screen that point stays.
        var viewportY: CGFloat
    }

    /// The continuous zoom, 0 (compact) through 3 (details); whole numbers
    /// are the saved levels.
    private(set) var zoom: Double
    private(set) var items: [CalendarGridItem] = []
    /// Each week's drawing input, by grid item id.
    private(set) var weeks: [String: CalendarWeekInput] = [:]
    /// The day number's circle and the caption scale, at the grid's capped
    /// text size. Rows draw with these and heights are measured with them.
    private(set) var numberSize: CGFloat = 32
    private(set) var scale: CGFloat = 1

    // Scroll state, kept out of observation so scrolling never re-renders.
    @ObservationIgnored var proxy: ScrollViewProxy?
    /// The content's top in the scroll view: 0 at rest, negative when scrolled.
    /// Once it reports, it's current, so a scroll made in code is measured.
    @ObservationIgnored var contentMinY: CGFloat = 0 {
        didSet { scrolledTo = nil }
    }
    @ObservationIgnored var viewportHeight: CGFloat = 600
    @ObservationIgnored var headerHeight: CGFloat = 44
    /// Set once the list has scrolled to its first month; until then a data
    /// change has no place to keep.
    @ObservationIgnored private(set) var isPositioned = false
    /// The month to open on, waiting for its rows to exist.
    @ObservationIgnored private var pendingPosition: String?
    /// The row a scroll made in code put at the top, until the list reports
    /// where it now is; `contentMinY` is stale until then.
    @ObservationIgnored private var scrolledTo: Anchor?
    @ObservationIgnored private var pinchStart: Double?
    @ObservationIgnored private var anchor: Anchor?
    @ObservationIgnored private var settleDriver: CalendarSettleDriver?

    init(level: CalendarDensity) {
        zoom = Double(level.rawValue)
    }

    /// New rows or inputs. The week at the top of the screen stays where it
    /// is, so events arriving, months joining the range or lanes changing
    /// height never move what the person is looking at.
    func update(items: [CalendarGridItem], weeks: [String: CalendarWeekInput]) {
        guard items != self.items || weeks != self.weeks else { return }
        let held = isPositioned && pinchStart == nil && settleDriver == nil
            ? scrolledTo ?? anchor(atViewportY: 0) : nil
        let before = held.flatMap(contentY)
        if items != self.items { self.items = items }
        if weeks != self.weeks { self.weeks = weeks }
        positionIfReady()
        // Scroll only if the held point actually moved, so a change that
        // only reshades days never touches a scroll in progress.
        guard let held, let before, let after = contentY(of: held), abs(after - before) > 0.5 else { return }
        anchor = held
        apply(zoom)
        anchor = nil
    }

    /// Where an anchored point sits in the content, at the current zoom.
    private func contentY(of anchor: Anchor) -> CGFloat? {
        var top: CGFloat = 0
        for item in items {
            let height = height(of: item, at: zoom)
            if item.id == anchor.id { return top + anchor.fraction * height }
            top += height
        }
        return nil
    }

    func setTextSize(_ size: DynamicTypeSize) {
        let category = UIContentSizeCategory(min(size, .xxLarge))
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let number = UIFontMetrics(forTextStyle: .body).scaledValue(for: 32, compatibleWith: traits)
        let caption = UIFontMetrics(forTextStyle: .caption2).scaledValue(for: 1, compatibleWith: traits)
        if number != numberSize { numberSize = number }
        if caption != scale { scale = caption }
    }

    // MARK: - Scrolling in code

    /// Opens the list on a row (a month's header) once its rows exist, and
    /// from then on keeps the person's place through data changes.
    func position(at id: String) {
        isPositioned = false
        pendingPosition = id
        positionIfReady()
    }

    /// Scrolls a row to the top now.
    func scroll(to id: String, animation: Animation?) {
        guard let proxy else { return }
        stopSettling()
        Motion.perform(animation) { proxy.scrollTo(id, anchor: .top) }
        scrolledTo = Anchor(id: id, fraction: 0, viewportY: 0)
    }

    private func positionIfReady() {
        guard let id = pendingPosition, proxy != nil, items.contains(where: { $0.id == id }) else { return }
        pendingPosition = nil
        // After the rows' first layout, so the jump is exact.
        DispatchQueue.main.async { [weak self] in
            guard let self, pendingPosition == nil else { return }
            scroll(to: id, animation: nil)
            isPositioned = true
        }
    }

    // MARK: - Heights

    /// A grid item's height at a zoom, from the same function its row uses.
    func height(of item: CalendarGridItem, at zoom: Double) -> CGFloat {
        guard case .week = item.kind else { return headerHeight }
        guard let input = weeks[item.id] else { return 0 }
        return CalendarWeekCanvas.height(zoom: zoom, input: input, numberSize: numberSize, scale: scale)
    }

    // MARK: - Pinching

    var isPinching: Bool { pinchStart != nil }

    func pinchChanged(magnification: CGFloat, startY: CGFloat) {
        if pinchStart == nil {
            stopSettling()
            pinchStart = zoom
            anchor = anchor(atViewportY: startY)
        }
        apply(CalendarZoom.zoom(start: pinchStart ?? zoom, magnification: Double(magnification)))
    }

    /// The level a pinch settles on once the fingers lift; a quick pinch
    /// carries on to the next, never further.
    func pinchEnded(magnification: CGFloat, velocity: CGFloat) -> CalendarDensity {
        // Scale per second, as zoom levels per second.
        let rate = Double(velocity) / max(Double(magnification), 0.01) / log(2) * 1.7
        pinchStart = nil
        let nearest = CalendarZoom.settle(zoom)
        let projected = CalendarZoom.settle(zoom, velocity: rate)
        let step = min(max(projected.rawValue - nearest.rawValue, -1), 1)
        return CalendarDensity(rawValue: nearest.rawValue + step) ?? nearest
    }

    /// A pinch the system cancelled, which never reports an end: settle
    /// where it was. Returns the level, or nil if no pinch was left open.
    func pinchCancelled() -> CalendarDensity? {
        guard pinchStart != nil else { return nil }
        pinchStart = nil
        return CalendarZoom.settle(zoom)
    }

    /// A level from the menu, with the week at the top of the screen held.
    func anchorTop() {
        stopSettling()
        anchor = anchor(atViewportY: 0)
    }

    /// Moves the zoom to a level, frame by frame unless `animated` is off,
    /// keeping the anchored row where it was on screen throughout.
    func settle(on level: CalendarDensity, animated: Bool) {
        stopSettling()
        let target = Double(level.rawValue)
        let distance = abs(target - zoom)
        guard animated, distance > 0.001 else {
            apply(target)
            anchor = nil
            return
        }
        let start = zoom
        settleDriver = CalendarSettleDriver(duration: 0.26 + 0.08 * min(distance, 3)) { [weak self] progress in
            guard let self else { return }
            // Ease out, like a well-damped spring with no overshoot.
            let eased = 1 - pow(1 - progress, 3)
            apply(CalendarZoom.mix(start, target, eased))
            if progress >= 1 {
                settleDriver = nil
                anchor = nil
            }
        }
    }

    private func stopSettling() {
        settleDriver?.stop()
        settleDriver = nil
    }

    // MARK: - Anchoring

    /// Sets the zoom without animation and scrolls to hold the anchor.
    private func apply(_ value: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            zoom = value
            holdAnchor()
        }
    }

    /// The grid item under a point of the screen, and how far down it.
    private func anchor(atViewportY y: CGFloat) -> Anchor? {
        let contentY = y - contentMinY
        var top: CGFloat = 0
        for (index, item) in items.enumerated() {
            let height = height(of: item, at: zoom)
            if contentY < top + height || index == items.count - 1 {
                let fraction = height > 0 ? min(max((contentY - top) / height, 0), 1) : 0
                return Anchor(id: item.id, fraction: fraction, viewportY: y)
            }
            top += height
        }
        return nil
    }

    /// Scrolls so the anchored point of its row stays at the same place on
    /// screen at the current zoom. The unit point is linear in the offset,
    /// so it's left unclamped: a row partly above the top edge needs a
    /// negative one.
    private func holdAnchor() {
        guard let anchor, let proxy, let item = items.first(where: { $0.id == anchor.id }) else { return }
        let height = height(of: item, at: zoom)
        let span = viewportHeight - height
        guard abs(span) > 0.5 else { return }
        let unit = (anchor.viewportY - anchor.fraction * height) / span
        proxy.scrollTo(item.id, anchor: UnitPoint(x: 0.5, y: unit))
    }
}

/// Calls back once per display frame with progress 0...1 over a duration,
/// then stops.
@MainActor
final class CalendarSettleDriver: NSObject {
    private var link: CADisplayLink?
    private let duration: CFTimeInterval
    private let start = CACurrentMediaTime()
    private let step: (Double) -> Void

    init(duration: CFTimeInterval, step: @escaping (Double) -> Void) {
        self.duration = duration
        self.step = step
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        let progress = min((CACurrentMediaTime() - start) / duration, 1)
        if progress >= 1 { stop() }
        step(progress)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}

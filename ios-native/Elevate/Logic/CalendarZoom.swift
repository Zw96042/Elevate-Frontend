import Foundation

/// The month grid's zoom as one continuous value, 0 (compact) through 3
/// (details), so a pinch can morph between densities in step with the
/// fingers rather than jumping. Whole numbers are the `CalendarDensity`
/// levels; everything between is interpolated from them. Pure, so the
/// geometry is testable and every row agrees on its own height.
enum CalendarZoom {
    static let range: ClosedRange<Double> = 0...3

    /// The level at or below the zoom, the one above, and how far between.
    static func bracket(_ zoom: Double) -> (lower: CalendarDensity, upper: CalendarDensity, fraction: Double) {
        let z = min(max(zoom, range.lowerBound), range.upperBound)
        let lower = Int(z.rounded(.down))
        let upper = min(lower + 1, 3)
        return (CalendarDensity(rawValue: lower) ?? .compact, CalendarDensity(rawValue: upper) ?? .details, z - Double(lower))
    }

    /// The nearest level, where a pinch settles when the fingers lift.
    static func settle(_ zoom: Double, velocity: Double = 0) -> CalendarDensity {
        // A quick pinch carries a little further, as a flick does.
        let projected = min(max(zoom + velocity * 0.15, range.lowerBound), range.upperBound)
        return CalendarDensity(rawValue: Int(projected.rounded())) ?? .bars
    }

    /// The zoom a pinch has reached: pinching out by half again roughly
    /// steps one level, and the ends give a little before stopping.
    static func zoom(start: Double, magnification: Double) -> Double {
        let raw = start + log2(max(magnification, 0.01)) * 1.7
        if raw < range.lowerBound { return range.lowerBound - rubber(range.lowerBound - raw) }
        if raw > range.upperBound { return range.upperBound + rubber(raw - range.upperBound) }
        return raw
    }

    private static func rubber(_ overshoot: Double) -> Double { 0.25 * (1 - 1 / (overshoot + 1)) }

    static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// Clamped progress of the zoom through one step, 0 at `from`, 1 a
    /// whole level later.
    static func progress(_ zoom: Double, from start: Double) -> Double {
        min(max(zoom - start, 0), 1)
    }

    // MARK: - Geometry, in points before Dynamic Type scaling

    static let laneSpacing = 2.0
    static let moreRowHeight = 13.0
    /// The least room under a week's numbers, so quiet weeks keep rhythm.
    static let minimumEventsHeight = 8.0
    static let compactEventsHeight = 12.0

    static func laneHeight(_ level: CalendarDensity) -> Double {
        switch level {
        case .compact: return 4
        case .bars: return 5
        case .titles: return 17
        case .details: return 31
        }
    }

    static func laneHeight(at zoom: Double) -> Double {
        let (lower, upper, t) = bracket(zoom)
        return mix(laneHeight(lower), laneHeight(upper), t)
    }

    /// Lanes a week shows at a level: none in compact, then as many as its
    /// events need up to the level's limit.
    static func lanes(_ level: CalendarDensity, depth: Int) -> Int {
        level == .compact ? 0 : min(max(depth, 0), level.laneCount)
    }

    /// Room under the numbers at a whole level.
    static func eventsHeight(_ level: CalendarDensity, depth: Int, hasHidden: Bool) -> Double {
        guard level != .compact else { return compactEventsHeight }
        let shown = lanes(level, depth: depth)
        let lanesHeight = Double(shown) * (laneHeight(level) + laneSpacing)
        return max(minimumEventsHeight, lanesHeight + (hasHidden ? moreRowHeight : 4))
    }

    /// Room under the numbers at any zoom, interpolated between levels.
    /// `hidden(level)` says whether that level leaves events uncounted.
    static func eventsHeight(at zoom: Double, depth: Int, hidden: (CalendarDensity) -> Bool) -> Double {
        let (lower, upper, t) = bracket(zoom)
        return mix(eventsHeight(lower, depth: depth, hasHidden: hidden(lower)),
                   eventsHeight(upper, depth: depth, hasHidden: hidden(upper)), t)
    }

    /// How visible a lane is at a zoom: fully once its level shows it,
    /// fading in across the step where it first appears.
    static func laneOpacity(lane: Int, at zoom: Double) -> Double {
        let (lower, upper, t) = bracket(zoom)
        let atLower = lane < lower.laneCount ? 1.0 : 0
        let atUpper = lane < upper.laneCount ? 1.0 : 0
        return mix(atLower, atUpper, t)
    }
}

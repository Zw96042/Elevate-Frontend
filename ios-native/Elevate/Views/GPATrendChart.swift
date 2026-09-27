import SwiftUI
import Accessibility
import UIKit

/// One term on the GPA trend: its table key ("PR1", "RC2") and value.
struct GPATrendPoint: Hashable, Identifiable {
    var label: String
    var value: Double
    var level: GradeLevel? = nil
    var id: String { "\(level?.rawValue ?? "").\(label)" }
    var termName: String { GPAReport.termName(label) }
    var displayName: String {
        level.map { "\($0.yearName), \(termName)" } ?? termName
    }
}

// MARK: - Curve geometry

/// The trend as a smooth curve through each term, after the legacy chart:
/// every segment is a cubic Bézier whose control points sit at 30% and 70% of
/// the segment's width, each at the height of its nearer end. Tangents are
/// flat at every term, so the curve never overshoots a real value.
struct GPACurve {
    /// Term positions, evenly spaced left to right.
    let points: [CGPoint]
    let size: CGSize

    /// Vertical room left above the highest and below the lowest value.
    private static let verticalPadding: CGFloat = 0.1

    /// The chart's horizontal inset, shared by the drawn line, the touch dot
    /// and the scrub surface.
    static let chartInset: CGFloat = 6

    /// `inset` keeps the ends of the line and the touch dot inside the frame.
    init(values: [Double], size: CGSize, inset: CGFloat = GPACurve.chartInset) {
        self.size = size
        let range = Self.range(of: values)
        let span = range.upperBound - range.lowerBound
        let width = max(size.width - inset * 2, 1)
        let top = size.height * Self.verticalPadding
        let plotHeight = size.height * (1 - Self.verticalPadding * 2)
        let steps = CGFloat(max(values.count - 1, 1))
        points = values.enumerated().map { index, value in
            let fraction = span > 0 ? (range.upperBound - value) / span : 0.5
            return CGPoint(
                x: inset + width * CGFloat(index) / steps,
                y: top + plotHeight * CGFloat(fraction)
            )
        }
    }

    /// The plotted range on the real percentage scale: the data's own
    /// minimum and maximum, but never less than ten points tall, so a
    /// fraction-of-a-point change doesn't fill the short chart. A series
    /// narrower than that sits in the middle.
    private static let minimumSpan: Double = 10

    static func range(of values: [Double]) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else { return 0...1 }
        let span = max(high - low, minimumSpan)
        let middle = (high + low) / 2
        return (middle - span / 2)...(middle + span / 2)
    }

    var line: Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for (start, end) in zip(points, points.dropFirst()) {
                let (control1, control2) = Self.controls(start, end)
                path.addCurve(to: end, control1: control1, control2: control2)
            }
        }
    }

    /// The area between the curve and the bottom edge.
    var area: Path {
        var path = line
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }

    /// The point on the curve at a horizontal fraction of the plot, and the
    /// nearest term. The nearest term changes at the midpoint between terms.
    func position(at fraction: CGFloat) -> (point: CGPoint, nearest: Int) {
        guard let first = points.first, let last = points.last, points.count > 1 else {
            return (points.first ?? .zero, 0)
        }
        let clamped = min(max(fraction, 0), 1)
        let x = first.x + (last.x - first.x) * clamped
        let segment = min(Int(clamped * CGFloat(points.count - 1)), points.count - 2)
        let start = points[segment]
        let end = points[segment + 1]
        let nearest = Int((clamped * CGFloat(points.count - 1)).rounded())


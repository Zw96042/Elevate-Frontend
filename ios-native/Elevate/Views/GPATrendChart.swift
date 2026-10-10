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

        // x(t) rises monotonically, so a few bisection steps find the t
        // whose x is under the finger.
        let width = end.x - start.x
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<18 {
            let t = (low + high) / 2
            let u = 1 - t
            let curveX = start.x + width * (0.9 * u * u * t + 2.1 * u * t * t + t * t * t)
            if curveX < x { low = t } else { high = t }
        }
        let t = (low + high) / 2
        let u = 1 - t
        let y = start.y * (u * u * u + 3 * u * u * t) + end.y * (3 * u * t * t + t * t * t)
        return (CGPoint(x: x, y: y), nearest)
    }

    private static func controls(_ start: CGPoint, _ end: CGPoint) -> (CGPoint, CGPoint) {
        let width = end.x - start.x
        return (
            CGPoint(x: start.x + width * 0.3, y: start.y),
            CGPoint(x: start.x + width * 0.7, y: end.y)
        )
    }
}

/// The drawn curve as heights at evenly spaced positions from the first term
/// to the last, each a fraction of the plot's height. Every series has the
/// same number of heights whatever its number of terms, so a change of year
/// or series interpolates one rendered line into the next in place. Only
/// positions are interpolated; values, labels and readings always come from
/// the final points.
struct GPACurveProfile: VectorArithmetic {
    /// Dense enough that each term of All years spans several samples.
    static let sampleCount = 321

    var heights: [Double]

    init(heights: [Double]) {
        self.heights = heights
    }

    /// The curve through `values`: the same range, padding and segments as
    /// `GPACurve`, with both ends exactly at the first and last terms.
    init(values: [Double]) {
        guard !values.isEmpty else {
            heights = []
            return
        }
        let curve = GPACurve(values: values, size: CGSize(width: 1, height: 1), inset: 0)
        let last = Self.sampleCount - 1
        heights = (0...last).map { index in
            let point: CGPoint
            switch index {
            case 0: point = curve.points.first ?? .zero
            case last: point = curve.points.last ?? .zero
            default: point = curve.position(at: CGFloat(index) / CGFloat(last)).point
            }
            return point.y.isFinite ? Double(point.y) : 0.5
        }
    }

    static var zero: GPACurveProfile { GPACurveProfile(heights: []) }

    static func + (lhs: GPACurveProfile, rhs: GPACurveProfile) -> GPACurveProfile {
        lhs.combined(with: rhs, +)
    }

    static func - (lhs: GPACurveProfile, rhs: GPACurveProfile) -> GPACurveProfile {
        lhs.combined(with: rhs, -)
    }

    mutating func scale(by rate: Double) {
        for index in heights.indices { heights[index] *= rate }
    }

    var magnitudeSquared: Double {
        heights.reduce(0) { $0 + $1 * $1 }
    }

    /// `zero` is empty, so a missing height counts as zero.
    private func combined(with other: GPACurveProfile, _ operation: (Double, Double) -> Double) -> GPACurveProfile {
        let count = max(heights.count, other.heights.count)
        var result = [Double]()
        result.reserveCapacity(count)
        for index in 0..<count {
            let lhs = index < heights.count ? heights[index] : 0
            let rhs = index < other.heights.count ? other.heights[index] : 0
            result.append(operation(lhs, rhs))
        }
        return GPACurveProfile(heights: result)
    }
}

/// The line, or the area beneath it, drawn from an animatable profile.
private struct GPACurveShape: Shape {
    var profile: GPACurveProfile
    var closesArea = false

    var animatableData: GPACurveProfile {
        get { profile }
        set { profile = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let heights = profile.heights
        guard heights.count > 1 else { return Path() }
        let inset = GPACurve.chartInset
        let step = max(rect.width - inset * 2, 1) / CGFloat(heights.count - 1)
        var path = Path()
        for (index, height) in heights.enumerated() {
            let point = CGPoint(
                x: rect.minX + inset + step * CGFloat(index),
                y: rect.minY + rect.height * CGFloat(height)
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        if closesArea {
            let lastX = rect.minX + inset + step * CGFloat(heights.count - 1)
            path.addLine(to: CGPoint(x: lastX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Chart

/// The GPA trend: a short curve with a fading wash and nothing else at rest.
/// Touching it places a dot on the curve under the finger and names the
/// nearest term; letting go clears it. Vertical drags that start on the chart
/// still scroll the page.
///
/// Keep one chart across changes of school year and series: it draws in
/// once, then the same line reshapes to each new set of points.
struct GPATrendChart: View {
    var points: [GPATrendPoint]
    /// "Weighted" or "Unweighted".
    var seriesName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubFraction: CGFloat?
    @State private var reveal: CGFloat = 0
    @State private var revealFinished = false
    @State private var accessibilityIndex: Int?
    /// Replacing the drawn curve's identity ends any reshape in progress, so
    /// the line is already at the values a reading reports.
    @State private var curveGeneration = 0

    private static let height: CGFloat = 112

    /// The horizontal position being read, from touch or VoiceOver.
    private var activeFraction: CGFloat? {
        if let scrubFraction { return scrubFraction }
        guard let accessibilityIndex, points.count > 1 else { return nil }
        return CGFloat(min(accessibilityIndex, points.count - 1)) / CGFloat(points.count - 1)
    }

    private var isReading: Bool {
        scrubFraction != nil || accessibilityIndex != nil
    }

    private var snappedIndex: Int? {
        guard let activeFraction, points.count > 1 else { return nil }
        return Int((min(max(activeFraction, 0), 1) * CGFloat(points.count - 1)).rounded())
    }

    var body: some View {
        // Split from the accessibility modifiers below so Xcode 26 can
        // type-check each chain in reasonable time.
        chart
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(seriesName) GPA trend"))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Swipe up or down to hear each term.")
            .accessibilityAdjustableAction(adjust)
            .accessibilityChartDescriptor(
                GPAChartDescriptor(title: "\(seriesName) GPA by term", points: points)
            )
            .accessibilityIdentifier("gpa.chart")
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                plot(in: proxy.size)
            }
            .frame(height: Self.height)

            HStack(alignment: .top) {
                if let first = points.first {
                    endpoint(first, alignment: .leading)
                }
                Spacer(minLength: 8)
                if let last = points.last, points.count > 1 {
                    endpoint(last, alignment: .trailing)
                }
            }
            .font(.figure(.caption, weight: .regular))
            .foregroundStyle(Color.muted)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: snappedIndex) { old, new in
            old != nil && new != nil && old != new
        }
        .onAppear(perform: startReveal)
        .onChange(of: points) { old, new in
            // New data under a reading shows at once (the change was not
            // animated); this also ends a reshape that was already running.
            if isReading { settle() }
            // Another year's terms: a VoiceOver position no longer names the
            // same term.
            if old.map(\.id) != new.map(\.id) { accessibilityIndex = nil }
        }
        // Turning on Reduce Motion mid-draw or mid-reshape shows the whole,
        // current curve at once.
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { settle() }
        }
        .onDisappear { scrubFraction = nil }
    }

    /// An end of the curve: its term (with the school year on All years) and
    /// value.
    private func endpoint(_ point: GPATrendPoint, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(point.displayName)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
            // Rolls with a change of year or series like the screen's other
            // figures; instant with Reduce Motion.
            Text(GradeFormat.gpa(point.value))
                .font(.figure(.caption, weight: .medium))
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText(value: point.value))
                .animation(Motion.value(reduceMotion), value: point.value)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    private func plot(in size: CGSize) -> some View {
        let values = points.map(\.value)
        // The dot and callout read the final points on the exact curve; the
        // drawn line is already settled whenever they show.
        let curve = GPACurve(values: values, size: size)
        let reading = activeFraction.map { curve.position(at: $0) }
        let profile = GPACurveProfile(values: values)
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                GPACurveShape(profile: profile, closesArea: true)
                    .fill(LinearGradient(
                        colors: [Color.chartFill, Color.chartFill.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                GPACurveShape(profile: profile)
                    .stroke(Color.chartLine, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            // A reading shows final data, so new points under it are not
            // animated.
            .animation(isReading ? nil : Motion.morph(reduceMotion), value: profile)
            .id(curveGeneration)
            .mask(alignment: .leading) {
                if revealFinished {
                    Rectangle()
                } else {
                    Rectangle().scaleEffect(x: reveal, anchor: .leading)
                }
            }

            if let reading, points.indices.contains(reading.nearest) {
                Circle()
                    .fill(Color.chartLine)
                    .overlay { Circle().strokeBorder(Color.appBackground, lineWidth: 2) }
                    .frame(width: 11, height: 11)
                    .position(reading.point)

                CalloutLayout(anchor: reading.point, gap: 10) {
                    callout(reading.nearest)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            ChartScrubSurface(onScrub: scrub)
                .accessibilityHidden(true)
        }
    }

    /// A compact tooltip on the quiet well: the term (and year on All years),
    /// its value, and the change from the previous point.
    private func callout(_ index: Int) -> some View {
        let point = points[index]
        let change = index > 0 ? point.value - points[index - 1].value : nil
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return VStack(alignment: .leading, spacing: 1) {
            Text(point.displayName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ink)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(GradeFormat.gpa(point.value))
                    .font(.figure(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.ink)
                if let change {
                    Text(GradeFormat.signedChange(change))
                        .font(.figure(.footnote, weight: .regular))
                        .foregroundStyle(Color.muted)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.well, in: shape)
        .overlay { shape.strokeBorder(Color.rule, lineWidth: Metrics.line) }
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    // MARK: Reveal

    private func startReveal() {
        if reduceMotion {
            revealFinished = true
            return
        }
        Motion.perform(Motion.reveal(reduceMotion)) { reveal = 1 }
    }

    /// A reading during the draw-in or a reshape shows the whole, current
    /// curve at once, so the dot sits on the line it describes.
    private func settle() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            revealFinished = true
            curveGeneration &+= 1
        }
    }

    /// A touch settles the curve in the same update that places the dot.
    private func scrub(_ fraction: CGFloat?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if fraction != nil, scrubFraction == nil { settle() }
            scrubFraction = fraction
        }
    }

    // MARK: Accessibility

    private var accessibilityValue: String {
        if let accessibilityIndex, points.indices.contains(accessibilityIndex) {
            let point = points[accessibilityIndex]
            return "\(point.displayName), \(GradeFormat.gpa(point.value))"
        }
        guard let first = points.first, let last = points.last else { return "" }
        return "\(points.count) terms, from \(GradeFormat.gpa(first.value)) in \(first.displayName) to \(GradeFormat.gpa(last.value)) in \(last.displayName)"
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard !points.isEmpty else { return }
        if accessibilityIndex == nil { settle() }
        let last = points.count - 1
        let current = accessibilityIndex.map { min($0, last) }
        switch direction {
        case .increment:
            accessibilityIndex = min((current ?? -1) + 1, last)
        case .decrement:
            accessibilityIndex = max((current ?? points.count) - 1, 0)
        @unknown default:
            break
        }
    }
}

/// UIKit can reject a vertical pan before it recognizes. Filtering a
/// SwiftUI DragGesture's updates happens too late: it has already competed
/// with the surrounding scroll view for that touch.
private struct ChartScrubSurface: UIViewRepresentable {
    var onScrub: (CGFloat?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrub: onScrub)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panChanged(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onScrub = onScrub
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onScrub: (CGFloat?) -> Void

        init(onScrub: @escaping (CGFloat?) -> Void) {
            self.onScrub = onScrub
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let movement = pan.translation(in: pan.view)
            return abs(movement.x) > abs(movement.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // A scroll-view pan must not cancel an accepted horizontal scrub,
            // and this recognizer must never prevent the page from scrolling.
            guard let scrollView = otherGestureRecognizer.view as? UIScrollView else { return false }
            return otherGestureRecognizer === scrollView.panGestureRecognizer
        }

        @objc func panChanged(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began, .changed:
                guard let view = pan.view else { return }
                let inset = GPACurve.chartInset
                let usable = max(view.bounds.width - inset * 2, 1)
                onScrub(min(max((pan.location(in: view).x - inset) / usable, 0), 1))
            case .ended, .cancelled, .failed:
                onScrub(nil)
            default:
                break
            }
        }
    }
}

/// Places a callout centered above an anchor point, kept inside the plot's
/// edges and flipped below the point when there is no room above.
private struct CalloutLayout: Layout {
    var anchor: CGPoint
    var gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let callout = subviews.first else { return }
        let size = callout.sizeThatFits(.unspecified)
        let x = min(max(anchor.x - size.width / 2, 0), max(bounds.width - size.width, 0))
        var y = anchor.y - gap - size.height
        if y < 0 { y = anchor.y + gap }
        y = min(y, max(bounds.height - size.height, 0))
        callout.place(
            at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
        )
    }
}

/// The chart's data for VoiceOver's audio graph and chart summary.
private struct GPAChartDescriptor: AXChartDescriptorRepresentable {
    var title: String
    var points: [GPATrendPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        // Year-qualified on All years, so each year's terms stay distinct.
        let names = points.map(\.displayName)
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Term", categoryOrder: names)
        let yAxis = AXNumericDataAxisDescriptor(
            title: "GPA",
            range: GPACurve.range(of: points.map(\.value)),
            gridlinePositions: []
        ) { String(format: "%.2f", $0) }
        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: true,
            dataPoints: zip(names, points).map { AXDataPoint(x: $0, y: $1.value) }
        )
        return AXChartDescriptor(
            title: title,
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

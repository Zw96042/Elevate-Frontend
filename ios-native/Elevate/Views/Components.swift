import SwiftUI
import UIKit

extension View {
    /// Explicitly retain the blurred transition across system releases whose
    /// automatic scroll-edge style can otherwise become a hard boundary.
    @ViewBuilder
    func softScrollEdges() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            self
        }
    }
}

extension View {
    /// Pull to refresh for a scroll view. Only a pull that begins with the
    /// page at rest at its top refreshes. Returning from lower content stops
    /// at the top; another touch and pull is required to stretch past it.
    func visibleRefreshable(action: @escaping () async -> Void) -> some View {
        modifier(VisibleRefreshModifier(action: action))
    }
}

private struct VisibleRefreshModifier: ViewModifier {
    var action: () async -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isMainContentVisible) private var isMainContentVisible
    @State private var refreshing = false
    @State private var pullDistance: CGFloat = 0
    @State private var refreshTask: Task<Void, Never>?

    /// Overscroll a deliberate pull must reach for its release to refresh.
    private static let threshold: CGFloat = 72
    /// Pulls shorter than this are the drag's own slack and show nothing.
    private static let feedbackStart: CGFloat = 8

    func body(content: Content) -> some View {
        source(content)
            .scrollBounceBehavior(.always, axes: .vertical)
            .accessibilityValue(refreshing ? "Refreshing" : "")
            .onChange(of: !voiceOverEnabled && scenePhase == .active && isMainContentVisible) {
                pullDistance = 0
            }
            .onDisappear {
                refreshTask?.cancel()
                refreshTask = nil
                refreshing = false
                pullDistance = 0
            }
            .overlay(alignment: .top) {
                // The one indicator: the pull's progress, then the refresh.
                // VoiceOver uses the system control's own.
                if !voiceOverEnabled, refreshing || pullDistance > Self.feedbackStart {
                    Group {
                        if refreshing {
                            RefreshSpinner(color: Color.ink)
                        } else {
                            PullProgressRing(progress: min(pullDistance / Self.threshold, 1))
                        }
                    }
                    .frame(width: 20, height: 20)
                    .padding(10)
                    .background(Color.appBackground, in: Circle())
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder
    private func source(_ content: Content) -> some View {
        if voiceOverEnabled {
            // VoiceOver scrolls a page at a time and refreshes with a
            // three-finger swipe at the top, already a deliberate gesture
            // that the system control supports and announces.
            content.refreshable { await performRefresh() }
        } else {
            content.background {
                DeliberatePullObserver(isEnabled: scenePhase == .active && isMainContentVisible,
                                       threshold: Self.threshold) { distance in
                    pullDistance = distance
                } onRelease: { reachedThreshold in
                    pullDistance = 0
                    if reachedThreshold { startRefresh() }
                }
            }
        }
    }

    /// Some system releases cancel the refresh callback on release. Own the
    /// request/indicator lifetime, and cancel it when this screen disappears.
    @MainActor
    private func startRefresh() {
        guard refreshTask == nil else { return }
        refreshing = true
        refreshTask = Task { @MainActor in
            let started = ContinuousClock.now
            await action()
            do {
                try await Task.sleep(until: started + .milliseconds(500), clock: .continuous)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-SampleData"),
                   ProcessInfo.processInfo.arguments.contains("-SlowRefreshPreview") {
                    try await Task.sleep(for: .seconds(8))
                }
                #endif
            } catch { return }
            guard !Task.isCancelled else { return }
            refreshing = false
            refreshTask = nil
        }
    }

    /// The system control's callback: its spinner stays until the owned
    /// refresh, or one already running, finishes.
    @MainActor
    private func performRefresh() async {
        startRefresh()
        await refreshTask?.value
    }
}

/// How far a deliberate pull has gone: a ring that closes at the threshold
/// and turns from muted to ink once letting go will refresh.
private struct PullProgressRing: View {
    var progress: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.rule, lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progress >= 1 ? Color.ink : Color.muted, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(2)
    }
}

/// Follows the enclosing scroll view's own pan as an added target, without
/// replacing its delegate or competing with its recognizers. Only a fresh
/// pull from the resting top can overscroll there; returning from content
/// stops at the boundary while preserving normal bottom bounce.
private struct DeliberatePullObserver: UIViewRepresentable {
    var isEnabled: Bool
    var threshold: CGFloat
    var onPull: (CGFloat) -> Void
    var onRelease: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.threshold = threshold
        context.coordinator.onPull = onPull
        context.coordinator.onRelease = onRelease
        view.setSearchEnabled(isEnabled)
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// An invisible view behind the scroll view. It looks for that scroll
    /// view only while unattached after joining a window, never per render.
    final class ProbeView: UIView {
        weak var coordinator: Coordinator?
        private var searchesLeft = 0
        private var searchEnabled = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                coordinator?.detach()
            } else if searchEnabled {
                searchesLeft = 8
                DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attachIfNeeded()
        }

        func setSearchEnabled(_ enabled: Bool) {
            searchEnabled = enabled
            guard enabled else {
                searchesLeft = 0
                coordinator?.detach()
                return
            }
            guard let window, coordinator?.isAttached(in: window) != true, searchesLeft == 0 else { return }
            // Activation or uncovering can happen without moving this page to
            // a new window. Start a fresh bounded search on that update.
            searchesLeft = 8
            DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
        }

        private func attachIfNeeded() {
            guard searchEnabled, let coordinator, let window, !bounds.isEmpty, searchesLeft > 0,
                  !coordinator.isAttached(in: window) else { return }
            searchesLeft -= 1
            if let scrollView = enclosingScrollView() {
                coordinator.attach(to: scrollView)
            } else {
                // SwiftUI may still be assembling the hierarchy.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.attachIfNeeded() }
            }
        }

        /// The scroll view this probe sits behind: from the nearest ancestor
        /// outward, the shallowest scroll view among its other subviews that
        /// covers the probe's center. Use the page's own geometry: a sheet or
        /// transition can cover it while this background view first attaches.
        private func enclosingScrollView() -> UIScrollView? {
            let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
            var child: UIView = self
            var ancestor = superview
            for _ in 0..<8 {
                guard let current = ancestor else { return nil }
                if let scrollView = current as? UIScrollView,
                   Self.isVerticalInputSurface(scrollView, windowCenter: center) {
                    return scrollView
                }
                if let match = Self.outermostScrollView(in: current, skipping: child, windowCenter: center) { return match }
                // Stay inside the controller that owns this page. Other tabs
                // can retain laid-out scroll views in the same window.
                if current.next is UIViewController { return nil }
                child = current
                ancestor = current.superview
            }
            return nil
        }

        private static func outermostScrollView(
            in root: UIView,
            skipping skipped: UIView,
            windowCenter: CGPoint
        ) -> UIScrollView? {
            var queue = root.subviews.filter { $0 !== skipped }
            var index = 0
            while index < queue.count, index < 256 {
                let view = queue[index]
                index += 1
                if let scrollView = view as? UIScrollView,
                   isVerticalInputSurface(scrollView, windowCenter: windowCenter) { return scrollView }
                queue.append(contentsOf: view.subviews)
            }
            return nil
        }

        private static func isVerticalInputSurface(_ scrollView: UIScrollView, windowCenter: CGPoint) -> Bool {
            guard !(scrollView is UITextView), scrollView.isScrollEnabled,
                  scrollView.panGestureRecognizer.isEnabled, !scrollView.isPagingEnabled,
                  scrollView.bounds.contains(scrollView.convert(windowCenter, from: nil)) else { return false }
            return scrollView.alwaysBounceVertical
                || scrollView.contentSize.height + scrollView.adjustedContentInset.top
                    + scrollView.adjustedContentInset.bottom > scrollView.bounds.height + 1
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var threshold: CGFloat = 0
        var onPull: (CGFloat) -> Void = { _ in }
        var onRelease: (Bool) -> Void = { _ in }

        private enum Phase { case clamped, pulling, settling }
        private weak var scrollView: UIScrollView?
        private var phase: Phase = .clamped
        private var reported: CGFloat = 0
        private var settleLimit: CGFloat = 0
        private var lastMomentum: CFTimeInterval = 0
        private var touchObserver: RefreshTouchOrigin?
        private var offsetObservation: NSKeyValueObservation?
        private var isClampingOffset = false

        private static let topTolerance: CGFloat = 2
        /// A touch can stop UIKit deceleration before our recognizer sees it.
        private static let restInterval: CFTimeInterval = 0.1

        func isAttached(in window: UIWindow) -> Bool {
            scrollView?.window === window
        }

        func attach(to scrollView: UIScrollView) {
            guard scrollView !== self.scrollView else { return }
            detach()
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
            self.scrollView = scrollView
            let observer = RefreshTouchOrigin { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.touchBegan(in: scrollView)
            }
            scrollView.addGestureRecognizer(observer)
            touchObserver = observer
            offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                // UIKit offset changes arrive synchronously on the UI thread;
                // deferring this clamp would expose a frame of overscroll.
                MainActor.assumeIsolated { self?.enforceTopBoundary(in: scrollView) }
            }
        }

        func detach() {
            offsetObservation?.invalidate()
            offsetObservation = nil
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
            if let touchObserver { scrollView?.removeGestureRecognizer(touchObserver) }
            touchObserver = nil
            scrollView = nil
            phase = .clamped
            reported = 0
            settleLimit = 0
            lastMomentum = 0
        }

        private func touchBegan(in scrollView: UIScrollView) {
            let overscroll = -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
            if overscroll > Self.topTolerance {
                // Grabbing a returning pull must not snap it to the top or
                // deepen it into a second refresh gesture.
                phase = .settling
                settleLimit = overscroll
            } else {
                let resting = !scrollView.isDecelerating
                    && CACurrentMediaTime() - lastMomentum > Self.restInterval
                phase = abs(overscroll) <= Self.topTolerance && resting ? .pulling : .clamped
            }
            reported = 0
        }

        private func enforceTopBoundary(in scrollView: UIScrollView) {
            guard !isClampingOffset else { return }
            let decelerating = scrollView.isDecelerating
            if decelerating { lastMomentum = CACurrentMediaTime() }
            // Leave layout, inset changes and programmatic scrolling alone.
            guard scrollView.isTracking || decelerating else { return }
            let top = -scrollView.adjustedContentInset.top
            let overscroll = top - scrollView.contentOffset.y
            switch phase {
            case .pulling:
                // Once this touch moves into content, reversing direction
                // cannot turn it into a fresh pull from the top.
                guard overscroll < -Self.topTolerance else { return }
                phase = .clamped
                if reported > 0 { reported = 0; onRelease(false) }
            case .settling:
                if overscroll <= 0 {
                    phase = .clamped
                } else if overscroll > settleLimit {
                    clamp(scrollView, toY: top - settleLimit)
                } else {
                    settleLimit = overscroll
                }
            case .clamped:
                if overscroll > 0 { clamp(scrollView, toY: top) }
            }
        }

        private func clamp(_ scrollView: UIScrollView, toY y: CGFloat) {
            isClampingOffset = true
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
            isClampingOffset = false
        }

        @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
            guard let scrollView, phase == .pulling else { return }
            let overscroll = -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
            switch pan.state {
            case .began:
                reported = 0
            case .changed:
                let distance = max(overscroll, 0)
                guard abs(distance - reported) >= 0.5 else { return }
                reported = distance
                onPull(distance)
            case .ended, .cancelled, .failed:
                phase = overscroll > 0 ? .settling : .clamped
                settleLimit = max(overscroll, 0)
                onRelease(pan.state == .ended && overscroll >= threshold)
            default:
                break
            }
        }

    }
}

/// Observes touch-down and immediately fails, leaving the scroll view's own
/// pan recognizer in control. It never delays or cancels content touches.
private final class RefreshTouchOrigin: UIGestureRecognizer {
    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }
}

/// Explicit native color keeps refresh feedback legible on every theme.
private struct RefreshSpinner: UIViewRepresentable {
    var color: Color

    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = UIColor(color)
        indicator.startAnimating()
        return indicator
    }

    func updateUIView(_ indicator: UIActivityIndicatorView, context: Context) {
        indicator.color = UIColor(color)
    }
}

private struct MainContentVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// A root presentation can hide the tab content without changing its path.
    var isMainContentVisible: Bool {
        get { self[MainContentVisibleKey.self] }
        set { self[MainContentVisibleKey.self] = newValue }
    }
}

// MARK: - Metrics tokens

enum Metrics {
    /// Horizontal page margin shared by every screen. Content aligns to it.
    static let page: CGFloat = 16
    /// Corner radius of real controls: buttons and text fields.
    static let controlRadius: CGFloat = 6
    /// Width of separators and control outlines.
    static let line: CGFloat = 1
    /// Vertical padding of an open list row.
    static let rowPadding: CGFloat = 12
    /// Space between the sections of a screen.
    static let sectionGap: CGFloat = 28
}

// MARK: - Motion
//
// Every animation goes through one of these, so Reduce Motion is decided in
// one place: selections and values change instantly, and nothing draws in.

enum Motion {
    /// Choosing an option.
    static func select(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.2)
    }

    /// A number changing to a new value.
    static func value(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.35)
    }

    /// The GPA curve drawing in from the left. A heavily damped spring, close
    /// to the legacy chart's reveal but shorter.
    static func reveal(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 1.6, dampingFraction: 0.92)
    }

    /// The GPA curve reshaping for another year or series. A timing curve
    /// rather than a spring: it never passes its target, and an interrupting
    /// change adds on from where the line is drawn, so the line stays between
    /// curves it is moving between and never overshoots a real value.
    static func morph(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.55)
    }

    /// Content replaced in place, such as another month: a brief crossfade,
    /// with anything that moves settling on the same curve. Nothing slides.
    static func replace(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
    }

    /// A pressed control's scale, both ways: a critically damped spring that
    /// starts from wherever the control is, so a quick second tap retargets.
    static func press(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1)
    }

    /// A pressed fill or dim: shown at once on touch-down, settling back on
    /// release instead of snapping off.
    static func pressFeedback(_ reduceMotion: Bool, isPressed: Bool) -> Animation? {
        isPressed ? nil : press(reduceMotion)
    }

    /// The scale of a pressed compact control. Rows never scale, and Reduce
    /// Motion keeps every control at full size.
    static func pressScale(_ reduceMotion: Bool, isPressed: Bool, to scale: CGFloat) -> CGFloat {
        isPressed && !reduceMotion ? scale : 1
    }

    /// Runs a state change with the given animation, or immediately.
    static func perform(_ animation: Animation?, _ change: () -> Void) {
        if let animation {
            withAnimation(animation, change)
        } else {
            change()
        }
    }
}

// MARK: - Typography
//
// SF Pro throughout, always from a Dynamic Type text style. Hierarchy comes
// from size and a small set of weights: semibold for headings and controls,
// medium for names and figures, regular for reading text, and light only for
// the single large figure on a screen. Figures use tabular digits.

extension Font {
    /// Numbers set in SF Pro with tabular digits.
    static func figure(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
        .system(style).weight(weight).monospacedDigit()
    }

    /// The one large figure on a screen. `size` should come from `@ScaledMetric`.
    static func display(size: CGFloat) -> Font {
        .system(size: size, weight: .light).monospacedDigit()
    }
}

// MARK: - Grade formatting
//
// One set of number formats: compact grades in lists ("96", "93.5"), one
// decimal where explicitly requested, up to two inside a course, two for GPA.

enum GradeFormat {
    /// "96" for whole numbers, "93.5" otherwise.
    static func compact(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if abs(value - value.rounded()) < 0.05 { return String(format: "%.0f", value.rounded()) }
        return String(format: "%.1f", value)
    }

    static func oneDecimal(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f", value)
    }

    /// Course-detail display only; calculations and editing retain full precision.
    static func upToTwoDecimals(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let normalized = abs(value) < 0.005 ? 0 : value
        return normalized.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    /// Course averages always show hundredths, including trailing zeros.
    static func twoDecimals(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let normalized = abs(value) < 0.005 ? 0 : value
        return normalized.formatted(.number.precision(.fractionLength(2)).grouping(.never))
    }

    static func spokenCourseGrade(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "No grade" }
        return "\(twoDecimals(value)) percent"
    }

    static func gpa(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.2f", value)
    }

    static func spoken(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "No grade" }
        return "\(compact(value)) percent"
    }

    /// "+0.42" / "−1.10" for a change between two values.
    static func signedChange(_ value: Double, digits: Int = 2) -> String {
        let magnitude = String(format: "%.\(digits)f", abs(value))
        if abs(value) < pow(10, Double(-digits)) / 2 { return magnitude }
        return (value > 0 ? "+" : "−") + magnitude
    }
}

/// Band for a 0–100 grade, using the same thresholds as the assignment grade
/// filter. Only failing grades change color; the number carries the meaning.
enum GradeTier {
    case strong, steady, caution, attention, none

    init(_ score: Double?) {
        guard let score, score.isFinite else { self = .none; return }
        switch score {
        case 80...: self = score >= 90 ? .strong : .steady
        case 70..<80: self = .caution
        default: self = .attention
        }
    }

    @MainActor var textColor: Color {
        switch self {
        case .attention: return .gradeAttention
        case .none: return .muted
        default: return .ink
        }
    }
}

extension TermLabel {
    var displayName: String {
        switch self {
        case .q1: return "Quarter 1"
        case .q2: return "Quarter 2"
        case .sm1: return "Semester 1"
        case .q3: return "Quarter 3"
        case .q4: return "Quarter 4"
        case .sm2: return "Semester 2"
        }
    }

    static let fallTerms: [TermLabel] = [.q1, .q2, .sm1]
    static let springTerms: [TermLabel] = [.q3, .q4, .sm2]
}

enum UpdatedText {
    /// "Updated 2:14 PM" today, otherwise "Updated Oct 1". Static text, no timers.
    static func describe(_ date: Date) -> String {
        "Updated \(short(date))"
    }

    /// "2:14 PM" today, otherwise "Oct 1".
    static func short(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Separators
//
// Content sits directly on the page. Rows are divided by hairlines that start
// at the content edge they belong to. Nothing is framed: figures that add up
// to a whole (the grade breakdown, the semester composition) are open rows
// and side-by-side values too.

/// A full-width hairline.
struct Rule: View {
    var color: Color?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(color ?? Color.rule)
            .frame(height: 1 / max(1, displayScale))
            .accessibilityHidden(true)
    }
}

/// A hairline between list rows, starting at the row's text edge.
struct InsetDivider: View {
    var leading: CGFloat = 0

    var body: some View {
        Rule()
            .padding(.leading, leading)
    }
}

/// Column names over figures: muted footnote text, no band.
struct TableHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityHidden(true)
    }
}

/// A label and its value.
struct GridFact: Hashable {
    var label: String
    var value: String
}

/// A muted label over a value, set openly on the page.
struct LabeledValue: View {
    var label: String
    var value: String
    var valueColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.muted)
            Text(value)
                .font(.figure(.body))
                .foregroundStyle(valueColor ?? Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

/// A section title with an optional count and trailing control.
struct SectionHeading<Trailing: View>: View {
    var title: String
    var count: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let count {
                Text(count)
                    .font(.figure(.subheadline, weight: .regular))
                    .foregroundStyle(Color.muted)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 44)
        .padding(.bottom, 2)
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(_ title: String, count: String? = nil) {
        self.init(title: title, count: count) { EmptyView() }
    }
}

// MARK: - Button styles

// Press feedback appears on touch-down and settles back on release. Each
// style animates only its own feedback modifiers, never the label's content,
// so text, focus and layout changes made by the action stay unanimated.

/// Row feedback: the whole row takes the pressed fill. No scaling.
struct RowPressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Rectangle()
                    .fill(Color.pressed)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .animation(
                        Motion.pressFeedback(reduceMotion, isPressed: configuration.isPressed),
                        value: configuration.isPressed
                    )
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// The single filled call to action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.onProminentFill : Color.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                isEnabled ? Color.prominentFill : Color.pressed,
                in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
            )
            .animation(Motion.pressFeedback(reduceMotion, isPressed: pressed)) {
                $0.opacity(pressed ? 0.78 : 1)
            }
            .animation(Motion.press(reduceMotion)) {
                $0.scaleEffect(Motion.pressScale(reduceMotion, isPressed: pressed, to: 0.98))
            }
            // Outside the scale, so the hit area keeps its full size.
            .contentShape(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
    }
}

/// A quiet secondary control: ink text on the well fill, small enough to sit
/// in a line of text. Scope buttons and the what-if Add and Reset actions use
/// it. The drawn surface is compact; the hit area is at least 44 points tall.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.ink)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(pressed ? Color.selection : Color.well)
                    .animation(Motion.pressFeedback(reduceMotion, isPressed: pressed), value: pressed)
            }
            .animation(Motion.press(reduceMotion)) {
                $0.scaleEffect(Motion.pressScale(reduceMotion, isPressed: pressed, to: 0.97))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A text action in the action color: Retry, Clear.
struct ActionTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.themeAccent)
            .multilineTextAlignment(.leading)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Motion.pressFeedback(reduceMotion, isPressed: pressed)) {
                $0.opacity(pressed ? 0.55 : 1)
            }
    }
}

// MARK: - Grade numerals

/// A grade in SF Pro with tabular figures. Only failing grades change color.
struct GradeNumber: View {
    var score: Double?
    var style: Font.TextStyle = .title2
    var showsPercent = false

    var body: some View {
        Text(GradeFormat.compact(score) + (showsPercent && score != nil ? "%" : ""))
            .font(.figure(style))
            .foregroundStyle(GradeTier(score).textColor)
            .contentTransition(.numericText(value: score ?? 0))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Choosing
//
// Every choice in the app is one family. A choice is a plain row: its name,
// an optional note beneath, an optional figure, and a check in the action
// color on the chosen row. What a screen shows (the grading term, the school
// year) is set from a scope button: the current value with a down chevron,
// which opens a short sheet of those rows sized to its content. A choice
// between two values that changes something already on screen, such as the
// chart's series, is an inline pair: two plain buttons, the chosen one on
// a quiet selection fill. No menus, segmented tracks, or tabs.

/// One option in a choice list.
struct ChoiceOption<Value: Hashable>: Identifiable {
    var value: Value
    var title: String
    var note: String?
    /// A trailing figure, such as the grade for a term.
    var detail: String?
    var spokenDetail: String?
    var identifier: String?

    var id: Value { value }
}

/// Options under an optional quiet label, such as "Fall semester".
struct ChoiceGroup<Value: Hashable> {
    var title: String?
    var options: [ChoiceOption<Value>]
}

/// The label above a group of rows: quiet sentence-case footnote text that
/// names the group. It is a heading for VoiceOver, never decoration.
struct GroupLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One choosable row. The check keeps its width when hidden so names and
/// figures stay aligned from row to row.
struct ChoiceRow: View {
    var title: String
    var note: String?
    var detail: String?
    var spokenDetail: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    if let note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Color.muted)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let detail {
                    Text(detail)
                        .font(.figure(.body, weight: .regular))
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                        .fixedSize()
                }
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.themeAccent)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(title)
        .accessibilityValue(spokenDetail ?? detail ?? "")
        .accessibilityHint(note ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Groups of choice rows set openly on the page, divided by hairlines.
struct ChoiceList<Value: Hashable>: View {
    var groups: [ChoiceGroup<Value>]
    var isSelected: (Value) -> Bool
    var choose: (Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if let title = group.title {
                    GroupLabel(title)
                        .padding(.top, index == 0 ? 4 : 20)
                } else if index > 0 {
                    Rule()
                        .padding(.vertical, 8)
                }
                ForEach(Array(group.options.enumerated()), id: \.element.id) { row, option in
                    if row > 0 { InsetDivider() }
                    ChoiceRow(
                        title: option.title,
                        note: option.note,
                        detail: option.detail,
                        spokenDetail: option.spokenDetail,
                        isSelected: isSelected(option.value)
                    ) {
                        choose(option.value)
                    }
                    .accessibilityIdentifier(option.identifier ?? option.title)
                }
            }
        }
    }
}

/// The face of a scope button: the current value and a small muted down
/// chevron, set by `QuietButtonStyle` on the well fill at the leading edge
/// of a screen's first line. Term and school year share this face.
struct ScopeButtonLabel: View {
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
        }
    }
}

/// Dims an inline choice or icon button while pressed.
struct ScopePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .animation(Motion.pressFeedback(reduceMotion, isPressed: pressed)) {
                $0.opacity(pressed ? 0.55 : 1)
            }
    }
}

/// A scope button and the sheet it opens. Choosing a row applies it and
/// closes the sheet; swiping down closes it unchanged.
struct ScopePicker<Value: Hashable>: View {
    /// Names the choice: the sheet title and the button's spoken label.
    var title: String
    var valueName: String
    var hint: String
    var identifier: String
    var groups: [ChoiceGroup<Value>]
    @Binding var selection: Value

    var onPresentationChange: (Bool) -> Void = { _ in }
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ScopeButtonLabel(value: valueName)
        }
        .buttonStyle(QuietButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(valueName)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
        .sensoryFeedback(.selection, trigger: selection)
        .sheet(isPresented: $isPresented) {
            ChoiceSheet(title: title, groups: groups, selection: $selection)
        }
        .onChange(of: isPresented) { _, presented in onPresentationChange(presented) }
    }
}

/// A short sheet of choice rows under a centered title. Its height follows
/// its content, up to the full screen at large text sizes, where the rows
/// scroll.
struct ChoiceSheet<Value: Hashable>: View {
    var title: String
    var groups: [ChoiceGroup<Value>]
    @Binding var selection: Value

    @Environment(\.dismiss) private var dismiss
    @State private var themeManager = ThemeManager.shared
    @State private var contentHeight: CGFloat?
    @ScaledMetric(relativeTo: .body) private var rowEstimate: CGFloat = 53
    @ScaledMetric(relativeTo: .footnote) private var labelEstimate: CGFloat = 40
    @ScaledMetric(relativeTo: .headline) private var titleEstimate: CGFloat = 64

    /// Close to the measured height, so the sheet opens at nearly its final
    /// size before the content has been laid out once.
    private var estimatedHeight: CGFloat {
        let rows = groups.reduce(0) { $0 + $1.options.count }
        let labels = groups.filter { $0.title != nil }.count
        return titleEstimate + CGFloat(rows) * rowEstimate + CGFloat(labels) * labelEstimate + 16
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)

                ChoiceList(groups: groups, isSelected: { $0 == selection }) { value in
                    selection = value
                    dismiss()
                }
            }
            .padding(.horizontal, Metrics.page)
            .padding(.bottom, 16)
            .background {
                // Reads the content's own height; the sheet's height never
                // changes the content's, so this settles in one pass.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.appBackground.ignoresSafeArea())
        .presentationDetents([.height(contentHeight ?? estimatedHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .tint(Color.themeAccent)
        .foregroundStyle(Color.ink)
        .preferredColorScheme(themeManager.appearance.colorScheme)
    }
}

/// Two or three values chosen in place: plain buttons, the chosen one on a
/// quiet selection fill. Each keeps the same weight so nothing shifts. The
/// fill moves to the new choice with the selection animation.
struct InlineChoice<Value: Hashable>: View {
    var label: String
    var options: [ChoiceOption<Value>]
    @Binding var selection: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var selectionFill

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ChoiceList(groups: [ChoiceGroup(title: nil, options: options)], isSelected: { $0 == selection }) { value in
                    Motion.perform(Motion.select(reduceMotion)) { selection = value }
                }
            } else {
                compactChoices
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var compactChoices: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    guard !isSelected else { return }
                    Motion.perform(Motion.select(reduceMotion)) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSelected ? Color.ink : Color.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                                    .fill(Color.selection)
                                    .matchedGeometryEffect(id: "selection", in: selectionFill)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ScopePressStyle())
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(option.identifier ?? option.title)
            }
        }
        .fixedSize()
    }
}

// MARK: - Term selector

/// The grading term shown across the app. The scope button names the
/// current term; its sheet lists each semester's two quarters and the
/// semester they make up. `grades` optionally shows each term's grade.
struct TermSelector: View {
    @Binding var selection: TermLabel
    var grades: [TermLabel: Double] = [:]
    var allowedTerms: [TermLabel] = TermLabel.allCases
    var onPresentationChange: (Bool) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScopePicker(
            title: "Grading term",
            valueName: selection.displayName,
            hint: "Shows quarters and semesters",
            identifier: "term.selector",
            groups: [
                ChoiceGroup(title: "Fall semester", options: TermLabel.fallTerms.filter(allowedTerms.contains).map(option)),
                ChoiceGroup(title: "Spring semester", options: TermLabel.springTerms.filter(allowedTerms.contains).map(option)),
            ].filter { !$0.options.isEmpty },
            selection: Binding(get: { selection }, set: { choose($0) }),
            onPresentationChange: onPresentationChange
        )
    }

    private func option(_ term: TermLabel) -> ChoiceOption<TermLabel> {
        let grade = grades[term].flatMap { $0.isFinite ? $0 : nil }
        return ChoiceOption(
            value: term,
            title: term.displayName,
            note: semesterNote(term),
            detail: grade.map { GradeFormat.compact($0) },
            spokenDetail: grade.map { GradeFormat.spoken($0) },
            identifier: "term.option.\(term.shortName)"
        )
    }

    /// Names the quarters a semester is built from.
    private func semesterNote(_ term: TermLabel) -> String? {
        switch term {
        case .sm1: return "Quarters 1 and 2 with the exam"
        case .sm2: return "Quarters 3 and 4 with the exam"
        default: return nil
        }
    }

    /// Choosing the current term again leaves it selected.
    private func choose(_ term: TermLabel) {
        guard term != selection else { return }
        Motion.perform(reduceMotion ? nil : .snappy(duration: 0.25)) {
            selection = term
        }
    }
}

// MARK: - Viewport fill

/// A vertical stack that uses the visible height of its scroll view.
/// Children keep their natural heights. When together they need less than
/// `minHeight`, the children marked `.fillsViewport()` share the difference
/// equally, each growing to at most `maxGrowth` times its natural height.
/// When they need more, nothing grows and the scroll view scrolls.
/// `minHeight` comes from outside the scroll view, so the layout never feeds
/// back into its own input.
struct ViewportFillStack: Layout {
    var minHeight: CGFloat
    var maxGrowth: CGFloat = 1.75

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max()
            ?? 0
        return CGSize(width: width, height: heights(width: width, subviews: subviews).reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for (subview, height) in zip(subviews, heights(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height
        }
    }

    private func heights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        var heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let natural = heights.reduce(0, +)
        let growing = subviews.indices.filter { subviews[$0][FillsViewportKey.self] }
        guard !growing.isEmpty, minHeight > natural else { return heights }
        let share = (minHeight - natural) / CGFloat(growing.count)
        for index in growing {
            let cap = maxGrowth.isFinite ? heights[index] * (maxGrowth - 1) : share
            heights[index] += min(share, cap)
        }
        return heights
    }
}

private struct FillsViewportKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Marks a child of `ViewportFillStack` that takes a share of unused
    /// height. The child should accept extra height, for example with
    /// `.frame(maxHeight: .infinity)`.
    func fillsViewport(_ fills: Bool = true) -> some View {
        layoutValue(key: FillsViewportKey.self, value: fills)
    }
}

// MARK: - Person names

/// The display form of a person's name from Skyward. A name that arrives in
/// a single case ("ISAAC GROMBACHER-BROWN", "karen chong") is set in
/// proper-noun case: each part after a space, hyphen, or apostrophe starts
/// with a capital, initials stay capitals, and II/III/IV stay numerals. A
/// name that already mixes cases ("McDonald", "DeLeon", "van Dyke") is kept
/// as written, since its capitalization can't be guessed. Course-title rules
/// such as acronyms never apply to people.
enum PersonName {
    static func display(_ raw: String) -> String {
        let words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let collapsed = words.joined(separator: " ")
        let hasUpper = collapsed.contains { $0.isUppercase }
        let hasLower = collapsed.contains { $0.isLowercase }
        // Mixed case is kept; so is text without letters.
        guard hasUpper != hasLower else { return collapsed }
        return words.map(word).joined(separator: " ")
    }

    private static let numerals: Set<String> = ["II", "III", "IV"]

    private static func word(_ word: String) -> String {
        let bare = word.uppercased().trimmingCharacters(in: .punctuationCharacters)
        if numerals.contains(bare) { return word.uppercased() }
        // "J", "J.", "A.J.": every part between periods is a single letter.
        let isInitials = word.split(separator: ".").allSatisfy { $0.filter(\.isLetter).count <= 1 }
        if isInitials { return word.uppercased() }

        var result = ""
        var part = ""
        for character in word {
            if character == "-" || character == "'" || character == "’" {
                result += capitalized(part) + String(character)
                part = ""
            } else {
                part.append(character)
            }
        }
        return result + capitalized(part)
    }

    private static func capitalized(_ part: String) -> String {
        guard let first = part.firstIndex(where: \.isLetter) else { return part.lowercased() }
        return part[..<first].lowercased()
            + part[first].uppercased()
            + part[part.index(after: first)...].lowercased()
    }
}

// MARK: - Control line

/// The first line of a screen: the scope control (term or school year) at
/// the leading edge and when the data was fetched at the trailing edge. A
/// failed refresh says so in the same place with a Retry action, and a line
/// beneath it explains which saved data is still shown. Saved content stays
/// on screen throughout.
struct StatusStrip<Control: View>: View {
    /// When false the line shows no refresh state at all.
    var showsRefresh = true
    var lastUpdated: Date?
    var isRefreshing = false
    var error: String?
    /// False when the page explains the failure in its own line beneath,
    /// so the strip shows only "Couldn't refresh" and Retry.
    var showsFailureDetail = true
    var onRetry: () async -> Void
    @ViewBuilder var control: () -> Control

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isRetrying = false

    private var hasControl: Bool { Control.self != EmptyView.self }
    private var isBusy: Bool { isRefreshing || isRetrying }
    private var showsStatus: Bool {
        showsRefresh && (isBusy || lastUpdated != nil || error != nil)
    }
    private var showsFailure: Bool { showsRefresh && error != nil && !isBusy }

    var body: some View {
        if hasControl || showsStatus {
            VStack(alignment: .leading, spacing: 2) {
                if dynamicTypeSize.isAccessibilitySize || !hasControl {
                    if hasControl { control() }
                    if showsStatus { status }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        control()
                            .layoutPriority(1)
                        Spacer(minLength: 8)
                        if showsStatus { status }
                    }
                }
                if showsFailure, showsFailureDetail, let error {
                    Text(failureDetail(error))
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("refresh.status")
        }
    }

    @ViewBuilder
    private var status: some View {
        if isBusy {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Updating")
            }
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        } else if showsFailure {
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Color.gradeAttention)
                        .accessibilityHidden(true)
                    Text("Couldn't refresh")
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .accessibilityElement(children: .combine)
                Button("Retry") {
                    Task {
                        guard !isRetrying else { return }
                        isRetrying = true
                        await onRetry()
                        isRetrying = false
                    }
                }
                .buttonStyle(ActionTextButtonStyle())
                .frame(minWidth: 44)
                .accessibilityLabel("Retry refresh")
                .accessibilityIdentifier("refresh.retry")
            }
        } else if let lastUpdated {
            // Proportional digits: tabular figures space the clock's colon
            // apart, and this time never changes in place.
            Text(UpdatedText.describe(lastUpdated))
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .frame(minHeight: 44)
                .accessibilityValue("Last updated \(lastUpdated.formatted(date: .abbreviated, time: .standard))")
                .accessibilityIdentifier("refresh.timestamp")
        }
    }

    private func failureDetail(_ error: String) -> String {
        let saved: String
        if let lastUpdated {
            saved = "Showing data from \(lastUpdated.formatted(date: .abbreviated, time: .shortened))."
        } else {
            saved = "Showing saved data."
        }
        let reason = error
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return reason.isEmpty ? saved : "\(reason). \(saved)"
    }
}

extension StatusStrip where Control == EmptyView {
    init(
        lastUpdated: Date?,
        isRefreshing: Bool = false,
        error: String?,
        showsFailureDetail: Bool = true,
        onRetry: @escaping () async -> Void
    ) {
        self.init(
            lastUpdated: lastUpdated,
            isRefreshing: isRefreshing,
            error: error,
            showsFailureDetail: showsFailureDetail,
            onRetry: onRetry
        ) { EmptyView() }
    }
}

// MARK: - Shared chrome

extension View {
    /// A tab's first screen: the navigation bar is hidden and `RootHeader`
    /// sits above the content in its place, so the heading never collapses,
    /// moves, or centers as the content scrolls. Screens pushed onto the
    /// stack must restore the bar with `.toolbar(.visible, for: .navigationBar)`.
    func screenTitle(_ title: String, onSettings: @escaping () -> Void) -> some View {
        navigationTitle(title)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                RootHeader(title: title, onSettings: onSettings)
            }
    }
}

/// The fixed first row of a root screen: the title at the page margin and
/// Settings at the trailing edge. Content scrolls beneath its opaque page
/// background, which also fills the status bar area.
struct RootHeader: View {
    var title: String
    var onSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.title.bold())
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("screen.heading")
            Spacer(minLength: 8)
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ScopePressStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings.button")
        }
        .padding(.leading, Metrics.page)
        // The gear's 44-point target overhangs its glyph by about 12 points,
        // so the glyph itself ends at the page margin.
        .padding(.trailing, Metrics.page - 12)
        .padding(.vertical, 4)
        // The header never scrolls away, so very large text sizes stop
        // growing it before it crowds the content.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(Color.appBackground.ignoresSafeArea(edges: .top))
        .accessibilityElement(children: .contain)
    }
}

/// Settings gear in the inline navigation bar of a pushed screen. Root
/// screens show theirs in `RootHeader`.
struct SettingsToolbarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("settings.button")
    }
}

// MARK: - Login prompt / error / empty states

struct LoginPromptView: View {
    var message: String
    var onLogin: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect Skyward")
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onLogin) {
                    Text("Connect Skyward")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
                .accessibilityIdentifier("login.prompt.connect")
                Text("Your login is kept in the iOS Keychain on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 440, alignment: .leading)
            .padding(.horizontal, Metrics.page)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A failure with nothing saved to show. Embeds inside an existing scroll view.
struct InlineErrorState: View {
    var title: String
    var message: String
    var onRetry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task {
                    guard !isRetrying else { return }
                    isRetrying = true
                    await onRetry()
                    isRetrying = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isRetrying {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                    Text(isRetrying ? "Trying again…" : "Try again")
                }
            }
            .buttonStyle(ActionTextButtonStyle())
            .disabled(isRetrying)
            .accessibilityIdentifier("error.retry")
        }
        .frame(maxWidth: 440, alignment: .leading)
    }
}

/// Full-screen version of `InlineErrorState`, set from the top of the page.
struct ErrorStateView: View {
    var title: String
    var message: String
    var onRetry: () async -> Void

    var body: some View {
        ScrollView {
            InlineErrorState(title: title, message: message, onRetry: onRetry)
                .padding(.horizontal, Metrics.page)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A valid empty result, stated plainly in sentence text.
struct EmptyStateView: View {
    var title: String
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Loading placeholders
//
// A first load shows the shape of what is coming: quiet, static bars set on
// the line boxes of the real text styles, so they scale with Dynamic Type
// and a row keeps its height when the text arrives. No shimmer or pulse.
// Each screen lays out its own placeholder rows in its loaded structure;
// the container is not interactive and is one accessibility element that
// says what is loading. Saved content is never replaced by placeholders.

/// One line of text that hasn't loaded: a bar inside the line box of
/// `font`, about as wide as `length` figures and never wider than its
/// container. It keeps the line's height and baseline, so it aligns and
/// sizes exactly like the text it stands in for.
struct SkeletonText: View {
    enum Tone {
        /// Names, titles and figures: the hairline tone, as on the ring track.
        case primary
        /// Supporting lines beneath them, one step quieter.
        case secondary
    }

    var font: Font
    var length: Int
    var tone: Tone

    @Environment(\.colorSchemeContrast) private var contrast

    init(_ font: Font, length: Int, tone: Tone = .primary) {
        self.font = font
        self.length = length
        self.tone = tone
    }

    var body: some View {
        // Hidden figures measure the real line; they are never drawn or read.
        Text(verbatim: String(repeating: "0", count: max(1, length)))
            .font(font)
            .lineLimit(1)
            .hidden()
            .overlay { SkeletonBar().fill(color) }
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch (tone, contrast == .increased) {
        case (.primary, false): return Color.rule
        case (.secondary, false): return Color.well
        case (.primary, true): return Color.muted.opacity(0.4)
        case (.secondary, true): return Color.rule
        }
    }
}

/// A bar about as tall as lowercase letters, centered in a line box, with
/// slightly rounded ends rather than a pill.
private struct SkeletonBar: Shape {
    func path(in rect: CGRect) -> Path {
        let height = max(2, (rect.height * 0.46).rounded())
        let bar = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        return Path(roundedRect: bar, cornerRadius: height * 0.3, style: .continuous)
    }
}

/// A line of a `SkeletonRow`: the text style it stands in for and its
/// approximate length in figures.
struct SkeletonLine {
    var font: Font
    var length: Int

    init(_ font: Font, _ length: Int) {
        self.font = font
        self.length = length
    }
}

/// A loading open row: stacked leading lines and optional trailing lines,
/// such as an amount over its label, on shared baselines. The first line of
/// each stack is primary and the rest secondary. At accessibility sizes the
/// trailing lines move beneath, as the loaded rows' values do. Horizontal
/// padding comes from the caller, matching its loaded rows.
struct SkeletonRow: View {
    var lines: [SkeletonLine]
    var trailing: [SkeletonLine] = []

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    stack(lines, alignment: .leading)
                    if !trailing.isEmpty { stack(trailing, alignment: .leading) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    stack(lines, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !trailing.isEmpty { stack(trailing, alignment: .trailing) }
                }
            }
        }
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func stack(_ lines: [SkeletonLine], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                SkeletonText(line.font, length: line.length, tone: index == 0 ? .primary : .secondary)
            }
        }
    }
}

// MARK: - Term picker pill

struct TermPickerPill: View {
    @Binding var selectedTerm: TermLabel
    var label = "Grading term"
    var compact = false
    var showsDescriptor = true

    @State private var showingTerms = false
    @State private var triggerWidth: CGFloat = 320

    var body: some View {
        Button {
            showingTerms = true
        } label: {
            labelContent
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { triggerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        triggerWidth = width
                    }
            }
        }
        .popover(
            isPresented: $showingTerms,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            termChoices
                .frame(width: max(triggerWidth, 280))
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Grading term, \(selectedTerm.rawValue)")
        .accessibilityHint("Shows available grading terms")
    }

    private var termChoices: some View {
        VStack(spacing: 0) {
            termSection("Fall", terms: [.q1, .q2, .sm1])
            Divider()
                .padding(.horizontal, 16)
            termSection("Spring", terms: [.q3, .q4, .sm2])
        }
        .padding(.vertical, 8)
    }

    private func termSection(_ title: String, terms: [TermLabel]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(height: 30)

            ForEach(terms) { term in
                Button {
                    selectedTerm = term
                    showingTerms = false
                } label: {
                    HStack(spacing: 12) {
                        Text(term.rawValue)
                            .foregroundStyle(.primary)
                        Spacer()
                        if term == selectedTerm {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.themeAccent)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityAddTraits(term == selectedTerm ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var labelContent: some View {
        if !showsDescriptor {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.themeAccent)
                Text(selectedTerm.rawValue)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        } else if compact {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.themeAccent)
                Text(selectedTerm.shortName)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.themeAccent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selectedTerm.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
    }

}

// MARK: - Grade progress

struct GradeProgressRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var score: Double?
    var size: CGFloat = 44

    private var progress: Double {
        min(max((score ?? 0) / 100, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ringHighlight, lineWidth: 4)

            if score != nil {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.themeAccent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: progress)
            }

            Text(score.map { String(format: "%.0f", $0) } ?? "--")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(score == nil ? Color.secondary : Color.highlightText)
                .contentTransition(.numericText(value: score ?? 0))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

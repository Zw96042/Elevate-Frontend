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

struct RowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Login prompt / error states

struct LoginPromptView: View {
    var message: String
    var onLogin: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 34, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.highlightText)
                        .frame(width: 68, height: 68)
                        .background(Color.ringHighlight, in: Circle())
                    VStack(spacing: 8) {
                        Text("Connect Skyward")
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(message)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: onLogin) {
                        Label("Open settings", systemImage: "gearshape")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(Color.prominentFill, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(RowPressStyle())
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct ErrorStateView: View {
    var title: String
    var message: String
    var onRetry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 38, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                        .frame(width: 80, height: 80)
                        .background(.red.opacity(0.1), in: Circle())
                    Text(title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
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
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(Color.prominentFill)
                    .disabled(isRetrying)
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct StaleDataBanner: View {
    var lastUpdated: Date?
    var onRetry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Showing saved data", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(updateDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(isRetrying ? "Trying again…" : "Try again") {
                Task {
                    guard !isRetrying else { return }
                    isRetrying = true
                    await onRetry()
                    isRetrying = false
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .disabled(isRetrying)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var updateDescription: String {
        guard let lastUpdated else {
            return "Skyward couldn't refresh. The last successful update time isn't available."
        }
        return "Skyward couldn't refresh. Last updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))."
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.highlightText)
                .frame(width: 64, height: 64)
                .background(Color.ringHighlight, in: Circle())
            Text(title)
                .font(.headline)
                .padding(.top, 6)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
    }
}

// MARK: - Skeleton shimmer

struct SkeletonRow: View {
    var height: CGFloat = 76

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Color.skeletonFill).frame(width: 152, height: 14)
                Capsule().fill(Color.skeletonFill.opacity(0.65)).frame(width: 104, height: 10)
            }
            Spacer()
            Capsule().fill(Color.skeletonFill.opacity(0.75)).frame(width: 42, height: 18)
        }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)
        }
        .accessibilityHidden(true)
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

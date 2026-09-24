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

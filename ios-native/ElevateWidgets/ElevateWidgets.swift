import WidgetKit
import SwiftUI

/// The gallery opens with the widgets that show no grades. Those that do
/// follow, each saying so in its description.
@main
struct ElevateWidgetBundle: WidgetBundle {
    var body: some Widget {
        MissingAssignmentsWidget()
        InboxWidget()
        SchoolPulseWidget()
        GPAWidget()
        GPATrendWidget()
        GradesWidget()
        RecentGradesWidget()
    }
}

// MARK: - Timeline plumbing (one provider feeds every widget)

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?      // nil ⇔ app hasn't loaded data yet
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    // The extension can outlive a theme change in the app, so each request
    // adopts the saved theme on the main actor, then completes once.

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        let isPreview = context.isPreview
        Task { @MainActor in
            ThemeManager.shared.reloadSavedTheme()
            let snapshot = isPreview
                ? (WidgetSnapshotStore.load() ?? .placeholder)
                : WidgetSnapshotStore.load()
            completion(SnapshotEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        Task { @MainActor in
            ThemeManager.shared.reloadSavedTheme()
            let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshotStore.load())
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }
}

// MARK: - Freshness
//
// A section is out of date when it hasn't refreshed in six hours or its time
// is unknown, and partial when its last refresh didn't load all of it. Each
// widget sets the note in its own layout, so it never covers content.

private enum Freshness: Equatable, Sendable {
    case current
    case partial(updatedAt: Date?, isOutdated: Bool)
    case outdated(updatedAt: Date?)

    private static let staleAge: TimeInterval = 6 * 60 * 60

    init(snapshot: WidgetSnapshot?, section: WidgetSnapshot.SectionStatus?, now: Date = Date()) {
        guard let snapshot else {
            self = .current
            return
        }
        guard let section else {
            self = now.timeIntervalSince(snapshot.generatedAt) > Self.staleAge
                ? .outdated(updatedAt: snapshot.generatedAt)
                : .current
            return
        }
        if !section.isComplete {
            self = .partial(updatedAt: section.updatedAt, isOutdated: section.updatedAt.map { now.timeIntervalSince($0) > Self.staleAge } ?? true)
            return
        }
        guard let updatedAt = section.updatedAt,
              now.timeIntervalSince(updatedAt) <= Self.staleAge else {
            self = .outdated(updatedAt: section.updatedAt)
            return
        }
        self = .current
    }

    var isStale: Bool { shortText != nil }

    var isPartial: Bool {
        if case .partial = self { return true }
        return false
    }

    /// Only out-of-date notes are shown; completeness remains internal.
    var shortText: String? {
        switch self {
        case .current: return nil
        case .partial(_, let outdated): return outdated ? "Out of date" : nil
        case .outdated: return "Out of date"
        }
    }

    /// Where there's room, with when the data is from.
    var text: String? {
        switch self {
        case .current:
            return nil
        case .partial(let date, true):
            return date.map { "Last updated \(Self.describe($0))" } ?? "Out of date"
        case .partial: return nil
        case .outdated(let date):
            return date.map { "Last updated \(Self.describe($0))" } ?? "Out of date"
        }
    }

    var spoken: String? {
        switch self {
        case .current:
            return nil
        case .partial(let date, true):
            return "Data is out of date" + (date.map { ", last updated \(Self.describe($0))" } ?? "")
        case .partial: return nil
        case .outdated(let date):
            return "Data is out of date" + (date.map { ", last updated \(Self.describe($0))" } ?? "")
        }
    }

    /// Marks the lock screen layouts too small for the note.
    var symbol: String? {
        switch self {
        case .current: return nil
        case .partial(_, let outdated): return outdated ? "clock" : nil
        case .outdated: return "clock"
        }
    }

    /// "9:14 AM" today, otherwise "Oct 1". Static text, no timers.
    private static func describe(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private struct FreshnessKey: EnvironmentKey {
    static let defaultValue = Freshness.current
}

extension EnvironmentValues {
    fileprivate var snapshotFreshness: Freshness {
        get { self[FreshnessKey.self] }
        set { self[FreshnessKey.self] = newValue }
    }
}

/// Hands each widget the freshness of the section it shows.
private struct SnapshotFreshnessModifier: ViewModifier {
    var snapshot: WidgetSnapshot?
    var section: WidgetSnapshot.SectionStatus?

    func body(content: Content) -> some View {
        content.environment(
            \.snapshotFreshness,
            Freshness(snapshot: snapshot, section: section)
        )
    }
}

private func combinedStatus(
    _ first: WidgetSnapshot.SectionStatus,
    _ second: WidgetSnapshot.SectionStatus
) -> WidgetSnapshot.SectionStatus {
    let updatedAt: Date?
    if let firstDate = first.updatedAt, let secondDate = second.updatedAt {
        updatedAt = min(firstDate, secondDate)
    } else {
        updatedAt = nil
    }
    return WidgetSnapshot.SectionStatus(
        updatedAt: updatedAt,
        isComplete: first.isComplete && second.isComplete
    )
}

// MARK: - Color roles
//
// Full-color widgets use the theme's composed roles. Tinted, clear, and lock
// screen renderings drop the theme page, so text falls back to the system's
// primary and secondary levels there instead of ink meant for that page.

@MainActor
private struct Tone {
    var mode: WidgetRenderingMode

    private var isFullColor: Bool { mode == .fullColor }

    var ink: Color { isFullColor ? Color.ink : Color.primary }
    /// Widget titles and the latest point on a chart: the theme's action color.
    var accent: Color { isFullColor ? Color.themeAccent : Color.primary }
    var muted: Color { isFullColor ? Color.muted : Color.secondary }
    var rule: Color { isFullColor ? Color.rule : Color.secondary.opacity(0.4) }
    var chartLine: Color { isFullColor ? Color.chartLine : Color.primary }
    var chartFill: Color { isFullColor ? Color.chartFill : Color.primary.opacity(0.2) }
    var attention: Color { isFullColor ? Color.gradeAttention : Color.primary }
    var warning: Color { isFullColor ? Color.gradeWarning : Color.secondary }

    /// Only grades below passing change color; the number carries the rest.
    func grade(_ percent: Double?) -> Color {
        guard let percent, percent.isFinite else { return muted }
        return percent < 70 ? attention : ink
    }
}

private struct WidgetBackground: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryWidgetBackground()
        case .accessoryInline, .accessoryRectangular:
            Color.clear
        default:
            Color.appBackground
        }
    }
}

/// The app's Light or Dark choice, on full-color widgets that show the theme
/// page. System follows the device; tinted, clear, lock screen, and StandBy
/// renderings keep the system's appearance so they stay legible.
@MainActor
private struct AppAppearance: ViewModifier {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, chosenScheme ?? systemScheme)
    }

    private var chosenScheme: ColorScheme? {
        guard renderingMode == .fullColor, showsBackground else { return nil }
        switch family {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular:
            return nil
        default:
            return ThemeManager.shared.appearance.colorScheme
        }
    }
}

extension View {
    /// The theme page behind a widget, both in the app's chosen appearance.
    fileprivate func themedWidgetContainer() -> some View {
        modifier(AppAppearance())
            .containerBackground(for: .widget) {
                WidgetBackground().modifier(AppAppearance())
            }
    }
}

// MARK: - Type and formats
//
// SF Pro from Dynamic Type styles: semibold for titles and the one large
// figure, medium for other figures, and regular for reading text.

extension Font {
    fileprivate static func figure(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style).weight(weight).monospacedDigit()
    }

    /// The one large figure. `size` comes from `@ScaledMetric`.
    fileprivate static func display(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).monospacedDigit()
    }
}

private enum Format {
    static func gpa(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// "96" for whole numbers, "93.5" otherwise; bonus above 100 is kept.
    static func grade(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if abs(value - value.rounded()) < 0.05 { return String(format: "%.0f", value.rounded()) }
        return String(format: "%.1f", value)
    }

    /// "+0.42" or "−1.10".
    static func change(_ value: Double) -> String {
        let magnitude = String(format: "%.2f", abs(value))
        if abs(value) < 0.005 { return magnitude }
        return (value > 0 ? "+" : "−") + magnitude
    }

    static func spokenChange(_ value: Double) -> String {
        if abs(value) < 0.005 { return "unchanged" }
        return "\(value > 0 ? "up" : "down") \(String(format: "%.2f", abs(value)))"
    }

    /// Terms from the snapshot ("Q1", "SM1") and the GPA table ("RC1", "PR3").
    static func termName(_ code: String) -> String {
        let upper = code.uppercased()
        switch upper {
        case "Q1", "RC1": return "Quarter 1"
        case "Q2", "RC2": return "Quarter 2"
        case "Q3", "RC3": return "Quarter 3"
        case "Q4", "RC4": return "Quarter 4"
        case "SM1", "S1": return "Semester 1"
        case "SM2", "S2": return "Semester 2"
        case "FIN": return "Final"
        default:
            if upper.hasPrefix("PR"), let number = Int(upper.dropFirst(2)) {
                return "Progress report \(number)"
            }
            return code
        }
    }

    /// "Q1", "P3": the app's short names for the ends of the chart.
    static func termShort(_ code: String) -> String {
        let upper = code.uppercased()
        if upper.hasPrefix("RC"), let number = Int(upper.dropFirst(2)) { return "Q\(number)" }
        if upper.hasPrefix("PR"), let number = Int(upper.dropFirst(2)) { return "P\(number)" }
        return code
    }

    /// Skyward's "M/d/yy" as "Jun 10"; anything else is shown as reported.
    static func date(_ raw: String, now: Date = Date()) -> String {
        let parts = raw.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[0]), (1...31).contains(parts[1]) else {
            return raw
        }
        var components = DateComponents()
        components.month = parts[0]
        components.day = parts[1]
        components.year = parts[2] < 100 ? 2000 + parts[2] : parts[2]
        let calendar = Calendar.current
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == parts[1] else { return raw }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits))
    }

    /// A percentage for "94" or "47/50", used only to flag failing grades.
    static func percent(_ gradeText: String) -> Double? {
        let parts = gradeText.split(separator: "/")
        if parts.count == 2,
           let earned = Double(parts[0].trimmingCharacters(in: .whitespaces)),
           let total = Double(parts[1].trimmingCharacters(in: .whitespaces)),
           total > 0 {
            return earned / total * 100
        }
        return Double(gradeText.trimmingCharacters(in: .whitespaces))
    }

    /// A sender's name in proper-noun case when Skyward sends it in a single
    /// case; mixed-case names are kept as written. Mirrors the app's
    /// `PersonName`, which the extension can't import.
    static func person(_ raw: String) -> String {
        let words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let collapsed = words.joined(separator: " ")
        let hasUpper = collapsed.contains { $0.isUppercase }
        let hasLower = collapsed.contains { $0.isLowercase }
        guard hasUpper != hasLower else { return collapsed }
        return words.map(personWord).joined(separator: " ")
    }

    private static func personWord(_ word: String) -> String {
        let bare = word.uppercased().trimmingCharacters(in: .punctuationCharacters)
        if ["II", "III", "IV"].contains(bare) { return word.uppercased() }
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

/// The most rows that fit, from `maximum` down to one, so rows keep their
/// size across widget sizes and text sizes instead of shrinking or clipping.
/// Give it layout priority over the spacer below it.
private struct FittingRows<Content: View>: View {
    let maximum: Int
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(max(maximum, 1))
            content(max(maximum - 1, 1))
            content(max(maximum - 2, 1))
            content(max(maximum - 3, 1))
            content(1)
        }
    }
}

/// Rows stacked at least `spacing` apart, with the gaps growing up to
/// `maxSpacing` to take the height offered, so a list gains a little air
/// rather than ending on blank space. Hairlines count as rows here.
private struct SpreadRows: Layout {
    var spacing: CGFloat
    var maxSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).height }
        let gaps = CGFloat(max(subviews.count - 1, 0))
        let natural = heights.reduce(0, +) + spacing * gaps
        let width = proposal.width
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max()
            ?? 0
        guard gaps > 0, let offered = proposal.height, offered.isFinite else {
            return CGSize(width: width, height: natural)
        }
        let tallest = heights.reduce(0, +) + maxSpacing * gaps
        return CGSize(width: width, height: max(natural, min(offered, tallest)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)) }
        let gaps = CGFloat(max(subviews.count - 1, 1))
        let even = (bounds.height - sizes.map(\.height).reduce(0, +)) / gaps
        let gap = min(max(spacing, even), max(spacing, maxSpacing))
        var y = bounds.minY
        for (subview, size) in zip(subviews, sizes) {
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                proposal: ProposedViewSize(width: bounds.width, height: size.height)
            )
            y += size.height + gap
        }
    }
}

/// The first `rows` items, divided by hairlines, opening slightly to the
/// height they are given (see `SpreadRows`). Pass `fills: false` where two
/// lists share the height, so each keeps its natural rhythm.
private struct RuledList<Item, Row: View>: View {
    let items: [Item]
    let rows: Int
    let tone: Tone
    var spacing: CGFloat = 5
    var fills = true
    @ViewBuilder let row: (Item) -> Row

    /// How far each side of a hairline may open.
    private static var extraAir: CGFloat { 3 }

    var body: some View {
        let shown = Array(items.prefix(rows))
        SpreadRows(spacing: spacing, maxSpacing: fills ? spacing + Self.extraAir : spacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, item in
                if index > 0 { Hairline(tone: tone) }
                row(item)
            }
        }
    }
}

// MARK: - GPA movement

private struct GPAChange {
    var value: Double
    /// The table key of the term before the latest one.
    var since: String

    init?(_ snapshot: WidgetSnapshot) {
        guard let history = snapshot.gpaHistory, history.count >= 2 else { return nil }
        value = history[history.count - 1].weighted - history[history.count - 2].weighted
        since = history[history.count - 2].term
    }

    var longText: String { "\(Format.change(value)) since \(Format.termName(since))" }
    var shortText: String { "\(Format.change(value)) since \(Format.termShort(since))" }
    var spoken: String { "\(Format.spokenChange(value)) since \(Format.termName(since))" }
}

private func gpaTrendAccessibilityValue(_ history: [WidgetSnapshot.GPAHistoryPoint]) -> String {
    guard let first = history.first, let last = history.last else { return "No GPA history" }
    let series = history
        .map { "\(Format.termName($0.term)) \(Format.gpa($0.weighted))" }
        .joined(separator: ", ")
    return "\(history.count) terms, from \(Format.gpa(first.weighted)) in \(Format.termName(first.term)) "
        + "to \(Format.gpa(last.weighted)) in \(Format.termName(last.term)). \(series)"
}

/// The GPA trend after the app's chart: every segment is a cubic Bézier with
/// control points at 30% and 70% of its width, each at the height of its
/// nearer end, so tangents are flat at every term and the curve never
/// overshoots a real value. The range is never less than ten points tall, so
/// a fraction-of-a-point change doesn't fill the chart.
private struct TrendCurve {
    let points: [CGPoint]
    let size: CGSize

    private static let verticalPadding: CGFloat = 0.1
    private static let minimumSpan: Double = 10

    init(values: [Double], size: CGSize, inset: CGFloat = 2) {
        self.size = size
        let range = Self.range(of: values)
        let span = range.upperBound - range.lowerBound
        let width = max(size.width - inset * 2, 1)
        // Room for the end dot at the extremes of a short chart.
        let top = max(size.height * Self.verticalPadding, 4)
        let plotHeight = max(size.height - top * 2, 1)
        let steps = CGFloat(max(values.count - 1, 1))
        points = values.enumerated().map { index, value in
            let fraction = span > 0 ? (range.upperBound - value) / span : 0.5
            return CGPoint(
                x: inset + width * CGFloat(index) / steps,
                y: top + plotHeight * CGFloat(fraction)
            )
        }
    }

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
                let width = end.x - start.x
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x + width * 0.3, y: start.y),
                    control2: CGPoint(x: start.x + width * 0.7, y: end.y)
                )
            }
        }
    }

    var area: Path {
        var path = line
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// A short curve with a fading wash and nothing else. Its parent describes
/// the series to VoiceOver.
private struct TrendChart: View {
    let values: [Double]
    let tone: Tone

    var body: some View {
        GeometryReader { proxy in
            let curve = TrendCurve(values: values, size: proxy.size, inset: 4)
            ZStack {
                curve.area
                    .fill(LinearGradient(
                        colors: [tone.chartFill, tone.chartFill.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                curve.line
                    .stroke(tone.chartLine, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .widgetAccentable()
                if let last = curve.points.last {
                    Circle()
                        .fill(tone.chartLine)
                        .frame(width: 7, height: 7)
                        .position(last)
                        .widgetAccentable()
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shared parts

extension View {
    fileprivate func widgetPage() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct FreshnessNote: View {
    var compact = false

    @Environment(\.snapshotFreshness) private var freshness
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let text = compact ? freshness.shortText : freshness.text {
            Text(text)
                .font(.caption)
                .foregroundStyle(Tone(mode: renderingMode).warning)
                .lineLimit(1)
                .accessibilityLabel(freshness.spoken ?? text)
        }
    }
}

/// The first line of a widget: what it shows at the leading edge, and at the
/// trailing edge either context or, when the data isn't current, the note.
private struct WidgetHeading: View {
    var title: String
    /// Used when `title` doesn't fit at larger text sizes.
    var shortTitle: String? = nil
    var detail: String? = nil
    /// Small widgets set the note lower down, where it has room.
    var showsFreshness = true

    @Environment(\.snapshotFreshness) private var freshness
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let tone = Tone(mode: renderingMode)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                Text(title)
                    .fixedSize()
                Text(shortTitle ?? title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tone.accent)
            .widgetAccentable()
            .layoutPriority(1)
            Spacer(minLength: 0)
            if showsFreshness && freshness.isStale {
                ViewThatFits(in: .horizontal) {
                    FreshnessNote()
                    FreshnessNote(compact: true)
                }
            } else if let detail {
                // Hidden rather than clipped when the title needs the room.
                ViewThatFits(in: .horizontal) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(tone.muted)
                        .lineLimit(1)
                        .fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }
        }
    }
}

private struct Hairline: View {
    let tone: Tone
    var vertical = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let width = 1 / max(displayScale, 1)
        Rectangle()
            .fill(tone.rule)
            .frame(width: vertical ? width : nil, height: vertical ? nil : width)
            .accessibilityHidden(true)
    }
}

/// A sentence where a list would be: what's absent, and what to do.
private struct WidgetMessage: View {
    var title: String
    var detail: String? = nil

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let tone = Tone(mode: renderingMode)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tone.ink)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(tone.muted)
            }
        }
        .lineLimit(3)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A widget with nothing to show yet: its heading, then the message.
private struct WidgetEmptyState: View {
    var heading: String
    var headingDetail: String? = nil
    var title: String
    var detail: String? = nil

    @Environment(\.widgetFamily) private var family

    var body: some View {
        let isSmall = family == .systemSmall
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(title: heading, detail: headingDetail, showsFreshness: !isSmall)
            if isSmall { Spacer(minLength: 6) }
            WidgetMessage(title: title, detail: detail)
                .padding(.top, isSmall ? 0 : 10)
            if isSmall {
                FreshnessNote(compact: true)
                    .padding(.top, 4)
            } else {
                Spacer(minLength: 0)
            }
        }
        .widgetPage()
    }
}

/// Shown before the app has saved anything for widgets.
struct NoDataView: View {
    var heading: String
    var subject = "grades"

    var body: some View {
        WidgetEmptyState(heading: heading, title: "Open Elevate to load your \(subject)")
    }
}

/// An assignment as it reads in the app: its name, then class and date.
private struct AssignmentRow<Trailing: View>: View {
    let item: WidgetSnapshot.AssignmentItem
    let tone: Tone
    @ViewBuilder var trailing: () -> Trailing

    @ViewBuilder
    var body: some View {
        if let url = item.assignmentURL {
            Link(destination: url) { content }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name.isEmpty ? "Untitled assignment" : item.name)
                    .font(.subheadline)
                    .foregroundStyle(tone.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(tone.muted)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let date = Format.date(item.date)
        return date.isEmpty ? item.className : "\(item.className), \(date)"
    }
}

extension AssignmentRow where Trailing == EmptyView {
    init(item: WidgetSnapshot.AssignmentItem, tone: Tone) {
        self.init(item: item, tone: tone) { EmptyView() }
    }
}

/// A message as it reads in Inbox: its subject, then sender and date.
private struct MessageRow: View {
    let message: WidgetSnapshot.MessageItem
    let tone: Tone

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(message.subject.isEmpty ? "No subject" : message.subject)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tone.ink)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.person(message.from))
                Spacer(minLength: 8)
                Text(Format.date(message.date))
            }
            .font(.footnote)
            .foregroundStyle(tone.muted)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - GPA widget

struct GPAWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GPAWidget", provider: SnapshotProvider()) { entry in
            GPAWidgetView(entry: entry)
                .themedWidgetContainer()
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://gpa"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedBaseStatus
                ))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .configurationDisplayName("GPA")
        .description("Shows your weighted and unweighted GPA for the current term.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct GPAWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            GPAInlineView(snapshot: entry.snapshot)
        case .accessoryCircular:
            GPACircularView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            GPARectangularView(snapshot: entry.snapshot)
        default:
            GPASmallView(snapshot: entry.snapshot)
        }
    }
}

/// The same reading as the GPA line on Courses: the kind and term on the
/// title line, weighted large at the foot, unweighted beneath.
private struct GPASmallView: View {
    let snapshot: WidgetSnapshot?

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.snapshotFreshness) private var freshness
    @ScaledMetric(relativeTo: .largeTitle) var figureSize: CGFloat = 40

    var body: some View {
        let tone = Tone(mode: renderingMode)
        if let snapshot {
            if let lead = snapshot.weightedGPA ?? snapshot.unweightedGPA {
                let isWeighted = snapshot.weightedGPA != nil
                VStack(alignment: .leading, spacing: 0) {
                    WidgetHeading(
                        title: isWeighted ? "Weighted GPA" : "Unweighted GPA",
                        shortTitle: "GPA",
                        detail: snapshot.termShortName,
                        showsFreshness: false
                    )
                    Spacer(minLength: 4)
                    Text(Format.gpa(lead))
                        .font(.display(size: figureSize))
                        .foregroundStyle(tone.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .widgetAccentable()
                    if isWeighted, let unweighted = snapshot.unweightedGPA {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("Unweighted")
                                .foregroundStyle(tone.muted)
                            Text(Format.gpa(unweighted))
                                .font(.figure(.footnote, weight: .medium))
                                .foregroundStyle(tone.ink)
                        }
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                    FreshnessNote(compact: true)
                }
                .widgetPage()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(snapshot, lead: lead, isWeighted: isWeighted))
            } else {
                WidgetEmptyState(
                    heading: "GPA",
                    headingDetail: snapshot.termShortName,
                    title: freshness.isPartial ? "GPA unavailable" : "No GPA yet",
                    detail: freshness.isPartial
                        ? "Some grades didn't load."
                        : "It appears once \(Format.termName(snapshot.termShortName)) has grades."
                )
            }
        } else {
            NoDataView(heading: "GPA")
        }
    }

    private func spoken(_ snapshot: WidgetSnapshot, lead: Double, isWeighted: Bool) -> String {
        let parts: [String?] = [
            "\(isWeighted ? "Weighted" : "Unweighted") GPA \(Format.gpa(lead)), \(Format.termName(snapshot.termShortName))",
            isWeighted ? snapshot.unweightedGPA.map { "Unweighted \(Format.gpa($0))" } : nil,
            freshness.spoken,
        ]
        return parts.compactMap { $0 }.joined(separator: ". ")
    }
}

private struct GPAInlineView: View {
    let snapshot: WidgetSnapshot?

    @Environment(\.snapshotFreshness) private var freshness

    var body: some View {
        if let snapshot {
            if let value = snapshot.weightedGPA ?? snapshot.unweightedGPA {
                let text = "\(snapshot.termShortName) GPA \(Format.gpa(value))"
                Group {
                    if let symbol = freshness.symbol {
                        Label(text, systemImage: symbol)
                    } else {
                        Text(text)
                    }
                }
                .accessibilityLabel(spokenGPA(snapshot, value: value))
            } else {
                Group {
                    if let symbol = freshness.symbol {
                        Label(freshness.isPartial ? "GPA unavailable" : "No \(snapshot.termShortName) GPA yet", systemImage: symbol)
                    } else {
                        Text(freshness.isPartial ? "GPA unavailable" : "No \(snapshot.termShortName) GPA yet")
                    }
                }
                .accessibilityLabel([freshness.isPartial ? "GPA unavailable" : "No \(Format.termName(snapshot.termShortName)) GPA yet", freshness.spoken].compactMap { $0 }.joined(separator: ". "))
            }
        } else {
            Text("Open Elevate for GPA")
        }
    }

    private func spokenGPA(_ snapshot: WidgetSnapshot, value: Double) -> String {
        let kind = snapshot.weightedGPA != nil ? "weighted" : "unweighted"
        let reading = "\(Format.termName(snapshot.termShortName)) \(kind) GPA \(Format.gpa(value))"
        let parts: [String?] = [reading, freshness.spoken]
        return parts.compactMap { $0 }.joined(separator: ". ")
    }
}

/// A clear number with a small label; no ring.
private struct GPACircularView: View {
    let snapshot: WidgetSnapshot?

    @Environment(\.snapshotFreshness) private var freshness

    var body: some View {
        if let snapshot {
            if let value = snapshot.weightedGPA ?? snapshot.unweightedGPA {
                VStack(spacing: 0) {
                    HStack(spacing: 2) {
                        Text("GPA")
                        if let symbol = freshness.symbol {
                            Image(systemName: symbol)
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    Text(Format.gpa(value))
                        .font(.figure(.body, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .widgetAccentable()
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(snapshot, value: value))
            } else {
                VStack(spacing: 2) {
                    if let symbol = freshness.symbol { Image(systemName: symbol) }
                    Text(freshness.isPartial ? "Unavailable" : "No GPA")
                }
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([freshness.isPartial ? "GPA unavailable" : "No \(Format.termName(snapshot.termShortName)) GPA yet", freshness.spoken].compactMap { $0 }.joined(separator: ". "))
            }
        } else {
            Image(systemName: "graduationcap")
                .font(.title3)
                .accessibilityLabel("Open Elevate to load your GPA")
        }
    }

    private func spoken(_ snapshot: WidgetSnapshot, value: Double) -> String {
        let kind = snapshot.weightedGPA != nil ? "Weighted" : "Unweighted"
        let reading = "\(kind) GPA \(Format.gpa(value)), \(Format.termName(snapshot.termShortName))"
        let parts: [String?] = [reading, freshness.spoken]
        return parts.compactMap { $0 }.joined(separator: ". ")
    }
}

/// The term, then weighted and unweighted side by side.
private struct GPARectangularView: View {
    let snapshot: WidgetSnapshot?

    @Environment(\.snapshotFreshness) private var freshness

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 1) {
                heading(snapshot)
                if snapshot.weightedGPA != nil || snapshot.unweightedGPA != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        if let weighted = snapshot.weightedGPA {
                            figure(weighted, label: "Weighted")
                                .widgetAccentable()
                        }
                        if let unweighted = snapshot.unweightedGPA {
                            figure(unweighted, label: "Unweighted")
                        }
                    }
                } else {
                    Text(freshness.isPartial ? "Some grades didn't load" : "No GPA yet this term")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text("GPA")
                    .font(.headline)
                Text("Open Elevate to load your grades")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func heading(_ snapshot: WidgetSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            headingLine("\(Format.termName(snapshot.termShortName)) GPA", showsText: true)
            headingLine("\(snapshot.termShortName) GPA", showsText: true)
            headingLine("\(snapshot.termShortName) GPA", showsText: false)
        }
    }

    private func headingLine(_ title: String, showsText: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            if showsText, let note = freshness.shortText {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel(freshness.spoken ?? note)
            } else if let symbol = freshness.symbol {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(freshness.spoken ?? "")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func figure(_ value: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Format.gpa(value))
                .font(.figure(.title3, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - GPA trend widget

struct GPATrendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GPATrendWidget", provider: SnapshotProvider()) { entry in
            GPATrendWidgetView(entry: entry)
                .themedWidgetContainer()
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://gpa"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedBaseStatus
                ))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .configurationDisplayName("GPA Trend")
        .description("Shows your weighted GPA and how it has moved across recent terms.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GPATrendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.snapshotFreshness) private var freshness
    @ScaledMetric(relativeTo: .title) var figureSize: CGFloat = 30
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot,
           let history = snapshot.gpaHistory,
           history.count > 1,
           let latest = history.last {
            Group {
                if family == .systemSmall {
                    small(snapshot: snapshot, history: history, latest: latest)
                } else {
                    medium(snapshot: snapshot, history: history, latest: latest)
                }
            }
            .widgetPage()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weighted GPA trend")
            .accessibilityValue(spokenValue(snapshot: snapshot, history: history))
        } else if entry.snapshot != nil {
            WidgetEmptyState(
                heading: "GPA trend",
                title: freshness.isPartial ? "GPA history unavailable" : "Not enough terms yet",
                detail: freshness.isPartial
                    ? "Some grades didn't load."
                    : "The trend appears after two graded terms."
            )
        } else {
            NoDataView(heading: "GPA trend")
        }
    }

    private var tone: Tone { Tone(mode: renderingMode) }

    private func small(
        snapshot: WidgetSnapshot,
        history: [WidgetSnapshot.GPAHistoryPoint],
        latest: WidgetSnapshot.GPAHistoryPoint
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(title: "GPA trend", showsFreshness: false)
            latestFigure(latest)
                .padding(.top, 2)
            if freshness.isStale {
                FreshnessNote(compact: true)
            } else if let change = GPAChange(snapshot) {
                Text(change.shortText)
                    .font(.figure(.caption))
                    .foregroundStyle(tone.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            TrendChart(values: history.map(\.weighted), tone: tone)
                .frame(minHeight: 24, maxHeight: .infinity)
                .padding(.top, 6)
        }
    }

    private func medium(
        snapshot: WidgetSnapshot,
        history: [WidgetSnapshot.GPAHistoryPoint],
        latest: WidgetSnapshot.GPAHistoryPoint
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                latestFigure(latest)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Weighted GPA")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tone.accent)
                        .widgetAccentable()
                    if let change = GPAChange(snapshot) {
                        ViewThatFits(in: .horizontal) {
                            Text(change.longText)
                            Text(change.shortText)
                        }
                        .font(.figure(.footnote))
                        .foregroundStyle(tone.muted)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if freshness.isStale {
                    ViewThatFits(in: .horizontal) {
                        FreshnessNote()
                        FreshnessNote(compact: true)
                    }
                }
            }
            TrendChart(values: history.map(\.weighted), tone: tone)
                .frame(minHeight: 24, maxHeight: .infinity)
            if let first = history.first {
                ViewThatFits(in: .horizontal) {
                    endpoints(first, latest, name: Format.termName)
                    endpoints(first, latest, name: Format.termShort)
                }
            }
        }
    }

    private func latestFigure(_ latest: WidgetSnapshot.GPAHistoryPoint) -> some View {
        Text(Format.gpa(latest.weighted))
            .font(.display(size: figureSize))
            .foregroundStyle(tone.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .widgetAccentable()
    }

    /// The first and latest terms under the ends of the curve.
    private func endpoints(
        _ first: WidgetSnapshot.GPAHistoryPoint,
        _ last: WidgetSnapshot.GPAHistoryPoint,
        name: (String) -> String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            endpoint(first, name: name)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            endpoint(last, name: name)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    private func endpoint(
        _ point: WidgetSnapshot.GPAHistoryPoint,
        name: (String) -> String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name(point.term))
                .foregroundStyle(tone.muted)
            Text(Format.gpa(point.weighted))
                .font(.figure(.caption, weight: .medium))
                .foregroundStyle(tone.ink)
        }
    }

    private func spokenValue(snapshot: WidgetSnapshot, history: [WidgetSnapshot.GPAHistoryPoint]) -> String {
        let parts: [String?] = [
            GPAChange(snapshot).map { "Latest \($0.spoken)" },
            gpaTrendAccessibilityValue(history),
            freshness.spoken,
        ]
        return parts.compactMap { $0 }.joined(separator: ". ")
    }
}

// MARK: - School pulse widget

struct SchoolPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SchoolPulseWidget", provider: SnapshotProvider()) { entry in
            SchoolPulseWidgetView(entry: entry)
                .themedWidgetContainer()
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://calendar"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot.map {
                        combinedStatus($0.resolvedAssignmentStatus, $0.resolvedMessageStatus)
                    }
                ))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .configurationDisplayName("School Pulse")
        .description("Missing work and your latest messages at a glance. Shows no grades.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// A grade-free look at the school day: missing work beside the newest
/// message on the medium size, each listed on the large. Each section reads
/// its own status, so one that didn't load is never shown as clear or empty.
struct SchoolPulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: SnapshotEntry

    private var tone: Tone { Tone(mode: renderingMode) }
    private var isLarge: Bool { family == .systemLarge }
    private var missingRows: Int { dynamicTypeSize <= .large ? 3 : 2 }
    /// Lines for the newest item in a medium column.
    private var detailLines: Int { dynamicTypeSize <= .large ? 2 : 1 }

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeading(title: "School pulse", detail: Format.termName(snapshot.termShortName))
                if isLarge {
                    large(snapshot)
                } else {
                    medium(snapshot)
                }
            }
            .widgetPage()
        } else {
            NoDataView(heading: "School pulse", subject: "assignments and messages")
        }
    }

    // MARK: Sizes

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            missingColumn(s)
                .frame(maxWidth: .infinity, alignment: .leading)
            Hairline(tone: tone, vertical: true)
            inboxColumn(s)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
    }

    private func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Missing work") { missingFigure(s, style: .title2) }
                .padding(.top, 8)
            if !s.missingAssignments.isEmpty {
                RuledList(items: s.missingAssignments, rows: missingRows, tone: tone, fills: false) {
                    AssignmentRow(item: $0, tone: tone)
                }
                .padding(.top, 4)
            } else {
                Text(missingDetail(s, count: missingCount(s)))
                    .font(.footnote)
                    .foregroundStyle(tone.muted)
                    .lineLimit(2)
            }
            Hairline(tone: tone)
                .padding(.vertical, 10)
            sectionLabel("Inbox") {
                if s.messages.isEmpty, !s.resolvedMessageStatus.isComplete { unavailable }
            }
            if s.messages.isEmpty {
                Text(s.resolvedMessageStatus.isComplete ? "No messages" : "Open Elevate to refresh.")
                    .font(.footnote)
                    .foregroundStyle(tone.muted)
            } else {
                FittingRows(maximum: 3) { rows in
                    RuledList(items: s.messages, rows: rows, tone: tone) {
                        MessageRow(message: $0, tone: tone)
                    }
                }
                .padding(.top, 4)
                .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Medium columns

    /// The count large, then the newest missing assignment.
    @ViewBuilder
    private func missingColumn(_ s: WidgetSnapshot) -> some View {
        let column = VStack(alignment: .leading, spacing: 2) {
            sectionLabel("Missing work") { EmptyView() }
            Spacer(minLength: 2)
            missingFigure(s, style: .title)
            Text(missingDetail(s, count: missingCount(s)))
                .font(.footnote)
                .foregroundStyle(tone.muted)
                .lineLimit(detailLines)
        }
        .accessibilityElement(children: .combine)
        if let url = s.missingAssignments.first?.assignmentURL {
            Link(destination: url) { column }
        } else {
            column
        }
    }

    /// The newest message: its date, subject, and sender.
    private func inboxColumn(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionLabel("Inbox") {
                if let latest = s.messages.first {
                    Text(Format.date(latest.date))
                        .font(.footnote)
                        .foregroundStyle(tone.muted)
                }
            }
            Spacer(minLength: 2)
            if let latest = s.messages.first {
                Text(latest.subject.isEmpty ? "No subject" : latest.subject)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tone.ink)
                    .lineLimit(detailLines)
                Text(Format.person(latest.from))
                    .font(.footnote)
                    .foregroundStyle(tone.muted)
                    .lineLimit(1)
            } else if s.resolvedMessageStatus.isComplete {
                Text("No messages")
                    .font(.subheadline)
                    .foregroundStyle(tone.muted)
            } else {
                unavailable
                Text("Open Elevate to refresh.")
                    .font(.footnote)
                    .foregroundStyle(tone.muted)
                    .lineLimit(detailLines)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Parts

    /// A verified total, or the work found when some classes didn't load.
    /// Zero only when every class was checked; otherwise unavailable.
    private func missingCount(_ s: WidgetSnapshot) -> Int? {
        if let total = s.missingAssignmentsTotal, total > 0 || s.resolvedAssignmentStatus.isComplete {
            return total
        }
        return s.missingAssignments.isEmpty ? nil : s.missingAssignments.count
    }

    @ViewBuilder
    private func missingFigure(_ s: WidgetSnapshot, style: Font.TextStyle) -> some View {
        if let count = missingCount(s) {
            let isLowerBound = s.missingAssignmentsTotal == nil || !s.resolvedAssignmentStatus.isComplete
            Text("\(count)\(isLowerBound ? "+" : "")")
                .font(.figure(style, weight: .semibold))
                .foregroundStyle(count > 0 ? tone.attention : tone.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
                .accessibilityLabel((isLowerBound ? "At least " : "") + (count == 1 ? "1 assignment" : "\(count) assignments"))
        } else {
            unavailable
        }
    }

    /// The newest missing assignment, a verified clear, or what to do.
    private func missingDetail(_ s: WidgetSnapshot, count: Int?) -> String {
        if let first = s.missingAssignments.first {
            let name = first.name.isEmpty ? "Untitled assignment" : first.name
            return first.className.isEmpty ? name : "\(name), \(first.className)"
        }
        if count == 0 { return "Nothing missing in \(Format.termName(s.termShortName))" }
        return "Open Elevate to refresh."
    }

    /// A quiet group label with an optional figure or note at its end.
    private func sectionLabel<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(tone.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }

    private var unavailable: some View {
        Text("Unavailable")
            .font(.footnote)
            .foregroundStyle(tone.muted)
    }
}

// MARK: - Grades overview widget

struct GradesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GradesWidget", provider: SnapshotProvider()) { entry in
            GradesWidgetView(entry: entry)
                .themedWidgetContainer()
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://courses"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedBaseStatus
                ))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .configurationDisplayName("Grades")
        .description("Shows the current grade in each of your classes, with your GPA on the large size.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// Classes in schedule order with their term grade, as on Courses. The large
/// size opens with the weighted and unweighted GPA.
struct GradesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.snapshotFreshness) private var freshness
    @ScaledMetric(relativeTo: .title) var figureSize: CGFloat = 30
    let entry: SnapshotEntry

    private var tone: Tone { Tone(mode: renderingMode) }
    private var isLarge: Bool { family == .systemLarge }
    private var rowPadding: CGFloat { dynamicTypeSize > .large ? 2 : 3 }

    var body: some View {
        if let s = entry.snapshot {
            if !s.courses.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetHeading(title: "Grades", detail: Format.termName(s.termShortName))
                        .padding(.bottom, 4)
                    if isLarge, let weighted = s.weightedGPA {
                        gpaFigures(weighted: weighted, unweighted: s.unweightedGPA)
                            .padding(.bottom, 8)
                        Hairline(tone: tone)
                    }
                    FittingRows(maximum: isLarge ? 8 : 4) { rows in
                        courseList(s.courses, rows: rows)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .widgetPage()
            } else {
                WidgetEmptyState(
                    heading: "Grades",
                    headingDetail: Format.termName(s.termShortName),
                    title: freshness.isPartial ? "Classes didn't load" : "No classes this term",
                    detail: freshness.isPartial
                        ? "Open Elevate to refresh."
                        : "Skyward has no classes for \(Format.termName(s.termShortName))."
                )
            }
        } else {
            NoDataView(heading: "Grades")
        }
    }

    private func courseList(_ courses: [WidgetSnapshot.CourseGrade], rows: Int) -> some View {
        let shown = min(rows, courses.count)
        return VStack(alignment: .leading, spacing: 0) {
            RuledList(items: courses, rows: rows, tone: tone, spacing: 0) {
                courseRow($0)
            }
            if isLarge, courses.count > shown {
                Text("\(courses.count - shown) more in Elevate")
                    .font(.footnote)
                    .foregroundStyle(tone.muted)
                    .padding(.top, 4)
            }
        }
    }

    /// Weighted large and unweighted beside it, each over its label.
    private func gpaFigures(weighted: Double, unweighted: Double?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 20) {
            figure(Format.gpa(weighted), label: "Weighted GPA", size: figureSize, isAccented: true)
            if let unweighted {
                figure(Format.gpa(unweighted), label: "Unweighted", size: figureSize * 0.62)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Weighted GPA \(Format.gpa(weighted))" + (unweighted.map { ", unweighted \(Format.gpa($0))" } ?? "")
        )
    }

    private func figure(_ value: String, label: String, size: CGFloat, isAccented: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.display(size: size))
                .foregroundStyle(tone.ink)
                .widgetAccentable(isAccented)
            Text(label)
                .font(.caption)
                .foregroundStyle(tone.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func courseRow(_ course: WidgetSnapshot.CourseGrade) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(course.name)
                .font(.subheadline)
                .foregroundStyle(tone.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Format.grade(course.score))
                .font(.figure(.body, weight: .semibold))
                .foregroundStyle(tone.grade(course.score))
                .lineLimit(1)
                .accessibilityLabel(spokenGrade(course.score))
        }
        .padding(.vertical, rowPadding)
        .accessibilityElement(children: .combine)
    }

    private func spokenGrade(_ score: Double?) -> String {
        guard let score, score.isFinite else { return "No grade" }
        return "\(Format.grade(score)) percent"
    }
}

// MARK: - Recent grades widget

struct RecentGradesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentGradesWidget", provider: SnapshotProvider()) { entry in
            RecentGradesWidgetView(entry: entry)
                .themedWidgetContainer()
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(entry.snapshot?.recentGrades.first?.assignmentURL ?? URL(string: "com.zacharywilson.elevate://courses"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedAssignmentStatus
                ))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .configurationDisplayName("Recent Grades")
        .description("Shows the scores on the assignments your teachers graded most recently.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RecentGradesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) var figureSize: CGFloat = 34
    let entry: SnapshotEntry

    private var tone: Tone { Tone(mode: renderingMode) }

    var body: some View {
        if let s = entry.snapshot {
            if let latest = s.recentGrades.first {
                if family == .systemSmall {
                    small(latest)
                } else {
                    medium(s)
                }
            } else {
                let incomplete = !s.resolvedAssignmentStatus.isComplete
                WidgetEmptyState(
                    heading: family == .systemSmall ? "Latest grade" : "Recent grades",
                    title: incomplete ? "Grades didn't fully load" : "No graded work yet",
                    detail: incomplete
                        ? "Open Elevate to refresh."
                        : "New grades from \(Format.termName(s.termShortName)) will appear here."
                )
            }
        } else {
            NoDataView(heading: family == .systemSmall ? "Latest grade" : "Recent grades")
        }
    }

    private func small(_ latest: WidgetSnapshot.AssignmentItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(title: "Latest grade", showsFreshness: false)
            Spacer(minLength: 4)
            Text(latest.gradeText.isEmpty ? "—" : latest.gradeText)
                .font(.display(size: figureSize))
                .foregroundStyle(tone.grade(Format.percent(latest.gradeText)))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text(latest.name.isEmpty ? "Untitled assignment" : latest.name)
                .font(.subheadline)
                .foregroundStyle(tone.ink)
                .lineLimit(1)
            Text(latest.className)
                .font(.footnote)
                .foregroundStyle(tone.muted)
                .lineLimit(1)
            FreshnessNote(compact: true)
                .padding(.top, 2)
        }
        .widgetPage()
        .accessibilityElement(children: .combine)
    }

    /// The latest score large on the leading side, the ones before it listed
    /// beside it.
    private func medium(_ s: WidgetSnapshot) -> some View {
        let earlier = dynamicTypeSize <= .large ? Array(s.recentGrades.dropFirst()) : []
        return VStack(alignment: .leading, spacing: 0) {
            WidgetHeading(
                title: "Recent grades",
                detail: s.recentGradesTotal.map { "\($0) graded" }
            )
            .padding(.bottom, 6)
            HStack(alignment: .top, spacing: 12) {
                if let latest = s.recentGrades.first {
                    latestColumn(latest)
                        .frame(width: earlier.isEmpty ? nil : 108, alignment: .leading)
                }
                if !earlier.isEmpty {
                    Hairline(tone: tone, vertical: true)
                    FittingRows(maximum: 3) { rows in
                        RuledList(items: earlier, rows: rows, tone: tone) { item in
                            AssignmentRow(item: item, tone: tone) { grade(item, style: .body) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .widgetPage()
    }

    @ViewBuilder
    private func latestColumn(_ item: WidgetSnapshot.AssignmentItem) -> some View {
        let column = VStack(alignment: .leading, spacing: 1) {
            Text(item.gradeText.isEmpty ? "—" : item.gradeText)
                .font(.display(size: figureSize))
                .foregroundStyle(tone.grade(Format.percent(item.gradeText)))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text(item.name.isEmpty ? "Untitled assignment" : item.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tone.ink)
                .lineLimit(2)
            Text(item.className)
                .font(.footnote)
                .foregroundStyle(tone.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        if let url = item.assignmentURL {
            Link(destination: url) { column }
        } else {
            column
        }
    }

    private func grade(_ item: WidgetSnapshot.AssignmentItem, style: Font.TextStyle) -> some View {
        Text(item.gradeText.isEmpty ? "—" : item.gradeText)
            .font(.figure(style, weight: .semibold))
            .foregroundStyle(tone.grade(Format.percent(item.gradeText)))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Missing assignments widget

struct MissingAssignmentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MissingAssignmentsWidget", provider: SnapshotProvider()) { entry in
            MissingAssignmentsWidgetView(entry: entry)
                .themedWidgetContainer()
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://courses"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedAssignmentStatus
                ))
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .configurationDisplayName("Missing Work")
        .description("Assignments Skyward has flagged as missing.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The count first. A verified total is shown as is; when some classes
/// didn't load, the count is what was found so far; nothing is called clear
/// unless every class was checked.
struct MissingAssignmentsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @ScaledMetric(relativeTo: .largeTitle) var figureSize: CGFloat = 40
    let entry: SnapshotEntry

    private var tone: Tone { Tone(mode: renderingMode) }

    /// What the count means, or nil when nothing can be counted honestly.
    private struct Count {
        var value: Int
        var caption: String
        var isVerifiedClear: Bool
        var isLowerBound = false
    }

    private func missingCount(_ s: WidgetSnapshot) -> Count? {
        let isComplete = s.resolvedAssignmentStatus.isComplete
        if let total = s.missingAssignmentsTotal {
            if total == 0 {
                return isComplete
                    ? Count(value: 0, caption: "Nothing missing", isVerifiedClear: true)
                    : nil
            }
            return Count(value: total, caption: total == 1 ? "assignment" : "assignments", isVerifiedClear: false, isLowerBound: !isComplete)
        }
        guard !s.missingAssignments.isEmpty else { return nil }
        return Count(value: s.missingAssignments.count, caption: s.missingAssignments.count == 1 ? "assignment" : "assignments", isVerifiedClear: false, isLowerBound: true)
    }

    var body: some View {
        if let s = entry.snapshot {
            let missing = s.missingAssignments
            let total = s.missingAssignmentsTotal
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Missing Work", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    Spacer()
                    Text(total.map(String.init) ?? "—")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(total == 0 ? "All caught up!" : total.map { "assignment\($0 == 1 ? "" : "s") missing" } ?? "Some data unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Missing Work")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if total != 0 {
                            Text(total.map(String.init) ?? "—")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                        }
                    }
                    if total == 0 {
                        Spacer()
                        HStack {
                            Spacer()
                            Label {
                                Text("All caught up!")
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .font(.callout.bold())
                            Spacer()
                        }
                        Spacer()
                    } else {
                        ForEach(missing.prefix(4), id: \.self) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(item.className)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(item.date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            NoDataView()
        }
    }
}

// MARK: - Inbox widget

struct InboxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InboxWidget", provider: SnapshotProvider()) { entry in
            InboxWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://inbox"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedMessageStatus
                ))
        }
        .configurationDisplayName("Inbox")
        .description("Your most recent Skyward messages.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct InboxWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var maxRows: Int { family == .systemLarge ? 6 : 2 }

    var body: some View {
        if let s = entry.snapshot {
            if !s.messages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                Text("Inbox")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(s.messages.prefix(maxRows), id: \.self) { message in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: message.isAdministrator ? "building.columns" : "envelope")
                            .font(.caption)
                            .foregroundStyle(accent)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(message.subject)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(message.from)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(message.date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                }
            } else {
                WidgetEmptyStateView(systemImage: "envelope", title: "No messages")
            }
        } else {
            NoDataView()
        }
    }
}

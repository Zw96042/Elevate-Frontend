import WidgetKit
import SwiftUI

@main
struct ElevateWidgetBundle: WidgetBundle {
    var body: some Widget {
        GPAWidget()
        GPATrendWidget()
        SchoolPulseWidget()
        GradesWidget()
        RecentGradesWidget()
        MissingAssignmentsWidget()
        InboxWidget()
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

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview
            ? (WidgetSnapshotStore.load() ?? .placeholder)
            : WidgetSnapshotStore.load()
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

// MARK: - Shared bits

@MainActor private var accent: Color { Color.themeAccent }

struct NoDataView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "graduationcap")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Open Elevate to load your grades")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WidgetEmptyStateView: View {
    var systemImage: String
    var title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SnapshotFreshnessModifier: ViewModifier {
    var snapshot: WidgetSnapshot?
    var section: WidgetSnapshot.SectionStatus?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if let snapshot,
               isStale(snapshot: snapshot) {
                Text(section?.isComplete == false ? "Partial data" : "Out of date")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .accessibilityLabel(section?.isComplete == false ? "Some data is unavailable" : "Data is out of date")
            }
        }
    }

    private func isStale(snapshot: WidgetSnapshot) -> Bool {
        guard let section else {
            return Date().timeIntervalSince(snapshot.generatedAt) > 6 * 60 * 60
        }
        if !section.isComplete { return true }
        guard let updatedAt = section.updatedAt else { return true }
        return Date().timeIntervalSince(updatedAt) > 6 * 60 * 60
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

private func gpaTrendAccessibilityValue(_ snapshot: WidgetSnapshot) -> String {
    guard let history = snapshot.gpaHistory, !history.isEmpty else { return "No GPA history" }
    let series = history
        .map { "\($0.term) \(String(format: "%.2f", $0.weighted))" }
        .joined(separator: ", ")
    if let delta = gpaDelta(snapshot) {
        return "Latest \(String(format: "%.2f", history.last?.weighted ?? 0)), change \(String(format: "%+.2f", delta)). \(series)"
    }
    return series
}

private func scoreText(_ score: Double?) -> String {
    guard let score else { return "--" }
    return String(format: "%.0f", score)
}

private func gpaDelta(_ snapshot: WidgetSnapshot) -> Double? {
    guard let history = snapshot.gpaHistory, history.count >= 2 else { return nil }
    return history[history.count - 1].weighted - history[history.count - 2].weighted
}

private struct Sparkline: View {
    let values: [Double]
    var showsFill = true

    var body: some View {
        GeometryReader { proxy in
            let points = plottedPoints(in: proxy.size)
            ZStack {
                if showsFill, let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.24), accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func plottedPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? minimum
        let range = max(maximum - minimum, 0.1)
        let denominator = CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) / denominator * size.width,
                y: size.height - CGFloat((value - minimum) / range) * size.height
            )
        }
    }
}

private struct GradeMeterRow: View {
    let course: WidgetSnapshot.CourseGrade

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 8) {
                Text(course.name)
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(scoreText(course.score))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(accent)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(accent.opacity(0.82))
                            .frame(width: proxy.size.width * min(max((course.score ?? 0) / 100, 0), 1))
                    }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - GPA widget

struct GPAWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GPAWidget", provider: SnapshotProvider()) { entry in
            GPAWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://gpa"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedBaseStatus
                ))
        }
        .configurationDisplayName("GPA")
        .description("Your weighted and unweighted GPA for the current term.")
        .supportedFamilies([.systemSmall])
    }
}

struct GPAWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot {
            if let weighted = s.weightedGPA {
                VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("GPA")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(s.termShortName)
                        .font(.caption2.bold())
                        .foregroundStyle(accent)
                }
                Spacer()
                Text(String(format: "%.2f", weighted))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    Text("Weighted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let delta = gpaDelta(s) {
                        Label(String(format: "%+.2f", delta),
                              systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(delta >= 0 ? .green : .red)
                    }
                }
                if let history = s.gpaHistory, history.count > 1 {
                    Sparkline(values: history.map(\.weighted), showsFill: false)
                        .frame(height: 18)
                }
                }
            } else {
                WidgetEmptyStateView(systemImage: "chart.line.uptrend.xyaxis", title: "No GPA yet")
            }
        } else {
            NoDataView()
        }
    }
}

// MARK: - GPA trend widget

struct GPATrendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GPATrendWidget", provider: SnapshotProvider()) { entry in
            GPATrendWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://gpa"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedBaseStatus
                ))
        }
        .configurationDisplayName("GPA Trend")
        .description("A clean visual of how your GPA has moved recently.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GPATrendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot,
           let history = snapshot.gpaHistory,
           history.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("GPA Trend", systemImage: "chart.xyaxis.line")
                        .font(.caption.bold())
                    Spacer()
                    if let delta = gpaDelta(snapshot) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.bold())
                            .foregroundStyle(delta >= 0 ? .green : .red)
                    }
                }
                .foregroundStyle(.secondary)

                Sparkline(values: history.map(\.weighted))

                if family == .systemMedium {
                    HStack {
                        ForEach(history, id: \.self) { point in
                            Text(point.term)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            if point != history.last { Spacer() }
                        }
                    }
                } else {
                    Text((gpaDelta(snapshot) ?? 0) >= 0 ? "Trending up" : "Trending down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weighted GPA trend")
            .accessibilityValue(gpaTrendAccessibilityValue(snapshot))
        } else if entry.snapshot != nil {
            WidgetEmptyStateView(
                systemImage: "chart.xyaxis.line",
                title: "More graded terms are needed for a trend"
            )
        } else {
            NoDataView()
        }
    }
}

// MARK: - School pulse widget

struct SchoolPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SchoolPulseWidget", provider: SnapshotProvider()) { entry in
            SchoolPulseWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://gpa"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot.map {
                        combinedStatus($0.resolvedBaseStatus, $0.resolvedAssignmentStatus)
                    }
                ))
        }
        .configurationDisplayName("School Pulse")
        .description("GPA movement, missing work, and absences in one glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SchoolPulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            let missingTotal = snapshot.missingAssignmentsTotal
            let absentTotal = snapshot.absentAssignmentsTotal
            let isCaughtUp = missingTotal == 0 && absentTotal == 0
            VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
                HStack {
                    Label("School Pulse", systemImage: "waveform.path.ecg")
                        .font(.caption.bold())
                    Spacer()
                    Text(snapshot.termShortName)
                        .font(.caption2.bold())
                        .foregroundStyle(accent)
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    pulseMetric(
                        title: "GPA change",
                        value: gpaDelta(snapshot).map { String(format: "%+.2f", $0) } ?? "—",
                        symbol: (gpaDelta(snapshot) ?? 0) >= 0 ? "arrow.up.right" : "arrow.down.right",
                        color: (gpaDelta(snapshot) ?? 0) >= 0 ? .green : .red
                    )
                    pulseMetric(
                        title: "Missing",
                        value: missingTotal.map(String.init) ?? "—",
                        symbol: "exclamationmark.circle.fill",
                        color: .red
                    )
                    pulseMetric(
                        title: "Absent",
                        value: absentTotal.map(String.init) ?? "—",
                        symbol: "person.crop.circle.badge.xmark",
                        color: .orange
                    )
                }

                if family == .systemLarge {
                    if let history = snapshot.gpaHistory, history.count > 1 {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Recent GPA movement")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Sparkline(values: history.map(\.weighted))
                                .frame(height: 70)
                        }
                    }
                    attentionList(snapshot)
                } else {
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        Image(systemName: snapshot.missingAssignments.isEmpty
                              && isCaughtUp
                              ? "checkmark.circle.fill" : "bell.badge.fill")
                            .foregroundStyle(isCaughtUp
                                             ? .green : accent)
                        Text(isCaughtUp
                             ? "You're all caught up" : "Work needs your attention")
                            .font(.caption2.weight(.semibold))
                    }
                }
            }
        } else {
            NoDataView()
        }
    }

    private func pulseMetric(title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func attentionList(_ snapshot: WidgetSnapshot) -> some View {
        let items = snapshot.missingAssignments.map { ("Missing", $0, Color.red) }
            + (snapshot.absentAssignments ?? []).map { ("Absent", $0, Color.orange) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Needs attention")
                .font(.caption.bold())
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 7) {
                    Circle().fill(item.2).frame(width: 6, height: 6)
                    Text(item.1.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(item.0)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.2)
                }
            }
        }
    }
}

// MARK: - Grades overview widget

struct GradesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GradesWidget", provider: SnapshotProvider()) { entry in
            GradesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://courses"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedBaseStatus
                ))
        }
        .configurationDisplayName("Grades")
        .description("Current grades for all of your classes.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct GradesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var maxRows: Int { family == .systemLarge ? 8 : 3 }

    var body: some View {
        if let s = entry.snapshot {
            if !s.courses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(s.termShortName) Grades")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let updatedAt = s.resolvedBaseStatus.updatedAt {
                        Text(updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(s.courses.prefix(maxRows), id: \.self) { course in
                    GradeMeterRow(course: course)
                }
                Spacer(minLength: 0)
                }
            } else {
                WidgetEmptyStateView(systemImage: "books.vertical", title: "No current courses")
            }
        } else {
            NoDataView()
        }
    }
}

// MARK: - Recent grades widget

struct RecentGradesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentGradesWidget", provider: SnapshotProvider()) { entry in
            RecentGradesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://courses"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedAssignmentStatus
                ))
        }
        .configurationDisplayName("Recent Grades")
        .description("The latest assignments your teachers have graded.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RecentGradesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot {
            if let latest = s.recentGrades.first, family == .systemSmall {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest Grade")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(latest.gradeText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(latest.name)
                        .font(.caption2.bold())
                        .lineLimit(2)
                    Text(latest.className)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if !s.recentGrades.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Recent Grades")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(s.recentGrades.prefix(4), id: \.self) { item in
                        HStack(spacing: 8) {
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
                            Text(item.gradeText)
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(accent)
                            Text(item.date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                WidgetEmptyStateView(systemImage: "checkmark.circle", title: "No recent grades")
            }
        } else {
            NoDataView()
        }
    }
}

// MARK: - Missing assignments widget

struct MissingAssignmentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MissingAssignmentsWidget", provider: SnapshotProvider()) { entry in
            MissingAssignmentsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .privacySensitive(entry.snapshot != nil)
                .widgetURL(URL(string: "com.zacharywilson.elevate://courses"))
                .modifier(SnapshotFreshnessModifier(
                    snapshot: entry.snapshot,
                    section: entry.snapshot?.resolvedAssignmentStatus
                ))
        }
        .configurationDisplayName("Missing Work")
        .description("Assignments Skyward has flagged as missing.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MissingAssignmentsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

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

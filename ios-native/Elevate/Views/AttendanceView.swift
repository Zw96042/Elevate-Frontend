import SwiftUI

/// Source attendance records grouped by school date, newest first. Each row
/// shows Skyward's own description; nothing is counted or categorized.
struct AttendanceView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var showingConnect = false

    /// Changes whenever the refresh loop should start over or stop: another
    /// account, sign-in state, this tab leaving view, or the app backgrounding.
    private struct RefreshLoopIdentity: Hashable {
        var accountRevision: Int
        var canShowData: Bool
        var isSelected: Bool
        var isActive: Bool
    }

    private var refreshLoopIdentity: RefreshLoopIdentity {
        RefreshLoopIdentity(
            accountRevision: store.accountRevision,
            canShowData: store.canShowData,
            isSelected: router.selectedTab == .calendar,
            isActive: scenePhase == .active
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if !store.canShowData {
                    LoginPromptView(message: "Connect your Skyward account to see attendance records from your school.") {
                        showingConnect = true
                    }
                } else if store.attendance == nil, let error = store.attendanceError {
                    ErrorStateView(title: "Couldn't load attendance", message: error) {
                        await store.refreshAttendance(force: true)
                    }
                } else {
                    attendanceList
                }
            }
            .screenTitle("Attendance") { showingSettings = true }
            .background(Color.appBackground.ignoresSafeArea())
            .accessibilityIdentifier("attendance.screen")
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingConnect) { SkywardConnectSheet() }
            .task(id: refreshLoopIdentity) {
                let identity = refreshLoopIdentity
                guard identity.isSelected, identity.isActive, identity.canShowData else { return }
                // The store owns the first fetch and later due refreshes; a
                // new identity cancels this loop.
                await store.runAttendanceRefreshLoop()
            }
        }
    }

    private var statusStrip: some View {
        StatusStrip(
            lastUpdated: store.attendanceLastUpdated,
            isRefreshing: store.attendanceLoading,
            error: store.attendance == nil ? nil : store.attendanceError
        ) {
            await store.refreshAttendance(force: true)
        }
        .padding(.horizontal, Metrics.page)
    }

    private var attendanceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip

                if let attendance = store.attendance {
                    if attendance.availability == .unavailable {
                        EmptyStateView(
                            title: "Attendance isn't available",
                            message: "Skyward hasn't made attendance available for this account."
                        )
                        .padding(.horizontal, Metrics.page)
                        .accessibilityIdentifier("attendance.unavailable")
                    } else if attendance.records.isEmpty {
                        EmptyStateView(
                            title: "No attendance records",
                            message: "Skyward has no attendance records to show."
                        )
                        .padding(.horizontal, Metrics.page)
                        .accessibilityIdentifier("attendance.empty")
                    } else {
                        recordGroups(AttendanceDay.days(from: attendance.records))
                    }
                } else {
                    // Nothing fetched or saved yet, including before the
                    // first request starts.
                    loadingRows
                }
            }
            .padding(.bottom, 24)
        }
        .visibleRefreshable {
            await store.refreshAttendance(force: true)
        }
    }

    /// The record list's shape: dates as group labels, each over its records'
    /// description and period line.
    private var loadingRows: some View {
        let days = [[14, 11], [16], [12, 15, 10]]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(days.indices, id: \.self) { day in
                SkeletonText(.footnote.weight(.medium), length: 18, tone: .secondary)
                    .padding(.bottom, 2)
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 20)
                ForEach(days[day].indices, id: \.self) { index in
                    if index > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                    SkeletonRow(lines: [SkeletonLine(.body, days[day][index]), SkeletonLine(.subheadline, 17)])
                        .padding(.horizontal, Metrics.page)
                }
            }
        }
        .loadingPlaceholder("Loading attendance")
        .accessibilityIdentifier("attendance.loading")
    }

    private func recordGroups(_ days: [AttendanceDay]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(days) { day in
                GroupLabel(day.title)
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 20)
                    .accessibilityIdentifier("attendance.date.\(day.date)")
                ForEach(Array(day.entries.enumerated()), id: \.element.record.id) { position, entry in
                    if position > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                    AttendanceRow(record: entry.record, dateTitle: day.title)
                        .accessibilityIdentifier("attendance.record.\(entry.index)")
                }
            }
        }
    }
}

/// Records sharing one school date, in source order.
private struct AttendanceDay: Identifiable {
    struct Entry {
        /// Position across every displayed row, for row identifiers.
        var index: Int
        var record: AttendanceRecord
    }

    var date: String
    var title: String
    var entries: [Entry]

    var id: String { date }

    /// ISO school dates sort as text, so newest first is a descending sort.
    static func days(from records: [AttendanceRecord]) -> [AttendanceDay] {
        let grouped = Dictionary(grouping: records, by: \.date)
        var index = 0
        return grouped.keys.sorted(by: >).map { date in
            let records = grouped[date] ?? []
            let entries = records.map { record -> Entry in
                defer { index += 1 }
                return Entry(index: index, record: record)
            }
            let title = records.first?.displayDate?
                .formatted(.dateTime.weekday(.wide).month(.wide).day().year()) ?? date
            return AttendanceDay(date: date, title: title, entries: entries)
        }
    }
}

/// One record as an open row: Skyward's description, then the period and
/// class beneath it. Not navigable.
struct AttendanceRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var record: AttendanceRecord
    var dateTitle: String

    private var sourceDescription: String {
        record.attendance.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var code: String? {
        record.rawCode.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// "Period 2" only for a numeric period of a period record; any other
    /// source text, such as "All day", is shown as written.
    private var periodText: String? {
        guard let raw = record.period?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if record.granularity == .period, raw.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return "Period \(raw)"
        }
        return raw
    }

    private var courseText: String? {
        guard let raw = record.courseName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return ClassNameFormatter.format(raw.replacingOccurrences(of: " ", with: "_"))
    }

    private var spokenLabel: String {
        var parts = [dateTitle, sourceDescription]
        if let periodText { parts.append(periodText) }
        if let courseText { parts.append(courseText) }
        if let code { parts.append("Code \(code)") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            primaryLine
            if periodText != nil || courseText != nil {
                metadataLine
            }
        }
        .padding(.horizontal, Metrics.page)
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    @ViewBuilder
    private var primaryLine: some View {
        if let code {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    descriptionText
                    codeText(code)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    descriptionText
                        .frame(maxWidth: .infinity, alignment: .leading)
                    codeText(code)
                }
            }
        } else {
            descriptionText
        }
    }

    private var descriptionText: some View {
        Text(sourceDescription)
            .font(.body)
            .foregroundStyle(Color.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func codeText(_ code: String) -> some View {
        Text(code)
            .font(.subheadline)
            .foregroundStyle(Color.muted)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var metadataLine: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                if let periodText { metadataText(periodText) }
                if let courseText { metadataText(courseText) }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let periodText {
                    metadataText(periodText)
                        .layoutPriority(1)
                }
                if let courseText {
                    metadataText(courseText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func metadataText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.muted)
            .multilineTextAlignment(.leading)
    }
}

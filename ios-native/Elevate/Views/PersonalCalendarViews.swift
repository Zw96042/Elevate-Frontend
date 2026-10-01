import SwiftUI
import UIKit

extension Color {
    init(personal color: PersonalCalendarColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}

// MARK: - Calendars button

/// Beside the quarter: up to three shown calendars' colors, or a calendar
/// symbol before any are shown. Opens the Calendars sheet.
struct PersonalCalendarsButton: View {
    var store: PersonalCalendarStore
    var action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var swatch: CGFloat = 9

    private var shown: [PersonalCalendarInfo] { store.shownCalendars }

    private var spokenValue: String {
        switch store.access {
        case .full:
            return shown.isEmpty ? "None shown" : (shown.count == 1 ? "1 shown" : "\(shown.count) shown")
        case .notDetermined: return "Not connected"
        case .writeOnly, .denied, .restricted: return "No access"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 6) {
                if shown.isEmpty {
                    Image(systemName: "calendar")
                        .font(.subheadline.weight(.semibold))
                } else {
                    HStack(spacing: -swatch * 0.3) {
                        ForEach(shown.prefix(3)) { calendar in
                            Circle()
                                .fill(Color(personal: calendar.color))
                                .frame(width: swatch, height: swatch)
                                .overlay { Circle().stroke(Color.well, lineWidth: 1.5) }
                        }
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.muted)
                // Holds a text line's height, matching the quarter button.
                Text(verbatim: " ")
                    .frame(width: 0)
            }
            .accessibilityHidden(true)
        }
        .buttonStyle(QuietButtonStyle())
        .accessibilityLabel("Your calendars")
        .accessibilityValue(spokenValue)
        .accessibilityHint("Chooses which of this iPhone's calendars appear")
        .accessibilityIdentifier("calendar.personalCalendars")
    }
}

// MARK: - Invitation

/// Shown once on the Calendar page until the person connects or declines.
/// iOS asks for access only after "Show calendars".
struct PersonalCalendarInvitation: View {
    var store: PersonalCalendarStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.title3)
                .foregroundStyle(Color.themeAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Add your other calendars")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("See events from Google, iCloud and other calendars on this iPhone next to your assignments. They're never saved or sent anywhere.")
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Button("Show calendars") {
                        Task { await store.requestAccess() }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(store.isRequestingAccess)
                    .accessibilityIdentifier("calendar.invitation.connect")
                    Button("Not now") { store.dismissInvitation() }
                        .buttonStyle(ActionTextButtonStyle())
                        .accessibilityIdentifier("calendar.invitation.dismiss")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.invitation")
    }
}

// MARK: - Calendars sheet

/// Which of the iPhone's calendars appear on the Calendar page, by account.
struct PersonalCalendarsSheet: View {
    var store: PersonalCalendarStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var themeManager = ThemeManager.shared

    var body: some View {
        // A plain header on the sheet's own background: no navigation bar,
        // so nothing blurs over the list as it scrolls.
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Calendars", doneIdentifier: "calendars.done") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                    switch store.access {
                    case .full: choices
                    case .notDetermined: invitation
                    case .writeOnly, .denied: noAccess
                    case .restricted: restricted
                    }
                }
                .padding(.horizontal, Metrics.page)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .tint(Color.themeAccent)
        .foregroundStyle(Color.ink)
        .preferredColorScheme(themeManager.appearance.colorScheme)
        // A container, so its identifier doesn't replace its controls'.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendars.screen")
        .task(id: scenePhase) {
            // Returning from iOS Settings may have changed access.
            if scenePhase == .active { store.refreshAccess() }
        }
    }

    private static let privacyNote = "Elevate reads these events from this iPhone while you use Calendar. They aren't saved or sent anywhere."
    private static let googleNote = "To include Google Calendar, add your Google account to the iPhone in Settings › Apps › Calendar › Calendar Accounts."

    // MARK: Full access

    @ViewBuilder
    private var choices: some View {
        Text("Choose which of this iPhone's calendars appear next to your assignments.")
            .font(.subheadline)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, -Metrics.sectionGap + 8)

        let groups = PersonalCalendarGroup.groups(store.calendars)
        if groups.isEmpty {
            SettingsGroup(title: "Calendars") {
                Text("There are no calendars on this iPhone yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } footer: {
                Text(Self.googleNote)
                    .foregroundStyle(Color.muted)
            }
        } else {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                SettingsGroup(title: group.title) {
                    ForEach(Array(group.calendars.enumerated()), id: \.element.id) { row, calendar in
                        if row > 0 { InsetDivider() }
                        calendarRow(calendar)
                    }
                } footer: {
                    if index == groups.count - 1 {
                        Text("\(Self.privacyNote) \(Self.googleNote)")
                            .foregroundStyle(Color.muted)
                    }
                }
            }
        }
    }

    private func calendarRow(_ calendar: PersonalCalendarInfo) -> some View {
        Toggle(isOn: Binding(
            get: { store.selection.isShown(calendar) },
            set: { store.setShown($0, for: calendar) }
        )) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(personal: calendar.color))
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text(calendar.title.isEmpty ? "Untitled calendar" : calendar.title)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.themeAccent)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .accessibilityIdentifier("calendars.calendar.\(calendar.title)")
    }

    // MARK: Other states

    private var invitation: some View {
        SettingsGroup(title: "Your calendars") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Show events from Google, iCloud and the other calendars on this iPhone next to your assignments.")
                    .font(.body)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show calendars") {
                    Task { await store.requestAccess() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.isRequestingAccess)
                .accessibilityIdentifier("calendars.connect")
                if let error = store.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                }
            }
            .padding(.vertical, 8)
        } footer: {
            Text("iOS asks whether Elevate may see your calendars. \(Self.privacyNote)")
                .foregroundStyle(Color.muted)
        }
    }

    private var noAccess: some View {
        SettingsGroup(title: "Calendar access") {
            SettingsRow {
                Text("Calendars")
            } accessory: {
                Text(store.access == .writeOnly ? "Add events only" : "Off")
                    .foregroundStyle(Color.gradeWarning)
            }
            .accessibilityElement(children: .combine)
            InsetDivider()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                SettingsRow {
                    Text("Open iOS Settings")
                } accessory: {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.muted)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("calendars.openSettings")
        } footer: {
            Text("To show your events, choose Full Access under Calendars in Elevate's settings. \(Self.privacyNote)")
                .foregroundStyle(Color.muted)
        }
    }

    private var restricted: some View {
        SettingsGroup(title: "Calendar access") {
            Text("Calendar access is restricted on this iPhone, for example by Screen Time.")
                .font(.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        } footer: {
            EmptyView()
        }
    }
}

// MARK: - Event row

/// One event on the selected day: its time, its calendar's color, title,
/// calendar and location. Opens Apple's event view when it can.
struct PersonalEventRow: View {
    var event: PersonalEvent
    /// The selected day, yyyy-MM-dd, which decides how a long event reads.
    var day: String
    var calendar: PersonalCalendarInfo?
    var onOpen: (() -> Void)?
    var identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth: CGFloat = 66

    private var title: String { event.title.isEmpty ? "Untitled event" : event.title }

    private var detail: String? {
        let parts = [calendar?.title, event.location].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var color: Color {
        calendar.map { Color(personal: $0.color) } ?? Color.muted
    }

    private var span: PersonalEventSpan {
        PersonalEventDays.span(of: event, on: day, calendar: PersonalEventDays.dayCalendar)
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// The first line and the quieter second line of the time column.
    private var times: (String, String?) {
        switch span {
        case .allDay: return ("All day", nil)
        case .timed(let start, let end): return (Self.time(start), start == end ? nil : Self.time(end))
        case .starts(let start): return (Self.time(start), "Starts")
        case .ends(let end): return ("Until", Self.time(end))
        }
    }

    private var spokenTime: String {
        switch span {
        case .allDay: return "All day"
        case .timed(let start, let end):
            return start == end ? Self.time(start) : "\(Self.time(start)) to \(Self.time(end))"
        case .starts(let start): return "Starts at \(Self.time(start))"
        case .ends(let end): return "Until \(Self.time(end))"
        }
    }

    private var spokenLabel: String {
        var parts = [title, spokenTime]
        if let name = calendar?.title, !name.isEmpty { parts.append("\(name) calendar") }
        if let location = event.location { parts.append(location) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        if let onOpen {
            Button(action: onOpen) { content(showsChevron: true) }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel(spokenLabel)
                .accessibilityHint("Shows the event's details")
                .accessibilityIdentifier(identifier)
        } else {
            content(showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
                .accessibilityIdentifier(identifier)
        }
    }

    private func content(showsChevron: Bool) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        return HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if !stacked { timeColumn.frame(width: timeWidth, alignment: .leading) }
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 3) {
                    if stacked {
                        Text([times.0, times.1].compactMap { $0 }.joined(separator: " – "))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.ink)
                    }
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Color.muted)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.faint)
            }
        }
        .padding(.horizontal, Metrics.page)
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }


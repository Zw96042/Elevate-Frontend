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


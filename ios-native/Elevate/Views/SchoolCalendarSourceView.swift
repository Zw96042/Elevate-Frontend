import SwiftUI

/// The school-year dates built into this version of Elevate, with the
/// district's public calendar. Term selection itself stays in
/// `AcademicCalendar`; this page only lists its documented 2026–27 dates.
/// Nothing is fetched from the district, and new years arrive with app updates.
struct SchoolCalendarSourceView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The Eanes ISD 2026–27 student calendar cited by `AcademicCalendar`.
    static let sourceURL = URL(string: "https://resources.finalsite.net/images/v1772560663/eanesisdnet/upu1dn8wbinzko3qfhub/2026-27STUDENTCALENDAR.pdf")

    private struct QuarterDates: Identifiable {
        var term: TermLabel
        var dates: String
        var spoken: String
        var id: String { term.shortName }
    }

    private static let quarters = [
        QuarterDates(term: .q1, dates: "Aug 13 – Oct 8, 2026", spoken: "August 13 to October 8, 2026"),
        QuarterDates(term: .q2, dates: "Oct 13 – Dec 18, 2026", spoken: "October 13 to December 18, 2026"),
        QuarterDates(term: .q3, dates: "Jan 5 – Mar 12, 2027", spoken: "January 5 to March 12, 2027"),
        QuarterDates(term: .q4, dates: "Mar 22 – May 21, 2027", spoken: "March 22 to May 21, 2027"),
    ]

    /// Whether today, as a district day, is still within the school year
    /// these dates cover (through July 2027).
    static func coversToday(_ date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return true }
        return year * 100 + month <= 2027_07
    }

    /// The Settings row's subtitle.
    static func summary(_ date: Date = Date()) -> String {
        coversToday(date) ? "2026–27 dates, built into this version" : "2027–28 dates aren't in this version"
    }

    var body: some View {
        let covered = Self.coversToday()
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                SettingsGroup(title: "2026–27 quarters") {
                    ForEach(Array(Self.quarters.enumerated()), id: \.element.id) { index, quarter in
                        if index > 0 { InsetDivider() }
                        quarterRow(quarter)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("From Eanes ISD's 2026–27 student calendar. Elevate uses these dates to pick the current term.")
                        if !covered {
                            Text("Elevate estimates terms until an app update adds the 2027–28 calendar.")
                                .accessibilityIdentifier("schoolCalendar.outOfRange")
                        }
                    }
                    .foregroundStyle(Color.muted)
                }

                if let url = Self.sourceURL {
                    SettingsGroup(title: "Source") {
                        Link(destination: url) {
                            SettingsRow {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("2026–27 student calendar")
                                    Text("Eanes ISD, PDF")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.muted)
                                }
                            } accessory: {
                                Image(systemName: "arrow.up.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.muted)
                                    .accessibilityHidden(true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityHint("Opens the district's calendar in Safari")
                        .accessibilityIdentifier("schoolCalendar.publicSource")
                    } footer: {
                        Text("These dates are built into this version of Elevate, not fetched from the district. New school years arrive with app updates.")
                            .foregroundStyle(Color.muted)
                    }
                }
            }
            .padding(.horizontal, Metrics.page)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .softScrollEdges()
        .navigationTitle("School Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("schoolCalendar.screen")
    }

    /// The quarter and its dates. The full date range is long, so it moves
    /// beneath the name from xxLarge text, before it can crowd the name.
    private func quarterRow(_ quarter: QuarterDates) -> some View {
        let stacked = dynamicTypeSize >= .xxLarge
        return SettingsRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(quarter.term.displayName)
                if stacked {
                    Text(quarter.dates)
                        .foregroundStyle(Color.muted)
                }
            }
        } accessory: {
            if !stacked {
                Text(quarter.dates)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quarter.term.displayName)
        .accessibilityValue(quarter.spoken)
        .accessibilityIdentifier("schoolCalendar.quarter.\(quarter.term.shortName)")
    }
}

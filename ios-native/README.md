# Elevate (Native iOS)

A native Swift/SwiftUI rewrite of the React Native (Expo) app in `frontend/elevate`.
Zero third-party dependencies — Apple frameworks only.

The native rewrite is version **2.1.0** and requires iOS 17. The Expo **2.0.4**
security release remains the supported update path for iOS 15 and 16; do not
replace that compatibility release with this target.

## Requirements

- Xcode 26+ (project compiles the layered Icon Composer app icon)
- iOS 17+ (uses `@Observable`, Swift Charts `chartXSelection`)

## Build & run

```sh
open Elevate.xcodeproj          # run from Xcode, or:
xcodebuild -project Elevate.xcodeproj -target Elevate -sdk iphonesimulator build
```

CI also runs the Swift package tests, an unsigned Release simulator build, and
Xcode static analysis from `.github/workflows/ios.yml`.

Leave signing enabled when building an app to install and run in the simulator.
The CI `CODE_SIGNING_ALLOWED=NO` command verifies compilation only; running that
build can fail Keychain writes with error `-34018` because simulated entitlements
are missing. Use the normal Xcode run workflow or the signed build command above.

## Architecture

| Layer | Files | Replaces (RN app) |
|---|---|---|
| HTML parsing | `Parsing/MiniHTML.swift` | `node-html-parser` — small tolerant parser + CSS-selector engine |
| Skyward API | `Networking/Skyward*.swift` | `lib/api/skyward/*` — URLSession form posts, scraping, bounded data-only parsing of `sf_gridObjects` |
| Storage | `Services/Storage.swift` | AsyncStorage — credentials and sessions in **Keychain**, caches in UserDefaults |
| Services | `Services/DataService.swift` | `lib/services/*` — caching (30 min courses / 5 min grade info), request dedup, auto re-auth on session expiry |
| What-if | `Services/WhatIfStore.swift` | Added assignments, existing-assignment score estimates, and final exam estimates scoped to the active account |
| Business logic | `Logic/GradeMath.swift` | calculateGrades, gpaCalculator, semesterAverageCalculator, academicCalendar, formatClassName, unifiedGpaManager |
| State | `Store/AppStore.swift` | React context providers |
| UI | `Views/*.swift` | Expo Router screens — Courses, class detail (with what-if calculator), GPA (custom trend curve + manual entry, pushed from Courses), Attendance, Past courses + posted grade detail, Inbox + message detail, Settings |
| Theming | `Shared/Theme.swift` | New — selectable color palettes + light/dark override (Settings → Appearance), stored in the app group so widgets match |
| Widgets | `ElevateWidgets/` | New — WidgetKit extension: GPA, GPA Trend, School Pulse, Grades, Recent Grades, Missing Work, and Inbox. The app writes a `WidgetSnapshot` to the app group after each refresh (`Services/WidgetSnapshotBuilder.swift`) |

## Notes

- The app talks **directly to Skyward** (Eanes ISD base URL, same as the RN app);
  there is no backend dependency at runtime.
- The app target retains the released Expo app's `com.zachwilson.elevate` bundle
  identifier so the native rewrite ships as an update, not a separate app.
- On first launch after an Expo update, the app imports compatible SecureStore
  records, migrates supported AsyncStorage what-if data, invalidates legacy
  sessions, and removes plaintext legacy secrets before normal hydration.
- Semester grades use the district policy: `40% RC_a + 40% RC_b + 20% final exam`
  (RC grades rounded first), falling back to the RC average without an exam grade.
- GPA weighting: +10 for AP, +5 for Honors, with the same course-name exception
  lists as the original (`CourseLevelDetector`).
- The "showoff mode" easter egg and per-device skeleton sizing were intentionally
  not ported.
- The app and the widget extension share data through the app group
  `group.com.zacharywilson.elevate` (entitlements in `Config/`). Simulator
  builds work as-is; for device builds the app group must exist on the
  developer account — Xcode's automatic signing registers it on first build
  from Xcode.

## Interface and onboarding

Courses, Calendar and Inbox are the main tabs. On iOS 26+, native Liquid Glass
navigation has a separate Search button that expands across the bottom bar and
rises above the keyboard when tapped. The system handles focus and dismissal.
Search matches assignment titles,
classes and categories within the selected quarter, using official Calendar
assignments and their saved timestamps/coverage. Search runs locally; changing
a query does not make a network request. iOS 17–25 retains usable native tabs
and a Search destination.
Courses opens on the term's classes and grades, with a GPA line that opens the
full GPA history; each class holds its own assignments. Calendar combines
attendance and official assignment due dates. Only Skyward assignment metadata
marks missing work. Settings → School records contains Past courses, Documents,
Student Info and Fees. These pages load independently and retain their existing
account caches. The history widget link opens Past courses within Settings.
Past courses shows posted high-school semester grades by recorded school year
with read-only detail. Rows without a posted semester grade stay out of this
display. A unique complementary fall/spring pair of the exact same course is
shown together; repeated or conflicting records remain separate. Source caches
and GPA calculations keep their original records.
The `com.zacharywilson.elevate://gpa` link from
the GPA widgets opens GPA inside Courses, and the tab bar stays visible on
pushed screens.

The interface uses native SF Pro typography and an open composition: content sits
on the page, rows are divided by inset hairlines, and Courses and Inbox
use stable titles in the navigation bar's own row. GPA and other pushed
screens keep centered inline titles while content scrolls. Data screens use a common
control line: the term or school year on the left and when the data was fetched
on the right. The category breakdown and the semester's 40/40/20 composition are
open rows and figures, not bordered tables. Course averages have a restrained
outer ring with an unfilled center and their numeric grade still visible.
Only the arc clamps at 100; grades above 100 retain their value. Large text
stacks rows instead of squeezing columns.
First-load placeholders use static, theme-aware bars at the content's text
sizes and in each page's actual columns. They announce loading once; saved
content stays visible during refreshes.

Automatic term selection uses the [official Eanes 2026–27 student calendar](https://resources.finalsite.net/images/v1772560663/eanesisdnet/upu1dn8wbinzko3qfhub/2026-27STUDENTCALENDAR.pdf)
in the district's America/Chicago timezone:

| Quarter | First day | Last day |
| --- | --- | --- |
| 1 | August 13, 2026 | October 8, 2026 |
| 2 | October 13, 2026 | December 18, 2026 |
| 3 | January 5, 2027 | March 12, 2027 |
| 4 | March 22, 2027 | May 21, 2027 |

Inter-quarter breaks keep the preceding quarter until the next starts.
After the fall or spring semester ends, Courses selects that semester for
review; Calendar keeps its last quarter. Both follow date changes on activation
while preserving independent manual choices. These verified dates apply only
to 2026–27; other years retain the existing approximate calendar until their
district dates are provided.

Choices are one family (`Views/Components.swift`): plain rows with a check on
the chosen one. The term and school year are scope buttons (value and a small
muted chevron on a quiet well surface) that open a short sheet of those rows, sized to its content; terms are
grouped by Fall and Spring semester and name the quarters a semester combines.
Weighted/Unweighted and similar two-way choices are an inline pair of plain
buttons with a quiet fill on the chosen one. Sort and filter, Display, and the
add-assignment category and status use the same rows. No menus or segmented
controls are used for choosing.

The Courses list fills the visible screen: `ViewportFillStack` measures each
row's natural height and gives every class the same share of the height left
above the tab bar, so seven or eight classes end just above it. Small phones,
long names, and accessibility text sizes keep natural heights and scroll.
Teacher and sender names pass through `PersonName`: single-case names become
proper-noun case (hyphens, apostrophes, initials, II–IV), and names already in
mixed case are kept as written.

The GPA trend is a short custom curve, after the legacy app's chart. Touching it
places a dot on the curve and names the nearest term; letting go clears it. It
offers VoiceOver an audio graph and term-by-term adjustment, and is replaced by a
list of terms at accessibility text sizes. Reduce Motion removes the draw-in and
other movement.

Appearance offers six composed themes: Classic, Lab, Dusk, Paper, Field, and Ember.
Each defines its page, text, secondary text, hairlines, action, button, selection,
pressed, chart line and fill, attention, and warning colors separately for light and
dark mode. Themes change only color. Existing stored palette IDs and custom accents
remain compatible with widgets. Classic uses navy and cobalt; Lab reserves color
for signals; Dusk is composed for evening use; Paper uses ivory, sepia and claret;
Field uses stone and spruce; Ember uses sand and clay. The chooser shows each
theme’s actual light/dark text, control, and chart roles. Custom keeps the original
chosen RGB color and derives readable display tones for each appearance.

What-if mode edits earned points on existing assignments as well as adding work.
Weighted estimates retain decimal point inputs, round each category's weighted
contribution to two decimals, and then sum those contributions. This matches
observed Eanes Skyward totals; category averages are not rounded before weighting.
Enabling editing alone keeps the posted grade. An estimate requires an effective
local change; an unavailable edited quarter cannot become a numeric semester estimate.
With no score focused, tapping an assignment starts editing. During editing,
score taps switch directly to another score; titles, metadata, and blank space
save and dismiss the keyboard. Focused scores retain full precision.
Tapping outside a score field commits the edit and dismisses the keyboard.
Edits persist locally for the active account and quarter; semester estimates use
the corresponding quarters and the existing district formula. Turning What-if off
shows official scores. Restore returns one score to Skyward's value; Reset clears
that term's local changes. No grade edits are sent to Skyward.


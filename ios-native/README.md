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
Xcode static analysis from the repository root `.github/workflows/ios.yml`.

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

A verified empty gradebook shows No assignments; a verified empty inbox shows a
drawn envelope with "You're all caught up", centered on the screen.
Malformed responses and session failures retain an error/retry state. Saved data
uses its actual cache timestamp, and a quarter's error cannot appear on another
quarter. Refresh keeps saved content visible while reporting Updating.

The updated skippable feature introduction appears once for everyone, including
students who completed the earlier introduction or already have a saved login.
The new completion version is saved after finishing, so it does not repeat on
later launches. Connected students can Skip or Continue directly into Elevate.
Without a saved login, Skip opens the shared Skyward sign-in form; Back returns
to the introduction, and Not now or a verified login finishes it.
The ten-page tour covers grades/Inbox, What-if/scenarios/goals, GPA/converter, credits and school records, Calendar/This week/Done, widgets, notifications, the direct Skyward connection, theme choices, and an optional App Lock. Theme and System/Light/Dark selections preview immediately and persist through the same settings used elsewhere. Notification permission is requested only after an explicit tap; grades never appear in alert content.

App Lock is off by default. Enabling it requires successful iOS device-owner authentication, using Face ID, Touch ID, or the device passcode. It covers app screens and accessibility while locked or inactive, relocks in the background, and waits to open notification/widget destinations until unlocked. It does not alter Keychain protection, background refresh, or widget/notification privacy settings. People using iOS's Home Screen Require Face ID must turn that separate setting off themselves to restore detailed previews. The updated completion flag is v3, so people who completed an earlier tour see these additions once. There is no replay button in Settings.

The lock cover uses the standalone E mark and a frosted, theme-aware background. Only a tiny blurred color sample of previously visible content can appear behind it; Reduce Transparency uses a solid background. No cover image is saved.

For Debug simulator previews, launch with `-SampleData` to open synthetic school
data, or `-SampleData -ShowOnboarding` to force the introduction without changing
its completion flag. Add `-EmptyAssignments`, `-EmptyInbox`, or
`-FailSecondQuarter` for bounded empty/error-state checks with synthetic data.
These arguments do not alter Release behavior. Use a
separate simulator when capturing account screens to keep saved logins private.

## Course changes and notifications

Courses shows a quiet signed change beside each official average, comparing it
with the last average actually viewed for that account, course/year, and term.
The first known grade establishes a baseline silently. The comparison stays
stable through refreshes and navigation for the current foreground session;
the next session compares against the latest viewed value. Covered screens,
other tabs, background hydration, and what-if estimates never advance viewing
history. Missing grades reset their baseline instead of becoming zero.

Settings → Notifications now provides optional local grade alerts, personal
reminders and permission status. Alerts always include available class and
assignment/reminder names, never numeric grades. The former alert-content
section and its saved flags are retired. Grade changes
are off until explicitly enabled. Only fresh successful official observations
advance the separate notification ledger; disk hydration and what-if edits do
not. First observations seed silently; changes at hundredth-point precision are grouped.
Foreground checks are silent and retain unseen changes for a later validated background check. Grade banners never present while Elevate is open. Actual visible
official grades acknowledge their course and term; old caches, offscreen grades and
What-if estimates never acknowledge newer unseen changes. Assignment updates with
an unchanged course average are not detected by this observer. iOS chooses background
execution. Checks request eligibility after 15 minutes and preserve earlier pending
requests. Skyward credentials and sessions remain in device-only Keychain storage,
available to background checks after the first unlock following a restart,
including while the screen is locked. Expired sessions use the normal
saved-credential login and retry. Existing records upgrade on a successful read.
The [notification notes](docs/GRADE_NOTIFICATIONS_PLAN.md) explain delivery and
background limitations. No server, APNs registration, or credential upload is added.

Missing Work, Inbox, and grade-free School Pulse lead the widget gallery; optional GPA and grade widgets remain available. All seven kinds reload the shared selected palette and appearance for their timelines. Full-color Home Screen widgets follow System/Light/Dark; system-rendered lock-screen and accented widgets retain iOS rendering. Incomplete missing-work counts are lower bounds, never verified clear totals. Foreground activation independently retries incomplete assignment snapshots with a five-minute cooldown, including when the course cache is fresh. GPA also
supports inline, circular, and rectangular lock-screen families. Widgets retain
section-specific stale indicators and internal completeness tracking, privacy-sensitive content, and their
existing navigation links. WidgetKit controls timeline refresh scheduling.

All years GPA trends retain each school year separately, from PR1 through SM2,
including manual semesters only for years without Skyward history. Repeated
term names include their school year in the chart readout and accessibility.
Known semester classes offer only their own quarter/semester terms in detail;
full-year and unknown-duration classes retain all terms.

## App icon

`Elevate/icon_themed.icon` is the original Icon Composer document retained from
the Expo app, including its light, dark, tinted, and lighting effects. Both native
build configurations select `icon_themed` as the primary icon. Keep the document
and its layers intact; do not substitute a flattened PNG for the app icon.

The main tabs are Courses, Calendar and Inbox, with a separate Search destination. Calendar combines
attendance with official assignment due dates for the selected quarter; Missing
comes from Skyward assignment metadata, never from an attendance coincidence.
Settings → School records groups Past courses, read-only Fees (with Payments), Student Info, and Documents.
Fees also links to Eanes ISD's public RevTrak payment site in the browser.
Skyward credentials and session tokens are not forwarded; checkout stays on the
district's payment site.
Documents preview supported PDFs/images with Quick Look and offer Save or share,
including Save to Files. All school requests remain direct to Skyward. See
[school-data integration](docs/SCHOOL_DATA_INTEGRATION.md) for source contracts,
cache behavior, session recovery, and file lifecycle.

## Grade planning and context

Class detail → Grade goal solves a named assignment or semester exam using the
same calculator as What-if. Results keep their important input assumptions visible;
calculation details and scenario explanations start collapsed. Other ungraded work
and end-of-quarter assumptions are explicit. Required scores are rounded upward to hundredth-point precision
and checked through the forward calculation. Merely opening a plan never
changes official or saved hypothetical scores.

GPA → GPA converter shows completed semester grades on both generic scales
at once: unweighted out of4.0 and weighted out of5.0, with bonuses explained.
Year details show both; conversion rules and skipped records stay expandable.
The district percentage GPA is unchanged. My Colleges is temporarily removed
from navigation and onboarding; its code and saved selections are retained.
The retained114 college profiles contain sourced
cohort figures and academic preparation guidance. UC, UGA, UF, FSU and UCF profiles
estimate completed grades using their published policies with explicit course
classification and letter-grade assumptions. Unpublished formulas have no
fabricated college-specific estimate. Unknown subjects or unverified bonus
rules withhold a total and explain why. Cohort shares are never a student's
percentile or admission probability. Sources and reporting limits stay in each
profile and [COLLEGE_GPA.md](docs/COLLEGE_GPA.md). Bundled admissions details add
separately sourced test ranges, applicant/admission figures and subject preparation.
Every statistic retains its cohort and population; SAT section ranges are not
combined into a fabricated total. Personal preparation compares known local
high-school credit estimates and current enrollment, including saved source-bound
corrections. It does not certify college eligibility or infer missing course sequences.
Update `Elevate/Resources/CollegeAdmissions.json` with primary publications;
keep exact counts, approximate counts, means and middle-50% ranges distinct.

Courses → Missing work reuses official quarter assignment data and teacher
metadata. It retains checked-course coverage and saved timestamps; an unchecked
class never becomes a reassuring zero. Personal reminders are available from
assignment options, Calendar, and Missing work. A reminder is a local date chosen
by the student, separate from the official due date and submission status.
Calendar, Search, Missing work, This week, assignment reminders and refreshed
assignment widgets open the exact official quarter row. Widget links carry opaque
account/course/assignment identifiers and wait for account activation and App Lock.
Unavailable rows show a message instead of guessing by title. Grade breakdown
starts collapsed, and future-quarter/empty gradebooks retain explicit unposted states.
Pull refresh starts only with a new downward touch at the resting top; returning
from lower content and momentum bounces do not count as refresh pulls.

The internal grade journal retains fresh official observations. Calendar → This
week moves checked assignments out of active work into a reversible Done section
without changing Skyward's Missing status or cancelling reminders. Class detail offers saved What-if scenarios and assignment
impact estimates. GPA → Course plan estimates credits automatically from completed historical
semesters, with corrections and separate expected credits from live current
enrollment and planned courses. Unknown metadata stays reviewable. Settings → App updates checks Apple's public
version and release notes; native code updates still use App Store/TestFlight.
My Colleges is temporarily removed from navigation and onboarding. Its implementation
and account-local selections are retained for a possible return. The shared bottom
Search searches assignments. The dormant college routes have no app entry point or
college URL handler. An exact
4.0 unweighted is the ceiling; published cohort percentages are not personal ranks.
See [on-device planning](docs/STUDENT_PLANNING.md) for scope, storage and limits.

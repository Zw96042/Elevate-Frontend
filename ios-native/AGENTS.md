# Elevate native iOS

Native Swift/SwiftUI Skyward client, using Apple frameworks only. This iOS 17+ rewrite is separate from the Expo compatibility release for iOS 15/16.

## Where to work

- `Elevate/Parsing/` and `Elevate/Networking/`: tolerant HTML/data parsing and Skyward requests.
- `Elevate/Logic/GradeMath.swift`: grades/GPA policy.
- `Elevate/Services/` and `Elevate/Store/`: credentials, caches, migration, refresh, and app state.
- `Elevate/Views/`: SwiftUI screens.
- `Shared/`, `ElevateWidgets/`, and `Config/`: theme/snapshot contract, widgets, and entitlements.
- `Package.swift` and `Tests/ElevateCoreTests/`: the macOS-testable core subset.
- `.github/workflows/ios.yml`: Swift tests, unsigned Release simulator build, and analysis.

## Local commands

Use Xcode 26+; the package requires Swift tools 6.0. Open `Elevate.xcodeproj` for device/simulator UI work.

- `swift test`
- `xcodebuild -project Elevate.xcodeproj -scheme Elevate -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- Use the same Xcode command with `analyze` for static analysis, as in CI.

For interactive simulator runs, build with signing enabled (Xcode's default):

```sh
xcodebuild -project Elevate.xcodeproj -scheme Elevate -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

Do not use `CODE_SIGNING_ALLOWED=NO` for an app you install and run. The unsigned
CI command checks compilation only; it omits simulated entitlements needed for
Keychain access and can cause secure-storage error `-34018` during login. Keep
credentials in Keychain; fix the build rather than weakening storage.

## Compatibility and data contracts

Preserve the released app bundle identifier and shared app-group entitlement. Credentials/sessions belong in Keychain; caches belong in UserDefaults. Retain the Expo migration that imports supported data, invalidates old sessions, and removes plaintext secrets. Treat scraped JavaScript-like values as bounded data, never executable script.

The district semester formula is 40% + 40% + 20% with RC grades rounded first and RC-average fallback when no exam grade exists. Keep AP/Honors weighting and existing course exceptions aligned with tests. The native target must not replace the older-iOS Expo update path.

## Interface direction

The Past courses semester archive displays rows with at least one posted SM1 or
SM2 value (including zero/pass codes). It can combine a unique exact-name,
same-year fall/spring pair with disjoint source grades; ambiguous or conflicting
repeats remain separate. This is a display projection only: keep raw transcript
records, cache identities, and GPA inputs intact. Missing semester grades do not
establish a dropped enrollment status.

Navigation has Courses, Calendar and Inbox, with a separate assignment Search
destination. iOS 26+ uses the native detached Liquid Glass search-role tab,
with TabView-level searchable and search-tab activation so the field expands
across the bottom bar above the keyboard;
iOS 17–25 retains native fallback tabs. Settings → School records groups Past
courses, Documents, Student Info and Fees. Search matches official selected-quarter
Calendar assignments locally by title, class and category, retaining freshness,
failed-course coverage, empty/error states and account reset. No network request
per query, no What-if values or implied all-year coverage. Past courses retains
source school years and immutable posted grades; detail is read-only and never
requests live assignments. Without verified current-year provenance, show
recorded years with an explanatory note. Attendance keeps source descriptions
and periods, with its independent account cache. Calendar joins school dates
without classifying every attendance record as absence or inferring missing
work from attendance. Assignment metadata determines Missing/Absent/No count.
Calendar is the school year as scrolling months, as in iOS Calendar: a flat,
deliberately non-lazy list of month headers and week rows (`CalendarGridItem`)
with exact heights, so jumps and zooms land precisely. The zoom is continuous
(`Logic/CalendarZoom.swift`, 0 compact … 3 details, whole numbers are the
saved `CalendarDensity` levels): a pinch morphs every week frame by frame
through color strips, bars spanning the days an event covers, titled chips and
timed chips, keeps the point under the fingers in place, and settles on the
nearest level; the Detail menu animates through the same values for VoiceOver.
Each week is one animatable `Canvas` (`CalendarWeekCanvas`) with its day tap
targets outside it (`CalendarDayTargets`, taps rather than Buttons so ending
a pinch never opens a day). `Views/CalendarGridModel.swift` owns the zoom,
anchoring and every week's input, built from `CalendarSnapshot` once per data
change; only `CalendarMonthList` reads the zoom, so a pinch frame never looks
data up or re-renders the rest of the page. Theme colors are cached
(`Color.shared` in `Shared/Theme.swift`) because a fresh dynamic `UIColor`
makes SwiftUI re-lay-out every Text using it on every update. Tapping a day
pushes `CalendarRoute.day`, a day view that pages sideways between days, with
a week strip, what's due, events and attendance. A day's number is shaded by every Skyward assignment due
(`CalendarDayLoad`, five steps of the action color, never a hue, real counts
in VoiceOver); attendance is a separate corner dot; personal events never
change the shade. Graded work (`CalendarAssignment.isDoneByGrade`: a posted
score, grade or points, and not marked Missing) shows as done; ungraded work
keeps the personal Done ring (same store, account guard and duplicate-row
rule via `AssignmentCompletion.ambiguousIDs`). Assignments are kept per
quarter in `AppStore.calendarQuarters`; opening Calendar requests every
quarter, one after another (saved quarters only when due), so nothing arrives
or shifts while scrolling (`CalendarQuarterMap` maps school dates to quarters
through `AcademicCalendar`), and nothing is evicted. `SkywardHTTP` retries
transient connection errors (a dropped or flaky cellular connection) twice
with a short backoff before reporting a network error, and reports
cancellation as cancellation, never as a failure. Search still works in its
own selected quarter (`calendarTerm`) and never discards another quarter's
data. Calendar retains undated work (the "undated" pill), Missing flags (the
"missing" pill and the day view), failed-course coverage, and saved source
timestamps; its status area is at most a freshness row with pills, one
coverage line and a one-line invitation, never a paragraph. Requests use only
current-grade courses with real gradebook params and that quarter's semester
identity. Local what-if work stays out of
Calendar.
Calendar can also show the iPhone's own calendars (Google through the iOS
account, iCloud, subscriptions) via EventKit full access, requested only from
its invitation or Calendars sheet. Every calendar is opt-in (selection v2):
right after access is granted the Calendars sheet opens with all of them off.
`Services/PersonalCalendarStore.swift` reads the grid's months (at most 14,
around today) only while Calendar or its day view is on screen and keeps
events in memory, through a tab switch or a pushed page but not into the
background or past sign-out; only the calendar selection is saved,
device-level. Sheets use `SheetHeader` (title and a round check), not a
navigation bar. Elevate never
adds, edits or deletes events, so its detail sheet is its own read-only view
rather than `EKEventViewController`. Personal events stay out of This week,
Search, widgets and Skyward wording. Debug `-SampleData` uses synthetic
calendars; add `-SampleCalendarInvitation` or `-SystemCalendars` for the
pre-access state or the simulator's real calendars; `-SlowCalendarQuarterPreview Q2`,
`-CalendarQuarterErrorPreview Q2` and `-FutureQuarterPreview` show one
quarter loading, failing, or verified empty before its start. The calendar grid
is task-specific; do not introduce app-wide grids. The `://gpa` deep link replaces
the Courses path; `://attendance` opens Calendar and `://history` opens Past
courses inside Settings. The router lives in `Views/AppRouter.swift`.

Automatic term selection uses the official Eanes 2026–27 calendar in Gregorian
America/Chicago days: Q1 August 13–October 8; Q2 October 13–December 18;
Q3 January 5–March 12; Q4 March 22–May 21. Keep the preceding quarter across the
October and March breaks, then semester review after each semester ends.
The verified schedule is specific to August 2026–July 2027; other years retain
the documented legacy approximation. Courses and Calendar each follow the
current term on activation only while the user follows their last automatic
selection. Preserve independent manual selections and cancel stale Calendar
requests when its automatically selected quarter changes.

Use clean native sans typography and an open composition: content on the page,
selective inset hairlines, and safe areas applied once. Courses and Inbox
use a fixed left-aligned `RootHeader` through `screenTitle` and a top safe-area
inset, with the root navigation bar hidden. Pushed destinations explicitly restore
the navigation bar; the root heading keeps its position and size on scroll. GPA
and message detail keep centered inline titles. Class detail shows its full,
wrapping centered course heading at the content top; its inline title appears
after that heading scrolls away. Courses rows wrap complete names at every text
size. Heights are
content-driven with no filler spacers, except the Courses list: its rows share
the visible height above the tab bar through `ViewportFillStack` (measured
natural heights plus equal shares, capped; natural heights and scrolling on
small phones, long names, and accessibility sizes). The category breakdown and
semester composition are open rows/figures, not bordered tables; a category row
shows its share of the grade, any renormalized share, points, and average. Show
course level (AP/Honors) only where GPA math is explained. Do not use bordered
tables, app-wide grids, boxed control or stat strips, course grids, floating cards,
serif display type, decorative eyebrow labels, middle-dot separators, grade
rings, or underlined term tabs. Keep headings, numbers, and controls readable
from 375×667 to large phones and at large text sizes; use explicit
`dynamicTypeSize` branches, never `ViewThatFits` inside list rows.

The user's later styling request permits a restrained outer ring around each
Courses average, with an unfilled center and the numeric grade still readable.
Only the arc clamps to 0–100; source grades above 100 remain visible. Missing
grades stay unavailable, not zero progress. The former Records root is retired; its destinations use open rows in Settings.

Choices use one family from `Views/Components.swift`: scope buttons (value and
small muted chevron on the quiet well surface of `QuietButtonStyle`) opening a
content-fit `ChoiceSheet` of check rows (term, school year), `InlineChoice`
pairs for two-way choices (chart series), and `ChoiceList` rows elsewhere. The
user rejected native menus, segmented controls, and up-down chevrons for these scope selectors. Assignment sorting and filtering use native Menu submenus, not a sheet.
Group labels are quiet sentence-case footnotes, not headings or eyebrows. Format
people's names with `PersonName`, never the course-title formatter.

Term selection should make quarter/semester relationships explicit. Preserve
native bottom-tab continuity in detail screens, actual chart scrubbing, and
Reduce Motion behavior. The Courses GPA line and the GPA screen read the same
`GPAReport`/`GPACalculator` path. Themes in `Shared/Theme.swift` set every color
role per appearance; keep IDs and `Color.themeAccent` for widgets. What-if edits remain local and account/quarter scoped;
turning the mode off shows official grades. An estimate is marked by an inline
"Estimate" beside the class grade (no eyebrow) and its difference from Skyward;
Add sits on the Assignments heading in what-if mode. With no field focused, tapping an editable row
focuses its earned-points field and selects the score. While editing, only a score
tap continues or switches editing; title, metadata, padding, or blank-space taps
commit and dismiss. Explicit options retain their own actions. Added assignments default to "What-if assignment" and can
change category using that assignment's quarter choices, preserving its other
values.
Existing assignments also offer Make no count / Count in estimate. Exclusions
remain local and independent of score edits; a status-only override continues
following newly fetched Skyward scores. Only an actual score difference shows
the original-score note and Restore Skyward Score. Restoring that score preserves
the independent no-count choice; reset clears both changes.
A verified empty response is an empty state, while session, transport, and
malformed-response failures remain errors.
Show cached data's true timestamp and preserve saved content while refreshing.


## Grade viewing history and widgets

`GradeChangeTracker` compares official course averages with the last actually
viewed value, scoped to the account, course/year identity, and term. The Courses
caller gates observation on active scene, selected tab, empty navigation path,
and uncovered content, including scope sheets. Keep the foreground comparison
baseline fixed through navigation and refreshes; end it on background. Fetches
must not mark hidden grades seen. What-if values never enter this history.
Notification detection/delivery uses separate account-scoped observation and
delivery state in GradeNotificationLedger and SchoolNotifications. Accept only
validated fresh official course observations, never cache hydration or What-if.
First observations seed silently; pending retries coalesce to current grades.
Grade notifications detect changes at posted hundredth precision and serialize
fresh observations through delivery. Foreground fetches stay silent and never
imply viewing; retain unseen pending changes for a validated background check.
Only background-origin observations while UIKit is backgrounded can schedule;
foreground grade presentation stays suppressed with unseen requests retryable.
Settings records the last successful background observation separately.
Only active, uncovered viewport-visible official grades acknowledge their own
course/term and displayed revision; older caches and What-if do not consume
newer pending changes. Preserve request associations for foreground suppression.
BGTaskScheduler checks are opportunistic, request eligibility after 15 minutes,
and preserve an earlier pending request. Skyward credentials and sessions use
device-only AfterFirstUnlock Keychain protection, enabling normal re-authentication
while locked after the first unlock following a restart. Existing records upgrade
protection on a successful decoded read without rewriting their payload. Nonsecret
scheduling state may resubmit before first unlock but cannot authorize network
access. Reminders and lock-screen previews are explicit account choices.
See `docs/GRADE_NOTIFICATIONS_PLAN.md` for delivery limitations.


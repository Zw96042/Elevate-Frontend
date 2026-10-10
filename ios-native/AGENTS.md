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


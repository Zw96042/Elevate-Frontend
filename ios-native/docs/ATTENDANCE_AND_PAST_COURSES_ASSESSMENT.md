# Attendance and Past courses: implementation assessment

Investigated October 3, 2026. Scope: native iOS app; legacy Expo is a reference.
Implemented October 3, 2026; navigation revised October 4. Calendar combines
attendance with quarter-scoped assignment due dates. Past courses is under
Records alongside Documents, Student Info, and Fees.

## Implemented contracts

- Attendance uses `POST sfattendance001.w` with shared session fields. Private read-only structural inspection verified a single attendance-history HTML table with Date, Attendance, Period, and Class columns. Dates include weekday/month text. Skyward legally omits the closing tbody tag; complete row, cell, and table closures remain required. Other/malformed/multiple-student tables are errors. Source descriptions remain intact; no percentages, invented code meanings, totals, year selector, or pagination claims.
- The source's four-column “No absences or tardies were found.” row is a verified empty history, alongside the existing no-record markers. Linked, repeated, incorrectly spanned, or record-mixed markers remain errors.
- Attendance has a 30-minute account cache, shared requests, one session retry, stale-response/cancellation guards, and independent loading/error/freshness state. Offline refresh retains saved records and their timestamp. Explicit unavailable and verified empty responses are distinct.
- History reuses combined academic data and retains exact source year/row identity. Posted grades are snapshotted before live gradebook merging. Injected live courses are excluded from the archive. Current-year filtering requires independent verified provenance; otherwise the UI explains that recorded years are shown. Source support remains the existing high-school subset (not credits or a complete transcript).
- Past course details show posted quarter/exam/semester grades without live assignment or what-if requests. Old caches without year metadata require refresh rather than a fabricated empty history.
- GPA/semester calculation policy and existing live course identities remain intact. Course-detail numeric displays use up to two decimals without rounding input or stored estimates.

The original investigation below records the evidence and limitations that led to this implementation.

## Findings

| Page | Existing support | Remaining work |
| --- | --- | --- |
| Past courses | Native authentication, academic-history request/parser, unified course state, account cache, historical grades and GPA | Navigation and a read-only history screen; retain school-year and row identity for reliable grouping/filtering |
| Attendance | Shared authentication, HTTP transport, bounded parsers, account-cache infrastructure | Verify the actual Eanes Student Access request; add attendance model, parser, service/cache/state and screen |

Neither page requires a developer-operated backend or a dependency on Expo.
Attendance is available in Eanes Family Access according to the district, but
this investigation did not authenticate to verify availability under a student
login or establish its endpoint and response schema.

## Past courses: the API already exists

`SkywardHistoryAPI.fetchCombinedAcademicData` concurrently loads:

- `POST sfacademichistory001.w`, relative to the configured Skyward base URL.
  Form fields: `dwd`, `wfaacl`, `encses`.
- `POST sfgradebook001.w` for the current gradebook, with shared session fields:
  `dwd`, `wfaacl`, `encses`, `User-Type`, `sessionid`.

The history response is HTML containing `sf_gridObjects`. It is parsed as
bounded data with `JavaScriptLiteralParser`, never evaluated as JavaScript.
Compatible `gradeGrid_*` rows contain school-year/grade headers and course
grades. `HistoryCourse` retains name, term duration, PR1–PR8, RC1–RC4,
EX1–EX2, SM1–SM2, and a derived final-grade fallback.

`DataService.combinedCourses` already transforms this into `[UnifiedCourseData]`,
uses an account-scoped 30-minute cache, shares requests, and retries once after
session expiry. `AppStore.courses` holds historical and current courses. GPA
already consumes this data. A history screen can share that request and refresh
status rather than adding another independent transcript fetch.

### Limits to address before calling it a complete course history

- `UnifiedCourseTransformer` discards the academic-year dictionary key. It
  keeps `gradeYear` (9–12), but that is a grade level, not `2025-2026`.
- Transcript-only records lack original course/section/gradebook identity;
  current-year matching supplies those fields only for live gradebook rows.
  Duplicate transcript names receive storage-key suffixes, but the flattened
  model drops those suffixes when `courseName` is present. Repeated rows can
  therefore share an ID.
- The parser intentionally omits non-linked alternate records and all grade
  levels below 9. The existing data is a high-school GPA-oriented subset, not
  a complete transcript. Credits are not represented in the model.
- `AppStore.currentGradeLevel` chooses the highest recorded grade. Filtering
  to a lower grade is insufficient for repeated years, missing current-grade
  information, or completed courses in the current school year.
- `finalGrade` is a fallback chosen from semester/quarter values, not proof
  of an official annual final. Show separately labelled posted grades.
- Historical courses normally have no `hasGradebookParams`. Do not route them
  into the live assignment/what-if screen or invent assignment access.
  The existing detail request uses `httploader.p?file=sfgradebook001.w` and
  `viewGradeInfoDialog`, with no historical school-year selector. The current
  detail screen requests it without validating those IDs, and its grade
  headline requires a successful response before using historical fallback.
  A read-only posted-grade detail view is needed for transcript-only rows.

Recommended data change: retain an optional school-year key and a source row
key/origin alongside unified course data. Keep decoding compatible with saved
caches; refresh older records before claiming exact year grouping. Distinguish
the current academic year using verified current-gradebook context. Preserve
existing GPA inclusion rules; a broader transcript model should be separate if
alternate or pre-high-school credit is later included.

For an initial page, show previous school years and their posted grades. Whether
“Past courses” also includes completed semesters in the current year remains a
product-scope choice; it requires explicit semester and active-course evidence.

## Attendance: discovery must precede the parser

No attendance request, model, parser, screen or tests were found in either app.
Public sources confirm the feature, but no exact Eanes Student Access endpoint
or request contract was established. Do not implement a guessed
`sfattendance001.w` endpoint or assume a JSON REST response.

The next technical step is a read-only inspection of the Attendance page under
an authenticated Eanes student account. Establish:

1. Initial page URL/method and required session, student, school/entity,
   track and year fields, if any.
2. The response structure: HTML/grid data, calendar data, or follow-up dialogs.
3. Requests for year changes, date ranges, row details, pagination and the
   attendance-code legend, if provided.
4. Coverage: daily versus period records, dates, course/period identifiers,
   raw codes, descriptions, reasons, comments and any official totals.
5. Explicit evidence for zero records versus unavailable/disabled access,
   expired sessions, maintenance pages and unexpected schema.

Keep any live inspection private: do not save or print credentials, cookies,
session codes, raw student responses or screenshots. Record only structural
field names and types; build synthetic fixtures for parser tests.

### Proposed implementation after the contract is verified

- `Networking/SkywardAttendanceAPI.swift`: reuse `SkywardHTTP`, session
  validation and the existing data-only parsers as appropriate to the actual
  response. Keep parsing out of views.
- Attendance records: retain date-only school dates, daily/period granularity,
  raw code and source description, optional reason/course/period, and stable
  source identity. Preserve unknown codes; do not infer meanings from letters.
- `DataService`: load through the existing session-retry path, with coalescing,
  cancellation, generation guards and account/student/year-scoped caching.
- `AppStore`: independent records, loading/error/freshness state and refresh
  task; clear/cancel all of it on account changes and logout. Attendance failure
  must not prevent grades or Inbox from loading.
- Fetch on first attendance visit and refresh as needed. Do not multiply
  foreground network work solely because a new tab exists.
- Show source records and verified summaries. Period absences are not unique
  absent days; an exception-only feed does not establish total days present or
  an attendance percentage. Avoid calculating exam eligibility or credit risk
  from incomplete records.

Eanes distinguishes funded/unfunded absence codes. Westlake also describes
period-level records and a 24–36-hour update window. Preserve source meanings
and true refresh timestamps. Displaying attendance is the requested scope;
absence submission/correction would be a separate write feature.

## Navigation integration

The app currently declares Courses and Inbox in `ElevateApp.swift`, with tab
selection and widget deep links in `Views/AppRouter.swift`. Adding the requested
two destinations means extending both and giving each page its own navigation
state. Preserve Courses as the landing page, GPA inside Courses, existing widget
links, and the account-change reset for every account-bound pushed destination.

Reuse the fixed `screenTitle`, scope `ChoiceSheet`, `StatusStrip`, refresh,
login, empty and error components. History should own its selected year/term so
browsing it does not silently change the current Courses or GPA selection.
Update the two-tab description in native AGENTS/README when implementation
actually changes navigation. No final visual design was produced here.

## Verification for implementation

- History: exact year retention, duplicate names/rows, repeated grade years,
  missing current-grade evidence, half-year courses, posted zero/letter/missing
  grades, cache decoding, and unchanged GPA calculations.
- Attendance: verified populated/empty/unavailable pages; daily versus period
  records; multiple records on one day; unknown codes; date-only handling;
  pagination/year changes; malformed/truncated/maintenance/login responses.
- Services/store: session expiry retry; failed refresh keeps valid cache and
  original timestamp; account switch/logout during requests; independent
  attendance failures.
- UI: all four destinations, back/tab continuity, scope selection, sign-in,
  loading/empty/error/offline refresh, large text, VoiceOver, Reduce Motion.
- Run core tests, signed Debug simulator verification, unsigned Release build
  and analysis. Core tests exclude AppStore, DataService, auth API and views.

## Evidence and verification status

Local source reviewed: `Elevate/Networking/SkywardHistoryAPI.swift`,
`SkywardHTTP.swift`, `Models/Models.swift`, `Services/DataService.swift`,
`Store/AppStore.swift`, `Views/AppRouter.swift`, `ElevateApp.swift`, Courses/GPA/
ClassDetail views, history/merge tests, and legacy academic-history integration.

Public sources read October 3, 2026:

- [Eanes attendance](https://www.eanesisd.net/parents/attendance): Family Access
  records and district attendance-code descriptions.
- [Westlake attendance](https://whs.eanesisd.net/school/attendance): period
  absences and the source update window.
- [Skyward Family Access](https://www.skyward.com/products/student-information-system/family-engagement/family-access):
  attendance is a portal feature.
- [Google's Skyward SMS 2.0 integration setup](https://support.google.com/edu/classroom/answer/9356588?hl=en):
  its OneRoster route uses district setup/vendor keys and secrets. This is a
  separate integration route, not an endpoint usable with Elevate's existing
  student session. It does not establish an attendance API for this app.

No authenticated attendance request, live schema validation or UI/device test
was performed. Public third-party scraper listings did not establish an
attendance contract; they are not dependencies proposed for Elevate.

Observed baseline verification: `swift test` passed 96 tests in 12 suites;
`git diff --check` passed. No app build was run for this documentation-only
assessment. The passing tests verify existing core behavior, not attendance
support or the proposed navigation.

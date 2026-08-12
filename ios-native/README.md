# Elevate (Native iOS)

A native Swift/SwiftUI rewrite of the React Native (Expo) app in `frontend/elevate`.
Zero third-party dependencies — Apple frameworks only.

## Requirements

- Xcode 16+ (project uses filesystem-synchronized groups)
- iOS 17+ (uses `@Observable`, Swift Charts `chartXSelection`)

## Build & run

```sh
open Elevate.xcodeproj          # run from Xcode, or:
xcodebuild -project Elevate.xcodeproj -target Elevate -sdk iphonesimulator build
```

## Architecture

| Layer | Files | Replaces (RN app) |
|---|---|---|
| HTML parsing | `Parsing/MiniHTML.swift` | `node-html-parser` — small tolerant parser + CSS-selector engine |
| Skyward API | `Networking/Skyward*.swift` | `lib/api/skyward/*` — URLSession form posts, scraping, bounded data-only parsing of `sf_gridObjects` |
| Storage | `Services/Storage.swift` | AsyncStorage — credentials and sessions in **Keychain**, caches in UserDefaults |
| Services | `Services/DataService.swift` | `lib/services/*` — caching (30 min courses / 5 min grade info), request dedup, auto re-auth on session expiry |
| What-if | `Services/WhatIfStore.swift` | artificialAssignments / finalExamGrades AsyncStorage blobs |
| Business logic | `Logic/GradeMath.swift` | calculateGrades, gpaCalculator, semesterAverageCalculator, academicCalendar, formatClassName, unifiedGpaManager |
| State | `Store/AppStore.swift` | React context providers |
| UI | `Views/*.swift` | Expo Router screens — Courses, class detail (with what-if calculator), GPA (Swift Charts graph + manual entry), Inbox + message detail, Settings |
| Theming | `Shared/Theme.swift` | New — selectable color palettes + light/dark override (Settings → Appearance), stored in the app group so widgets match |
| Widgets | `ElevateWidgets/` | New — WidgetKit extension: GPA, GPA Trend, School Pulse, Grades, Recent Grades, Missing Work, and Inbox. The app writes a `WidgetSnapshot` to the app group after each refresh (`Services/WidgetSnapshotBuilder.swift`) |

## Notes

- The app talks **directly to Skyward** (Eanes ISD base URL, same as the RN app);
  there is no backend dependency at runtime.
- The app target retains the released Expo app's `com.zachwilson.elevate` bundle
  identifier so the native rewrite ships as an update, not a separate app.
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

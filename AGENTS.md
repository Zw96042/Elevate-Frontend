# Elevate / BetterSkyward frontend

An Expo/React Native student app for Skyward grades, assignments, GPA, inbox, and account sessions. The package name is `liquidglass`; the root README contains older framework-version notes, so use `package.json` for current versions.

This app is retained as a legacy reference. Active product development belongs in the
native app under `ios-native/` (see `ios-native/AGENTS.md`); consult this code for behavior, parsing, tests, and migration.
Only change this reference app when the current task explicitly calls for it.

## Map

- `app/`: Expo Router screens, tabs, and dynamic class/assignment/message routes.
- `lib/api/skyward/`: direct device-to-Skyward auth, grade, history, and message API calls.
- `lib/services/`: auth/data/message orchestration.
- `lib/utils/`: session, storage, account-cache, and parsing helpers.
- `context/`: shared application/data and bottom-sheet state.
- `utils/`: grade/GPA/calendar logic; `__tests__/`: unit and context regression tests.
- `jest.config.js` and `.github/workflows/frontend-tests.yml`: test discovery, coverage, and CI commands.
- `ios-native/`: the active native SwiftUI app; its CI is `.github/workflows/ios.yml`. Run Expo commands from the repository root and native commands from `ios-native/`.

## Commands

Use npm and the lockfile; CI uses Node 20.

- Setup: `npm ci`.
- Development: `npm start`; web: `npm run web`.
- Native build/run: `npm run ios` or `npm run android`.
- Lint: `npm run lint`.
- Tests: `npm test`; CI invocation: `npm test -- --ci --coverage`.
- Type checking, as in CI: `npx tsc --noEmit`.

Do not use the template `reset-project` script as a setup step. It is unrelated to the current app and its referenced script is absent in this checkout.

## Contracts

Preserve account-scoped caches and session isolation when switching users or completing asynchronous requests. Read the related auth/account race regression tests before changing context or service state.

Keep Skyward parsing and grade calculations in the existing helpers; do not duplicate district-specific logic in screens. Test missing periods, empty gradebooks, loading/error states, and stale responses where relevant. Avoid live student data in fixtures or logs.

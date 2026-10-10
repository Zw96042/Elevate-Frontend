# Grade-change notifications

Elevate detects official grade changes on the device and offers optional local alerts while preserving the direct-to-Skyward architecture. Reliable alerts while every device is closed would need an independent source of fresh grade data and a push service; APNs alone cannot discover changes.

Device-local alerts and reminders are now implemented, separately from the course-screen viewing indicator. Grade changes default off; reminder delivery defaults on; alerts always include available names and never numeric grades. Permission is requested only after an explicit enable/save action. No server, credential upload, or push registration is added. Background cadence remains unverified on a physical device. Settings records the last successful background observation separately from all grade checks and restores the existing account-scoped background status across cold launches; before an account is accessible, sign-in failures cannot be saved to that account. These local status fields are not an upload/report feature.

## Two baselines, different purposes

The course-screen indicator compares the current official average with the last average the student actually viewed, scoped to account, school year/course identity, and term. It keeps that comparison for the current foreground session. Viewing 96 after previously viewing 95 shows +1; the next viewing session starts from 96. What-if values never enter this history.

Notifications need a separate last-successfully-observed baseline and a delivery ledger. Displaying an official grade acknowledges only that course, term, and visible value (or an older pending value superseded by a newer display). Fetching data or reading an older cached grade must not erase a newer pending alert; delivering an alert must not change the viewing-session comparison.

| Piece | Responsibility |
| --- | --- |
| Official grade observer | Accept only validated successful Skyward results; compute the same official course averages as the app. |
| Change detector | Compare observations for the same account, student, course/year, and term; produce a small typed event. |
| Delivery coordinator | Apply preferences, grouping, and deduplication; request an alert and record its outcome. |

An event contains an opaque account/course key, term, previous/current values, discovery time, and stable revision or content-derived ID. Discovery time means when Elevate found the change, not when a teacher posted it. Keep raw HTML, credentials, cookies, and student names out of diagnostics.

Seed each new baseline silently. A missing grade becoming available is a distinct event, not a fabricated zero-to-grade jump. Semester/quarter transitions and account changes establish separate histories. Failed, incomplete, expired-session, cancelled, stale-account, and cached-only results must not produce new notifications. Grades above 100 and fractional changes remain valid.

Repeated identical results produce one event. Use a scoped transactional observation/event ledger so concurrent foreground/background fetches cannot duplicate it. Keep delivery state distinct from detection: scheduling accepted, displayed/read state where known, and retry state. Do not claim an accepted scheduling request was necessarily shown to the person.

## Implemented: device-local alerts

1. Settings includes grade changes, initially off, with an explanation before system permission is requested. Elevate remains usable when permission is denied. Apple's guidance recommends asking in context. [Notification permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).
2. Successful foreground refreshes feed the observer silently, retaining unseen pending changes without scheduling alerts. Only background-origin observations while the app is actually backgrounded can schedule one grouped alert; opening the app never produces grade banners. State is rechecked after authorization and scheduling; an unseen request suppressed on activation remains retryable. Courses acknowledges only grades whose rings are in the viewport, while active and uncovered; detail acknowledges its visible official grade for the selected term. Offscreen rows, old cached values, other terms, and What-if estimates do not acknowledge newer official changes. Checks serialize through scheduling, recheck viewed state before adding a request and during foreground presentation, and preserve retries.
3. One `BGTaskScheduler` app refresh task requests eligibility after 15 minutes, on account activation, alert enablement, background transitions, and each run. An earlier pending request is retained rather than postponed by each transition. iOS chooses execution time; `earliestBeginDate` is a lower bound, not an appointment. The handler checks cancellation and account ownership before fetching and handles expiration without replacing valid caches. [Background scheduling](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate).
4. A successful background observation combines changes from that fetch into one local notification. The system can deliver a scheduled local notification while Elevate is closed; the app still needs an opportunity to discover the grade change first. [Local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).
5. Changes at the posted hundredth-point precision alert, including rises and falls grouped by refresh. Sub-hundredth numerical noise does not alert. The old fixed half-point policy migrates without discarding pending retries or retroactively announcing older small changes. Course deltas retain their own viewing comparison. This observer checks course averages; a new or corrected assignment that leaves its course average unchanged does not produce a grade alert. Threshold controls, assignment-level background detection, digest, and quiet hours remain future work.
6. Grade alerts include available class names; reminders include the class and assignment or reminder title. Neither format includes numeric grades. There is no alert-content setting. Retired name/grade-preview flags are ignored without changing the saved grade-change/reminder choices. Account activation removes older pending/delivered content (versions1/2), restores future reminders with version3, and rejects old-format foreground requests. Missing names use a generic fallback. iOS preview settings and app locking may suppress content. Tapping validates the currently connected account before opening the course and term. Logout removes that account's pending alerts and local event history.

Skyward credentials and sessions use device-only `AfterFirstUnlock` Keychain protection. After one unlock following a restart, background checks can access them while the screen is locked. Existing native records upgrade their accessibility after a successful decoded read; the update changes only protection, preserving the saved value even if migration fails. This is a deliberate change from `WhenUnlocked`, expanding background access to authentication secrets. Normal requests try saved session codes, re-authenticate using the saved username/password on explicit session expiry, and retry once. A screen lock does not force a session-only path; before the first unlock, protected secrets remain unavailable. Logout/account cancellation guards remain in place. [Keychain background access](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly).

This needs no hosted Skyward credentials or revived backend. It provides opportunistic background alerts, not guaranteed near-real-time monitoring. Test it on physical devices before describing background cadence in product copy.

## If reliable closed-app monitoring becomes a requirement

A remote notification starts at a provider server, which addresses the device through APNs. [Remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server).

The unresolved dependency is how that server learns about grades:

- **Preferred:** a supported district/Skyward integration or authorized event feed. Confirm availability and district access; the current scraper establishes neither an API contract nor a webhook.
- **Alternative:** an explicitly opt-in hosted polling service. This changes the current privacy and architecture contract because the service needs authorized access to private school data. Decide district support, credential/session custody, account deletion, polling limits, operating costs, and consent before implementation. Do not silently upload the existing device's credentials.
- **Client-uploaded events:** useful for coordinating alerts across devices, but cannot discover a change when no device refreshes. Do not market this as closed-app monitoring.

Once a supported detection source is settled, use a small separate service: authenticated device registration → school refresh jobs → validated change detector → event/outbox ledger → APNs worker. Use encrypted secret storage when required, short retention, strict per-account access, bounded polling/backoff, and content-free operational logs. Store current APNs tokens and remove invalid registrations. Use event deduplication and notification collapse/grouping; reconcile on the next foreground fetch so an old push cannot replace newer grades.

Silent pushes are not a reliable workaround for on-device polling: Apple treats them as low priority and does not guarantee delivery. Visible pushes also depend on system/user delivery settings. [Background push behavior](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app).

## Delivery and remaining validation

1. **Implemented:** viewing-session course delta, separate local notification ledger, account-scoped reminders/preferences, contextual permission, privacy defaults, grouped grade alerts, background handler, and scoped tap routing.
2. **Delivery contract:** accepted scheduling is not proof of display. Pending events coalesce to the newest fresh grade and disappear on recovery or an actual matching/newer official display. Overlapping fresh checks serialize through delivery; request associations preserve foreground suppression after relaunch. Logout/account replacement removes owned requests. A nonsecret enabled hint permits locked-device resubmission only; protected credentials are still required for any fetch.
3. **Observed validation:** core regressions cover first-load silence, deduplication, fractions/bonus/missing grades, term isolation, pending retry coalescing/recovery, and transformed live-course eligibility. Synthetic simulator flows cover reminder saving with denied permission and removal. Independent source review covers account/routing/cancellation guards. Physical-device locked-screen Keychain access and re-authentication, background cadence, actual alert display, permission restoration, logout during scheduling, and stale-link races still need device verification.
4. **Remote decision:** establish the detection source and privacy contract before building or deploying the push service. Then validate APNs sandbox delivery, token rotation, retries, deletion, and multiple-device coordination.

Remote monitoring and digest/quiet-hour controls remain future decisions. Test physical-device background execution before making any cadence or reliability claim.

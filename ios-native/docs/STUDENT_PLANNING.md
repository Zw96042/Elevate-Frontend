# On-device planning and update information

The native app keeps planning records on this iPhone, scoped to the connected
account. These tools do not write to Skyward or change official grades.

## Internal grade journal

The journal has no entry on the main Courses screen. It observes fresh, validated official course averages and quarter
assignment responses. Initial observations establish a silent baseline. Cached
responses, What-if estimates, stale-account responses, and failed requests do
not create changes. Dates show when Elevate found a change, rather than when a
teacher entered it. Assignment renames can appear as first-seen assignments;
ambiguous duplicate identities do not produce guessed changes. Retention is
bounded to 90 days and 500 events. Clearing the journal is independent of the
viewing comparison and notification ledger.

## This week and personal Done marks

Calendar's quarter remains the source scope. The week window includes today
and the next six calendar days in America/Chicago, with explicit
missing statuses, personal reminders, and undated work shown separately.
Coverage and saved-data freshness remain visible. A personal Done mark never
clears a teacher's Missing status. Ambiguous duplicate assignment identities
cannot receive a personal mark. Marks are account-scoped and persist locally. Checked assignments leave every
active group and appear once in Done; unchecking restores them. Scheduled
reminders remain independent and are not cancelled by marking an assignment.

## Saved What-if scenarios and assignment impact

Named scenarios save the current What-if snapshot for one course and term.
Applying a snapshot replaces only that term's local assignments, score overrides
and final-exam estimate. It does not change official grades, other terms, or
independent GPA exclusions. Names may repeat. Storage permits 50 scenarios per
class and 500 per account, with a bounded encoded payload. Unreadable data stays
intact until an explicit reset. Stale assignment overrides or unavailable
edited quarters produce an explanation instead of being silently discarded.

Comparison uses the same grade calculator as the existing editor, including
weighted categories, report-card rounding, 40/40/20 semesters and missing-exam
fallback. Assignment impact starts with the official gradebook, changes the
selected earned score, and calculates forward. It does not treat a course
average as enough information to invent assignment weight. Semester analysis
requires the assignment's actual quarter source. No-count rows and unavailable
inputs cannot produce a supported impact estimate.

## Course plan

See [Course planning](COURSE_PLANNING.md) for the Westlake requirements template,
primary sources and limitations. Completed historical semester records provide
automatic credit estimates through a bounded subject catalog, including eligible
older/nonlinked records. Missing credit-award metadata and ambiguous courses
remain reviewable. Corrections replace the source allocation; additions cover
records genuinely absent from Skyward. Legacy manual entries are retained for
review to prevent counting them twice. The main screen does not show projected
GPA, a counselor checklist or source links. Live current enrollment contributes
separate expected credits if passed, alongside earned and future planned
credits. Undated enrollment uses its observed semester and fetch date; stale,
unknown or overlapping records remain reviewable. Official GPA is unchanged.

## Notification content

Alerts always include available class and assignment/reminder names. Numeric
grades have no input to either notification-text builder. The alert-content
section is removed; retired name/grade-preview flags are ignored while existing
grade-change and reminder choices are preserved. Account activation removes
older scheduled/delivered formats and restores future reminders with current
version3 content. Foreground delivery rejects older formats and stale accounts.
iOS preview settings and app locking can hide content at the system level.
Notification permission and delivery limits remain documented in
[Notification notes](GRADE_NOTIFICATIONS_PLAN.md).

## App update information

An explicit update check retrieves public version, minimum OS and release-note
text from Apple's App Store lookup for Elevate. It sends no Skyward credentials
or student data, uses a separate cookie-free session and retains the last
verified information if a later check fails. Saved information includes its
check date. A marketing-version comparison cannot establish the latest
TestFlight build. A newer Store version requiring a newer OS is distinguished
from an installable update.

This is non-executable release information. Native Swift code and interface
changes still require App Store or TestFlight distribution. The district
calendar remains built into the app; no remote district configuration feed or
developer backend is introduced. Apple restricts downloading code that changes
an app's features: [App Review guideline 2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements).

# School data in Records and Calendar

Fees, Student Info, and Documents under Records load directly from Skyward when visited.
They use the existing account session, a 30-minute account-scoped metadata cache,
coalesced requests, cancellation and generation guards. A failed refresh keeps
last-known-good data and its original timestamp. Reload all data includes pages
that have been visited. They do not add a server or background polling.

## Verified read-only requests

Fees also offers **Make a payment**, opening `https://eanes.revtrak.net/` in
the browser. This public destination was verified against [Eanes ISD's Online
Payments guidance](https://www.eanesisd.net/dept/bs/op) on October 4, 2026. The
native client currently supports Eanes ISD only. The link does not include
student identifiers, Skyward credentials, or session tokens; checkout stays on
the district's payment site.

All page requests are POSTs with `SkywardHTTP.sessionFields`.

| Page | Endpoint | Source contract |
| --- | --- | --- |
| Fees | `sffeemanagement001.w` | One `grid_FeesDet<digits>` table, 9 columns, and one `grid_PaymentsDet<digits>` table, 7 columns. All posted strings retained; no recomputed balance. A separate public payment link opens the district store in the browser. |
| Student Info | `sfstudentinfo001.w` | One selected-student grid, scoped contact/student/enrollment tables. School name, phone, and principal are in the enrollment table's first `th colspan=4`. Official grade comes from enrollment, never GPA. Family/guardian/sidebar data excluded. |
| Documents | `sfportfolio.w` | One `grid_attachments<digits>*<digits>` table: Description, Type, Created. Complete recognized empty grids remain empty; malformed/partial grids fail. |

Documents use verified delegated `sff.aee(..., '#anchorID')` handlers containing
`sfportfolio.eSignCheck(false,false,...)`. Bounded literal arguments are parsed,
never evaluated. Direct `blobLink` files use same-origin HTTPS
`qdirconfig<digits>.p` resources. Generated `addToQueue` reports send source
arguments to `httploader.p?file=sfmainhttp001.w` with `addToPrintQueue`, then
`checkPrintQueue` using transient queue ID/token. The XML `response/sff` metadata
assigns the request's literal `messages` and `options`; each response must match
its request ID. Q/R states poll at the vendor's 2-second then 5-second intervals,
limited to 12 polls and a 60-second deadline. A completed report's verified
`window.open` command is parsed only for its literal same-origin blob URL.
Neither commands nor page scripts execute. The app resolves handlers anew when
opened. Signature, external, and unknown handlers remain visible with Requires
Skyward; the app does not acknowledge or sign them.

Student photos use the same authenticated resource program with `StuPic`.
Only those photo sources inside the student contact section count as photos;
decorative images are ignored and repeated identical sources are deduplicated.
Distinct student-photo sources remain an ambiguity error.
Download/photo URLs containing session values remain transient. Binary loads
block cross-origin redirects, enforce size limits (4 MB photos, 20 MB documents),
check HTTP/session failures and file signatures, and accept supported images/PDFs.
An octet-stream document is accepted only when its signature identifies a supported
format. Photo failure leaves the textual profile available.

## Preview and saving

Quick Look previews local files in a protected, backup-excluded temporary
UUID directory. Filenames use sanitized document titles; tokens never enter paths. Closing, account changes,
and the next launch remove owned preview files; stale writes remove their own
files before returning. Save or share opens the system sheet, including Save to
Files. A copy saved by the user is owned by the chosen destination.

## Incomplete English course titles

Skyward can supply an Independent Study in English title ending at an opening
parenthesis. For these exact incomplete labels, the combined course refresh
reads the matching course's `sfdialogs.w` class-information popup to recover its
catalog code. The handler is parsed as bounded data, never executed, and its
quoted binding must match the link's name or CSS `#id` selector exactly. Its
student, course and section must match the requested row. LA145 (AP Seminar)
and LA146 (AP Research) receive the district's +10 AP bonus; LA147 and unknown
codes do not. The original Skyward title and saved course identity stay intact.
Missing or ambiguous popup metadata fails the refresh and preserves the previous
account cache rather than guessing a level. A complete title uses the existing
title classifier without an additional request.

## Session recovery

Explicit expired/timed-out/ended responses, login forms/redirects, and HTTP
401/403 and typed loader `options.status == "logout"` trigger one shared reauthentication and request retry. A late failure
from an older session reuses already-refreshed tokens. Account changes invalidate
old work. Maintenance/schema failures and verified empty data are not treated as
expiry. The separate website-login revocation signature has not been reproduced:
new API authentication still allowed populated responses using old tokens/cookies.

Live verification exported fixed outcomes only, with no personal values, photos,
PDFs, source responses, or session URLs. Synthetic tests cover parser failure
boundaries, token-free metadata, account/auth recovery, and preview cleanup.
Simulator checks cover new navigation, states, native PDF preview, and large text;
physical-device behavior is not asserted.

## Calendar

Calendar reuses the attendance API/cache and existing grade-info requests.
Assignments are official source records for an explicit quarter, using only
current-grade courses with valid gradebook parameters and the matching
semester. At most three course requests run concurrently. The aggregate
retains per-course cached/previous data on failures and names failed courses;
its saved time is the oldest contributing source timestamp. A known empty
class still counts as resolved. Account, quarter, course-list, request ownership,
and cancellation guards reject stale batches. Reload all data refreshes it only
once visited. No new backend or background notification polling is introduced.

School dates stay date-only ISO keys; verified M/d/yy assignment dates use
2000+YY and invalid dates remain undated entries. Calendar never silently
turns an invalid date into today or counts absence coincidences as missing work.
Only source assignment metadata supplies Missing, Absent, and No count.
Local what-if assignments and score edits do not enter this page.

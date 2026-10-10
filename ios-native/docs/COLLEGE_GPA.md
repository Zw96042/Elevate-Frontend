# Completed-grade conversion and college comparisons

Elevate's district percentage GPA and What-if calculator are unchanged. The
converter is a separate named 4.0/5.0 estimate, calculated course by course from
completed semester records. It opens on all completed high-school years. Credits
are not available, so records count equally. Missing grades, pass codes, invalid
numbers and conflicting duplicates are excluded. The calculation does not use
projected quarter/semester scores or What-if assignments. Current semesters are
eligible only after their district semester has ended; undated live-only rows
must not inherit completion from a prior transcript bucket.

The generic converter uses A=90+, B=80+, C=70+, D=60+, F<60, without rounding or
plus/minus grades. Its optional local weighted policy gives passing AP-level
courses +1 and Honors +0.5, including existing district course-name exceptions.
These are explicit conversion assumptions, not a verified college's rules.

## College-specific estimates

The original GPA catalog was checked against primary publications on **2026-10-04**; supplemental admissions guidance and statistics were checked on **2026-10-06**:

| Profile | Cohort and population | Estimate used | Published comparison |
| --- | --- | --- | --- |
| UCLA | Fall 2025 admitted | Grades 10–11, UC fully weighted | 25th/median/75th: 4.44 / 4.61 / 4.78 |
| UC Berkeley | Fall 2026 admitted | Grades 10–11, UC unweighted | Middle 50%: 3.90–4.00 |
| University of Georgia | Fall 2026 admitted, March decision snapshot | Recognized academic core + AP art/music, AP/IB weighted | Middle 50%: 4.13–4.40 |
| University of Florida | Class of 2030 admitted, July 2026 | Recognized core + AP/IB/AICE electives, weighted | Middle 50%: 4.50–4.70 |
| Florida State | Fall 2026 admitted | Recognized academic core, weighted for C or better | Middle 50%: 4.30–4.60 |
| Central Florida | Fall 2025 enrolled | Recognized academic core, weighted | Published weighted mean: 4.26 |
| Stanford | Fall 2025 enrolled reporting GPA | No college-specific estimate | Published GPA bands; 69.60% reported GPA |
| Princeton | Fall 2025 enrolled reporting GPA | No college-specific estimate | Published GPA bands; 99% reported GPA |
| Johns Hopkins | Fall 2025 enrolled reporting GPA | No college-specific estimate | Published GPA bands; 95.86% reported GPA |
| Vanderbilt | Fall 2025 enrolled reporting GPA | No college-specific estimate | Published GPA bands; 99.8% reported GPA |
| Boston University | Fall 2025 enrolled reporting GPA | No college-specific estimate | Published GPA bands; mean 3.86; 100% reported GPA |
| Case Western Reserve | Fall 2025 enrolled reporting GPA | No college-specific estimate | Published GPA bands; mean 3.78; 92% reported GPA |
| University of Arizona | Fall 2024 enrolled reporting GPA | No college-specific estimate | Historical published bands; mean 3.47; 97.5% reported GPA |
| Purdue | 2025 published class profile; exact population unspecified | No college-specific estimate | Middle 50%: 3.70–4.00, converted to unweighted for reporting |
| Illinois Urbana-Champaign | Rolling three-year admitted profile | No college-specific estimate | Middle 50%: 3.70–4.00; source weighting/year span unspecified |
| Wisconsin–Madison | Current admissions guidance | No college-specific estimate | Typical unweighted academic GPA of 3.8–4.0; not a cohort quartile |
| Arizona State | Current admissions guidance | No college-specific estimate | 3.00 unweighted in competency courses is one alternative aptitude route |
| MIT | 2025–26 publication | No college-specific estimate | CDS GPA statistics marked unavailable |
| Yale | 2025–26 publication | No college-specific estimate | CDS GPA fields blank; no invented zeros |
| Pittsburgh | 2025–26 Pittsburgh campus publication | No college-specific estimate | CDS GPA fields unfilled; no invented zeros |

The [UC policy](https://admission.universityofcalifornia.edu/admission-requirements/first-year-requirements/gpa-requirement.html)
uses grades 10–11 (including specified summer coursework), A=4/B=3/C=2/D=1/F=0,
without plus/minus grades. For students outside California, school-designated
Honors courses receive no bonus; AP/IB with C or better receive +1. UCLA's
published **fully weighted** profile is uncapped, unlike the capped UC eligibility
GPA. Elevate uses explicit AP/IB designations and bounded exact district AP
short-code aliases, not local advanced-course exceptions. Known PE, athletics,
health and nonacademic support courses are omitted and retained for explanation.
Arts and academic electives remain included: their district category cannot
establish UC A–G eligibility. Remaining course eligibility, credits and summer
grade-year placement are unverified and disclosed in calculation notes.
Berkeley's weighted profile does not specify its cap, so the app uses the
published unweighted range instead of inventing one.

My Colleges is temporarily removed from app navigation and onboarding. Its
implementation and account-local selections are retained for a possible return;
college search and detail have no reachable entry point. The following describes
the retained implementation, rather than an available feature.

My Colleges opens on the student's chosen schools, saved locally per account.
A searchable picker adds or removes schools; the full catalog remains available
in Search. Rows lead with the student's record rather than the published average.
Only the six implemented sourced methods (two UC variants plus UGA, UF, FSU
and UCF) show a college-specific estimate. A named generic unweighted 4.0
reference can be compared only with verified compatible unweighted figures.
Unknown or incompatible scales explain why no comparison is available. A missing
implemented method means Elevate has not verified a complete usable formula,
not that the college publishes no policy. Published class statistics and source
lists are secondary disclosures; provenance supporting a personal comparison
remains beside it. The separate GPA converter retains generic 4.0/5.0 summaries.

Common Data Set instructions to report GPA on a 4.0 scale do not establish an
admissions recalculation formula or certify unweighted reporting. The app never
substitutes a college undergraduate grading scale for high-school admissions.
The named generic calculation remains in the core for compatibility;
`hasPublishedCalculation` keeps it out of individual college pages.
`publishedGPAScale` independently describes the published statistics. Unknown
scales and incompatible weighted/unweighted scales receive no displayed cohort
comparison. Generic weighted estimates are never placed against college statistics;
unweighted references require independently verified compatible figures.

### Published academic-core weighting

UGA, UF, FSU and UCF use all completed high-school semesters available to Elevate,
with no aggregate bonus cap. Course titles approximate subjects and levels;
this is not a verified transcript audit. Credits, official letter-grade scales
and authoritative subject codes are unavailable. The numeric conversion above
is an explicit estimate assumption, including its treatment of 60–69 as D.

- [UGA first-year criteria](https://admissions.uga.edu/apply/first-year-applicants/first-year-criteria/): academic core plus AP Art and Music Theory; AP/IB +1, Honors and dual enrollment +0. Its [self-report instructions](https://admissions.uga.edu/apply/first-year-applicants/first-year-criteria/self-reported-grades/) specify grades 9–11 plus completed grade 12, exclude middle-school grades, and identify non-core exclusions such as computer science, journalism and business math. Art History and ASL are included. UGA uses the school's letter-grade scale, which the app cannot verify from a numeric score alone.
- [UF decision process](https://admissions.ufl.edu/apply/freshman/our-decision-process): core plus AP/IB/AICE electives; AP/IB/AICE and core dual enrollment +1, Honors/pre-AP/pre-IB/pre-AICE +0.5.
- [FSU 2026–27 bulletin](https://bulletin.fsu.edu/matriculation/ug-admissions#admission-from-secondary-school1): academic core only; AP/IB/AICE/dual enrollment +1 and Honors/pre-AP/pre-IB/pre-AICE +0.5 at C or better. Below-C grades remain with base points. The bulletin's secondary-school tab and published source contain the same Fall 2026 comparison range.

- [UCF GPA FAQ](https://www.ucf.edu/admissions/undergraduate/question/how-is-my-high-school-gpa-calculated-for-admission/): academic core only; AP/IB/AICE/dual enrollment +1 and Honors/pre-AP/pre-IB/pre-AICE +0.5. Unlike UF, the published rule does not add non-core AP electives. Its source does not specify low-grade bonus treatment; Elevate withholds the total for a bonus-eligible grade below C. The catalog preserves the separately published Fall 2025 weighted mean as context.

The classifier checks exclusions before broad subject words, recognizes explicit
AP/IB/AICE/dual-enrollment labels, and keeps Pre-AP/Pre-IB/Pre-AICE separate from AP/IB.
Trailing H is recognized as Honors. Exact aliases resolve through the district
credit catalog, then an independent college subject mapping; the district
science classification of Robotics or Engineering does not make either college
core, and computer science stays excluded except UF AP/IB/AICE electives.
Compact AP codes must match a bounded known alias; arbitrary AP-prefixed words
never earn a bonus. Local advanced-course exceptions never establish a bonus.
The district's exact AP Capstone aliases are an exception to prefix/suffix
recognition: English Independent Study I / Independent Study in English 1
(LA145) is AP Seminar, and II / 2 (LA146) is AP Research. Both retain their
Skyward names and receive local AP weight and college AP recognition; raw course
identities stay unchanged. Generic independent study and III / LA147 remain
separate. These aliases do not establish graduation English credit or override
college subject-eligibility rules. Sources: [WHS English electives](https://whs.eanesisd.net/coursecatalog/courses/la/electives)
and [WHS GPA weights](https://whs.eanesisd.net/coursecatalog/info/rank-and-gpa).
Art History has an explicit exception before broad `HISTORY` matching: UGA's
self-report instructions include it as social science, and UF's published
AP/IB/AICE elective rule includes those advanced versions. FSU/UCF Art History
and ordinary UF Art History instead withhold the whole estimate because their
admissions-core eligibility has not been verified. The title and grade remain
available with an explanatory calculation note. [P.K. Yonge's 2026–27 course
guide](https://pkyonge.ufl.edu/my-pk/8th-12th/2026-2027-high-school-program/course-guide-26-27-electives/)
classifies AP Art History as fine arts for high-school graduation; that is
primary evidence about the school's graduation classification, not an explicit
FSU/UCF admissions-GPA exclusion. Neither inclusion nor exclusion is inferred
from that classification. UC retains Art History with its general A–G caveat.
Known non-core records are retained in `omittedRecords`, with counts in
`calculationNotes`; unrecognized subjects withhold the whole estimate. This
prevents an unknown low-grade course from silently improving the result.

UGA, UF and UCF's linked sources do not explicitly resolve bonus treatment for low
grades. If an otherwise bonus-eligible record is below C, Elevate retains it but
withholds the total and explains the verification limitation. This is an app
limitation, not a claim that the college excludes those grades or imposes a C
cutoff. FSU's cutoff is published. `unavailableReason` prevents both weighted and
unweighted totals or standing from being displayed for an incomplete calculation.

## Your GPA and published class context

The student's own GPA is described independently of the published cohort.
An exact 4.0 on an unweighted estimate is this scale's ceiling. A value of
3.999 is not perfect and displays as 3.99. Comparisons use the full calculation
before display truncation. Weighted estimates retain their named method;
a weighted 4.0 does not establish an unweighted 4.0. Where no college-specific
formula is verified, the screen can show an explicitly named **Elevate 4.0
reference**. It is compared only with verified unweighted published figures;
it is never presented as the college's recalculation.

Published quartiles remain class summaries. GPA histograms describe the share
of the reporting cohort in a band. **Vanderbilt's 31.6% means that 31.6% of its
Fall 2025 enrolled students reporting GPA were in the published 4.0 band. It
is not a student's percentile**, and its complement is not a rank either.
Published context is held separately in `CollegeGPAStanding.cohortContext`;
there is no cumulative higher-band share. The legacy `higherBandPercent` field
always returns nil. Unreported lower bands stay unavailable;
source-rounded percentages are retained without invisible rescaling (Johns
Hopkins totals 100.01%). Coverage applies only to students reporting GPA, not the
entire applicant or enrolled population. College estimates are displayed to two decimals without rounding up; matching a source band
use the full calculation value. None of these comparisons is an
admission probability, cutoff, or official transcript. Current courses do not enter the completed-grade GPA. Preparation rows can separately show completed local credits, current credits assuming passing completion, and the amount to reach a published subject target. These are local credit estimates, not verified admissions eligibility. Language sequences, laboratory eligibility, unclassified courses, and Toronto senior-English equivalence withhold unsupported totals or gaps. Program and subset restrictions remain visible above the rows; longer source notes are disclosed below.

The expanded catalog includes 114 searchable colleges. Its original GPA profiles are joined to separately sourced admissions metadata in `Elevate/Resources/CollegeAdmissions.json`. The resource carries per-statistic cohort, population, source, optional score ranges/means, applicant/admit counts, enrollment, and preparation subjects. Approximate lower-bound counts never produce an exact admission rate; SAT section quartiles are never summed into a total range. Search matches names and
aliases such as JHU, CWRU, ASU, UIUC and Vandy, ignores case/diacritics and extra
whitespace, and sorts names locally. An empty query shows the full catalog; a
missing match is a real empty result. No search triggers a network request.

`publishedSummary` preserves admissions guidance separately from class statistics,
and `publicationNote` explains source limitations. Wisconsin's typical GPA is
not a middle-50% range; Arizona State's competency-course route is not an
all-subject comparison or an admission guarantee. Purdue's GPA conversion is
for reporting after its admission cycle, and the page says GPA is not an
admission factor. Illinois's source does not establish weighting or the exact
three-year span. Arizona's Fall 2024 figures are deliberately historical: a newer
publication exists, but the 2024–25 values are the verified usable dataset here.
Missing MIT, Yale and Pittsburgh statistics stay unavailable in this catalog;
no college-specific estimate or cohort comparison appears when usable compatible
figures are unavailable. None of these profiles receives fabricated
bands, means, population percentages or a college-specific recalculation policy.

## Primary publications

- [UCLA 2025 profile](https://admission.ucla.edu/apply/first-year/first-year-profile/2025)
- [UC Berkeley profile](https://admissions.berkeley.edu/apply-to-berkeley/student-profile/)
- [Stanford 2025–26 CDS](https://drive.google.com/file/d/1GIPKgVj1d86dkmLkHI_mZVCk_iY6kiCp/view), C11/C12; [official index](https://irds.stanford.edu/data-findings/cds)
- [Princeton 2025–26 CDS v2](https://ir.princeton.edu/sites/g/files/toruqf2041/files/documents/CDS_2526_Princeton_v2.pdf), C11/C12
- [Johns Hopkins 2025–26 CDS v2](https://oira.jhu.edu/wp-content/uploads/2025-2026-CDS-Johns-Hopkins-University-v2.pdf), C11/C12
- [Vanderbilt 2025–26 CDS](https://cdn.vanderbilt.edu/vu-wpfsx/wp-content/uploads/sites/70/2026/07/CDS_2025-2026.xlsx), section C, F232:F240 (all-enrolled bands), E243/E244 (mean/coverage)
- [Boston University updated 2025–26 CDS section C](https://www.bu.edu/asir/files/2026/07/CDS-2025-2026-C-updated.pdf), C11/C12
- [Case Western Reserve adjusted final 2025–26 CDS](https://case.edu/ir/sites/default/files/2026-02/CDS%202025-26%20Adjusted%20Final.pdf), C11/C12
- [University of Arizona 2024–25 CDS](https://uair.arizona.edu/sites/default/files/2025-03/CDS-2024-2025-FINAL.pdf), C11/C12; historical usable data
- [Purdue 2025 class profile](https://admissions.purdue.edu/become-student/class-profile/)
- [Illinois admitted class profile](https://www.admissions.illinois.edu/class-profile/)
- [Wisconsin–Madison first-year admissions guidance](https://admissions.wisc.edu/apply-as-a-freshman/)
- [Arizona State first-year requirements](https://admission.asu.edu/apply/first-year/admission)
- [MIT 2025–26 CDS](https://ir.mit.edu/projects/2025-26-common-data-set/), C11/C12 unavailable
- [Yale 2025–26 CDS](https://oir.yale.edu/sites/default/files/yale_cds_2025-26_md_20260410_0.pdf), C11/C12 blank
- [Pittsburgh 2025–26 CDS](https://www.ir.pitt.edu/sites/default/files/2026-02/CDS_2025-2026_PGH-UA_0.pdf), C11/C12 unfilled

Harvard's published mean exceeds 4.0 despite a capped top histogram label;
the catalog must not assert that it matches a generic unweighted estimate. Colleges without
usable current GPA distributions can appear in search with explicit unavailable
statistics; the app does not fabricate ranks for them.

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


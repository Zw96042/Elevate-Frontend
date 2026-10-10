# Local course and credit planning

Course planning is separate from official grade history, the GPA converter,
college comparisons and assignment What-if. `CoursePlan` owns source-bound credit
corrections, missing-course additions,
future semester records and a personal review checklist. Historical credits are
automatically estimated from the independent transcript projection.
It cannot write to Skyward's Career Plan, change enrollment, or certify graduation.
Plans must remain account scoped in the caller's persistence; the pure calculator
does not own storage, fetches or authentication.

## Requirement profile and sources

Checked **2026-10-04** against primary district/state sources:

- [Westlake graduation catalog](https://whs.eanesisd.net/coursecatalog/info/graduation-requirements):
  the district default is Foundation + Multidisciplinary Endorsement with
  Distinguished Level of Achievement, totaling 26 credits. Allocations are
  English 4, mathematics 4, science 4, social studies 4, same-language study 2,
  PE 1, health 0.5, fine arts 1 and electives 5.5. Named-course conditions include
  Algebra II and English I–IV; subject totals alone do not prove them.
- [Westlake course selection resources](https://sites.google.com/eanesisd.net/westlakecounseling/course-selection/course-selection-resources):
  the dated 2026–27 resources link that live catalog and describe the separate,
  annually signed Skyward Career Plan. The graduation page itself does not
  advertise a fixed edition or entering cohort, so Elevate does not claim it is
  universally applicable to every student.
- [TEA 2025 Graduation Toolkit](https://tea.texas.gov/about-tea/newsroom/brochures/tea-graduation-toolkit-2025.pdf),
  pages 4–7 and 9: Foundation alone has 22 credits; an endorsement pathway adds
  math, science and electives to reach 26. Distinguished achievement additionally
  requires Algebra II and an earned endorsement. It also documents EOC, speech,
  CPR/applicable AED, peace-officer instruction and financial-aid requirements.
  The toolkit has cohort-dependent provisions, including economics. Personal
  checklist items therefore include counselor confirmation of entering-cohort
  rules, substitutions and credit eligibility. Checking them records a user's
  review, not verification by the app.

Only the named Westlake default profile is implemented. Foundation-only,
alternative endorsements, Texas First, individual exceptions and later cohort
rule changes require a separate researched profile. A standard state 26-credit
endorsement minimum must not silently replace Westlake's district allocations.

## Automatic transcript credits

`PlanningTranscriptCourse` preserves every valid academic-history course row,
including non-linked and middle-school rows previously omitted from the official
high-school grade subset. It retains school year, grade level, title, terms,
posted SM1/SM2 and exam strings. It does not use live gradebook scores or the
parser's synthesized `finalGrade`. The endpoint still supplies no verified
awarded-credit field or state subject code: automatic results are catalog-based
**estimates**, with source rows available for correction and review.

`TranscriptCreditCalculator` matches bounded exact title/code aliases after
punctuation, Roman numeral, Honors and Pre-AP normalization. It preserves
standalone “pre” in Pre Calculus. Bounded abbreviated math/language and published
Health/PE course codes share the same catalog identities. Recognized athletics
allow roster qualifiers (gender, varsity/JV, grade and course level), including
Water Polo, Football, Swimming/Diving and Cheerleader. The remaining complete
title must match a known PE course; a title merely containing a sport does not
match. Unknown high-school titles remain “Needs review” rather than becoming
electives. Ordinary pre-9 schedule rows are excluded from credit review and
remain available as source records for explicit corrections. Each completed, numerically passing semester (70+) in
a normal one-credit annual course contributes 0.5. Missing grades, pass codes,
nonfinite values, conflicting equivalent grades, unverified school years and
unknown grade levels do not create credit. Current/future semesters remain
unearned. Current-year completion follows the district calendar; older-year
completion uses the existing documented calendar approximation.

Primary catalog details checked **2026-10-04**:

- [Art History](https://whs.eanesisd.net/coursecatalog/courses/fine-arts/arthistory):
  AP Art History and each Art Historical Methods course are one-credit fine arts.
- [Science](https://whs.eanesisd.net/coursecatalog/courses/science/science-courses):
  AP Physics I & 2 and AP Physics C each carry two annual credits, so a passing
  semester contributes one. The I & 2 rule is documented from 2020–21; earlier
  records require review. AP Biology/Chemistry are separate from introductory
  Biology/Chemistry. IPC taken in grade 8 before 2021–22 counts as an elective;
  ordinary middle-school science does not become high-school science credit.
- [Mathematics](https://whs.eanesisd.net/coursecatalog/courses/math):
  Multivariable Calculus carries one credit in its fall-only course; Linear
  Algebra carries 0.5 in spring. Statistics, AP Statistics and Stats 2 remain
  separate courses.
- [Health/PE](https://whs.eanesisd.net/coursecatalog/courses/health-and-physical-education/health):
  Health Education and Outdoor Education each carry 0.5 for their semester.
  A single passing Health SM1 therefore contributes 0.5, not 0.25. PE estimates
  are capped at four; substitutions are not automatically double allocated.
- [Information Technology](https://whs.eanesisd.net/coursecatalog/courses/cate/it)
  and [STEM](https://whs.eanesisd.net/coursecatalog/courses/cate/stem) support
  one-credit Computer Science II/III and Robotics II electives; Robotics III
  is science. [AP Cybersecurity TC281](https://whs.eanesisd.net/coursecatalog/courses/~board/fa/post/ap-cybersecurity)
  is a one-credit course verified in the rendered district All Courses dialog
  (the category page and crawler omit that new-course detail).
- [Middle-school accelerated academics](https://www.eanesisd.net/academics/advanced/accelerated-academics/6th-8th-grade):
  recognized Algebra I/Geometry/Algebra II, Level-I world languages and Health
  can earn high-school credit. Spanish/French/Latin 7 alone earns none; the
  grade-8 completion is Level I and cannot add a second Level-I credit. Health
  has an independent final-exam condition; a passing posted semester remains
  an estimate because awarded-credit/attendance confirmation is unavailable.
  Eligibility is Algebra I in grades 6–8, Geometry in 7–8, Algebra II in 8,
  Level I language completion in 8 and Health 1 in 8. Ordinary accelerated
  middle-school Math 6/8, English, science, arts and PE are not high-school
  credit estimates. A middle-school PE waiver alone does not prove an awarded
  high-school credit; an individually verified exception can use a correction.
- [Westlake athletics](https://whs.eanesisd.net/coursecatalog/courses/health-and-physical-education/athletics)
  documents one-credit sports courses with gender, grade and varsity variants.
  [Westlake's Water Polo teacher schedule](https://sites.google.com/eanesisd.net/dcarruthers/home)
  identifies Boys & Girls Water Polo as an athletic period; it shares the
  athletics estimate and keeps the same eligibility/award limitations.
- [2026–27 Student Handbook](https://resources.finalsite.net/images/v1784580759/eanesisdnet/jjyxeuo7wx0dtjpm6i4s/2026-27StudentHandbook.pdf),
  printed pages 36 and 57: attendance and credit-award conditions are independent
  of grades. A fall 65–69 with a passing same-year spring and annual average 70+
  is marked for review: summer/correspondence/credit-by-exam provenance is absent.
  A failing spring semester is never automatically averaged up.

Disjoint fall/spring rows combine only the corresponding credit allocations.
Duplicate equivalent rows with the same score count once; conflicting scores
are unresolved. Ordinary repeated equivalent courses cannot earn the same
semester twice; explicitly repeatable arts/PE catalog entries retain later years.
AP/Honors aliases do not add duplicate English/introductory credit. Advanced
courses with distinct catalog identities retain their separate credits.

A correction binds to a deterministic signature containing source year, grade,
title, terms and original posted grades. It replaces that exact allocation,
including zero to exclude it; it never adds an extra record. Reordering source
rows preserves correction identity, while changed grades/source membership
orphan the old correction for review. This is deliberately independent of random
unified-course ID suffixes. Corrections may provide an unknown course's subject
and credit value after the student reviews its source.

## Current enrollment credits

The report keeps `earnedTotal`, `currentTotal` and `plannedTotal` separate.
Requirement `current` amounts and current totals contribute to expected combined
coverage and remaining deficits; `earnedRemaining` always uses earned credit only.
`CurrentCourseCredit` is a read-only enrollment projection with stable catalog/year
identity, underlying gradebook source identities, known semesters, status and detail.
It does not add grades to the official or projected GPA.

Current credit requires real gradebook request parameters and independent enrollment
provenance. The production live-grid merge sets optional `isCurrentEnrollment`,
`currentEnrollmentSemester`, `currentEnrollmentGradeYear` and
`currentEnrollmentObservedAt` fields only on actual gradebook memberships, using the
page's current grade level, scored bucket semesters and actual successful fetch time.
A later live snapshot clears previous membership flags. Historical source year/grades,
course duration and GPA inputs remain unchanged; old caches decode absent metadata.
Blank future grade cells do not prove enrollment duration. Unknown enrollment grade,
semester or catalog classifications remain reviewable with zero credit.

When independent current school-year evidence is unavailable, a current live membership
can count only its observed active, unfinished semester. Its displayed academic year is
nil (Current enrollment); historical merge buckets cannot date it. The observation must
be within the same academic year and semester as calculation time, so a prior-semester
or prior-year cache does not remain current indefinitely. The calendar only bounds an
actual observation; it never manufactures an enrollment or historical source year.
No upcoming semester is inferred in this path. Independently verified current-year
provenance from `CourseHistoryReport` and known enrolled terms additionally support
future semesters within that course year. Historical rows, planning-only carriers,
latest transcript buckets and What-if data do not establish enrollment on their own.

Known unfinished fall/spring enrollment contributes catalog credit **expected if
passed**, including an upcoming spring semester only when independently verified current-year enrollment explicitly includes it.
Live quarter/semester grades, including a failing live score, do not award credit or
change earned totals. Semester completion follows the existing district calendar.
Completed semesters and already credited catalog-equivalent semesters cannot also count
as prospective current credit. Normal annual courses remain capped at their catalog
credit, AP Physics 1&2 at two annually, Multivariable Calculus at one for its semester,
and Linear Algebra at 0.5. Robotics II is an elective. Split terms, repeated live source
identities and equivalent title/rigor aliases contribute only once; earned PE and
prospective PE together retain the four-credit cap.

## Manual reconciliation and persistence

Manual additions are retained for genuinely missing courses. With transcript
records present, older aggregate/manual entries remain visible for reconciliation
and do not silently add to newly detected credits: a saved “English credits = 3”
and three detected English credits still total three. An explicitly confirmed
missing-course addition may count only when its catalog-equivalent title does
not already appear in source records. When no source records exist, legacy manual
entries remain usable. Manual grades never become official GPA grades.

Future courses remain separate, with planned credit totals assuming successful
completion and eligibility. Optional `academicYear` and `semester` fields disambiguate
future entries from a current catalog-equivalent course. A same-year matching semester
or an unscoped matching entry is held in `manualPlannedReviewCourses`, excluded from
credits and projected GPA, and retained for review rather than discarded. A known
different future year or distinct known semester remains usable. When enrollment has
no year, an explicitly future academic year can still count; the calendar is used only
to establish that the planned year is future, never to assign enrollment provenance.
An unknown enrolled semester cannot establish that a manual semester is distinct.
Unscoped repeats cannot be presumed to mean next year. Manual earned additions matching
current enrollment also require reconciliation to prevent earned/current duplication.
Source courses retain their original subject and credit amount. Requirement
allocation fills each category's actual required amount, then assigns its
surplus to electives. Earned credits fill capacity first, current expected
credits next, and future planned credits last; each phase keeps its own totals
and elective surplus. Thus 5 earned math credits cover 4 math and 1 elective,
while a 1-credit Health Science course covers 0.5 health and 0.5 elective.
This never creates a second credit or changes GPA inputs. Category totals
cannot certify same-language study, named-course requirements, an endorsement,
EOC, attendance, speech, CPR/AED or cohort-specific graduation conditions.

Plans decode prior payloads without overrides, supplementary flags or future scope fields. Validation
bounds record/override counts, finite credits, score magnitude, names, identities
and encoded size. Invalid or corrupt account storage is preserved and blocked
from overwriting until explicit reset. Account-scope guards prevent stale UI
writes; no plan writes to Skyward or changes enrollment.

The planning projection is carried through the existing account-scoped course
cache on one deterministic normal record, or an empty `isPlanningOnly` transport
carrier when no official high-school records exist. AppStore extracts the payload
and strips carriers before publishing courses. Notification, journal, migration,
background and direct grade/history/timeline consumers exclude carriers. Optional
fields preserve older cache decoding and older caches fall back only to immutable
posted transcript semester grades. GPA inclusion and live course selection remain
unchanged.

## GPA projection

Baseline uses `GPAConversionCalculator`'s completed posted semester records in
known grades 9–12, retaining its missing-grade, pass-code, completion and
conflicting-duplicate exclusions. This is a calculated baseline, not a fetched
official transcript GPA. Source courses are immutable. Manual earned-credit
entries never contribute grades, which prevents them from duplicating imported
semester grades; they may consequently include credit without a GPA baseline.

Projected values add only planned semester records with eligible finite,
nonnegative expected scores, using `AcademicScoreValue`'s magnitude bound. Every
included record counts once regardless of the supplied credits, matching the
existing equal-semester conversion assumption where verified source credits are
unavailable. **Enter each semester separately**; a 1-credit allocation with one
expected score does not secretly become two semester GPA records. Missing,
invalid and explicitly excluded planned grades leave planned credits intact but
are skipped from GPA with a visible reason/count. With no completed source grades,
baseline is unavailable and any projected GPA reflects future entries alone.

Named policies preserve Elevate's district percentage average and weighted
percentage calculation (+10 AP level / +5 Honors, 110 cap per weighted record)
and reuse `GPAConversionPolicy` for the generic 4.0/5.0 thresholds and bonuses.
Official records retain existing course-name level detection; planned records use
the user's explicit level selection. They do not apply a college's eligibility,
credit-weighting or repeat rules. Neither future grades nor manual credit entries
enter official GPA, college standing, course averages or widgets.

## Verification boundary

`TranscriptCreditTests` verifies automatic subject/credit rules, middle-school
eligibility, duplicates/conflicts/repeats, invalid grades, completion, correction
provenance, legacy reconciliation, parser/cache compatibility and storage bounds.
`CoursePlannerTests` exercises credit deficits, partial allocations, category
coverage independent of total/endorsement, duplicate identities, malformed
credits/scores, GPA-only exclusions, completed-grade provenance, baseline
immutability, manual/official duplication prevention, named-policy projections,
equal-semester weighting and persistence round-trip. Core tests do not establish
device UI behavior or counselor approval of an individual graduation plan. Current
regressions also cover expected AP English deficits without earned/GPA changes,
source-year ambiguity, real gradebook identity, catalog semester/annual caps,
completed/previously earned equivalents, split terms and stable deduplication, unknown
classification, manual overlap review and scoped future-plan persistence.

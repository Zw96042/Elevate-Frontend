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


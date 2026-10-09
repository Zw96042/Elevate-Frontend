import Foundation
import Testing
@testable import ElevateCore

@Suite("Automatic transcript credit estimates")
struct TranscriptCreditTests {
    @Test("Art history is fine arts; catalog special credits retain their full semester allocation")
    func catalogAllocations() {
        let report = calculate([
            row("AP Art History"), row("AP Physics 1&2"), row("AP Physics C"),
            row("Health", terms: "1-2", spring: nil),
            row("Multivariable Calculus", terms: "1-2", spring: nil),
            row("Linear Algebra", terms: "3-4", fall: nil),
        ])
        #expect(report.credits(for: .fineArts) == 1)
        #expect(report.credits(for: .science) == 4)
        #expect(report.credits(for: .health) == 0.5)
        #expect(report.credits(for: .math) == 1.5)
        #expect(report.unresolved.isEmpty)
    }

    @Test("Catalog aliases preserve advanced second science courses and Pre Calculus")
    func distinctCourses() {
        let report = calculate([
            row("Biology I"), row("AP Biology"), row("Chemistry I"), row("AP Chemistry"),
            row("Pre Calculus"), row("Calculus"), row("Statistics"), row("AP Statistics"),
            row("Statistics 2 Beyond Statistics"), row("Robotics II"), row("Robotics III"),
            row("Computer Science III"), row("AP Cybersecurity"), row("AP English 2"),
        ])
        #expect(report.credits(for: .science) == 5)
        #expect(report.credits(for: .math) == 5)
        #expect(report.credits(for: .elective) == 3)
        #expect(report.credits(for: .english) == 1)
        #expect(report.unresolved.isEmpty)
        #expect(TranscriptCreditCalculator.normalize("Pre Calculus") != TranscriptCreditCalculator.normalize("Calculus"))
    }

    @Test("Middle-school credit includes eligible courses only, with language 7/8 and legacy IPC rules")
    func middleSchool() {
        let report = calculate([
            row("Algebra I", grade: 8), row("Geometry", grade: 8), row("Health", grade: 8, terms: "1-2", spring: nil),
            row("Spanish 7", grade: 7), row("Spanish 8", grade: 8), row("Spanish I", grade: 8),
            row("Biology", grade: 8), row("World History", grade: 8),
            row("IPC", year: "2020-2021", grade: 8), row("IPC", year: "2024-2025", grade: 8),
        ])
        #expect(report.credits(for: .math) == 2)
        #expect(report.credits(for: .health) == 0.5)
        #expect(report.credits(for: .worldLanguage) == 1)
        #expect(report.credits(for: .science) == 0)
        #expect(report.credits(for: .socialStudies) == 0)
        #expect(report.credits(for: .elective) == 1)
        #expect(report.records.filter { $0.name == "IPC" && $0.academicYear == "2024-2025" }.allSatisfy { $0.status == .excluded })
    }

    @Test("Disjoint semester rows, duplicate source rows and repeated equivalent courses count once")
    func repeatedRows() {
        let fall = row("English I", terms: "1-2", spring: nil)
        let spring = row("English I Honors", terms: "3-4", fall: nil)
        let report = calculate([fall, fall, spring, row("English I", year: "2024-2025")])
        #expect(report.total == 1)
        #expect(report.records.count == 4)
        let retry = calculate([
            row("English II", year: "2023-2024", fall: "55", spring: "80"),
            row("English II Honors", year: "2024-2025", fall: "80", spring: "80"),
        ])
        #expect(retry.total == 1)
    }

    @Test("Accelerated middle-school estimates retain the documented grade eligibility")
    func middleSchoolGradeEligibility() {
        let report = calculate([
            row("Geometry", grade: 6), row("Algebra II", grade: 7), row("Spanish I", grade: 7),
            row("Health", grade: 7, terms: "1-2", spring: nil),
        ])
        #expect(report.total == 0)
        #expect(report.records.allSatisfy { $0.status == .excluded })
        #expect(calculate([row("Algebra I", grade: 6)]).total == 1)
    }

    @Test("Ordinary middle-school schedules do not become credit-review tasks")
    func ordinaryMiddleSchoolSchedule() {
        let names = ["English 8", "Language Arts 7", "Math 8 Accelerated", "Math 7/8 Compacted", "Science 8",
                     "Texas History", "US History", "Band", "Art 1", "PE", "Football", "Uncatalogued Exploratory"]
        let report = calculate(names.map { row($0, grade: 8) })
        #expect(report.total == 0)
        #expect(report.unresolved.isEmpty)
        #expect(report.records.allSatisfy { $0.status == .excluded })
        #expect(calculate([row("Math 8 Accelerated", year: "unknown", grade: 8)]).unresolved.isEmpty)
        // Unknown high-school course identities still need a real allocation.
        #expect(calculate([row("Uncatalogued Seminar", grade: 10)]).unresolved.count == 2)
    }

    @Test("Middle-school high-school aliases retain eligibility and source-bound corrections")
    func acceleratedAliasesAndCorrections() throws {
        let report = calculate([
            row("PreAP ALG I", grade: 6), row("ALG1H", grade: 8), row("GEO H", grade: 7), row("GEOMP", grade: 8), row("ALG II Honors", grade: 8),
            row("SPN1", grade: 8), row("SPN1H", grade: 8), row("Spanish Level I", grade: 8),
            row("HLTH ED", grade: 8, terms: "1-2", spring: nil),
        ])
        #expect(report.credits(for: .math) == 3)
        #expect(report.credits(for: .worldLanguage) == 1)
        #expect(report.credits(for: .health) == 0.5)
        #expect(report.unresolved.isEmpty)
        let rows = [row("PE", grade: 8, terms: "1-2", spring: nil)]
        let excluded = try #require(calculate(rows).records.first)
        let correction = TranscriptCreditOverride(id: excluded.id, credits: 0.5, subject: .physicalEducation)
        let corrected = TranscriptCreditCalculator.calculate(courses: [], planningTranscriptCourses: rows,
            overrides: [correction], asOf: date)
        #expect(corrected.total == 0.5)
        #expect(corrected.records.first?.id == excluded.id)
        #expect(corrected.records.first?.status == .corrected)
        #expect(corrected.orphanedOverrideIDs.isEmpty)
    }

    @Test("Actual athletics recognize roster variants without classifying sport-related academic titles")
    func athleticsAliases() {
        for name in ["Water Polo", "Waterpolo 1", "Boys & Girls Water Polo", "Water Polo JV", "Football 9th Grade",
                     "Football 9th Grade - AT832A/B", "Girls Volleyball 1", "Tennis Junior Varsity", "Swimming/Diving", "Cheerleader", "9th Grade Girls Athletics",
                     "Basketball Boys 9th Grade AT833A/B*", "Volleyball Girls 9th Grade - AT830A/B*", "Girls Track & Field Varsity",
                     "Swimming and Diving Junior Varsity", "AT031C", "PE880D"] {
            let report = calculate([row(name)])
            #expect(report.credits(for: .physicalEducation) == 1)
            #expect(report.unresolved.isEmpty)
        }
        for name in ["Football History", "Water Polo Management", "Sports Science"] {
            #expect(calculate([row(name)]).total == 0)
            #expect(calculate([row(name)]).unresolved.count == 2)
        }
        let duplicates = calculate([row("Water Polo"), row("Boys Waterpolo 1"), row("Water Polo", year: "2024-2025")])
        #expect(duplicates.credits(for: .physicalEducation) == 2)
        #expect(calculate([row("Water Polo", grade: 8)]).unresolved.isEmpty)
        #expect(calculate([row("Water Polo", grade: 8)]).total == 0)
        #expect(calculate([row("PE"), row("Physical Education"), row("P.E.")]).total == 1)
    }

    @Test("Catalog display suffixes and sports medicine distinguish subject and equivalent credit")
    func catalogNamesAndSportsMedicine() {
        let report = calculate([
            row("AP LANGUAGE AND COMPOSITION (AP ENGLISH III) - LA118 (APENGLAN)"),
            row("ALGEBRA II HONORS - MA240 (ALG2)"), row("AP COMPUTER SCIENCE PRINCIPLES - TC736 (PRINIT)"),
            row("ATHLETIC TRAINING - SPORTS MEDICINE (SPORTMD1, SPORTMD2, SPORTMD3)"),
            row("AT100A/B"), row("SPORTMD1"),
        ])
        #expect(report.credits(for: .english) == 1)
        #expect(report.credits(for: .math) == 1)
        #expect(report.credits(for: .elective) == 2)
        #expect(report.credits(for: .physicalEducation) == 0)
        #expect(report.unresolved.isEmpty)
        #expect(calculate([row("Football History - LA999")]).unresolved.count == 2)
        #expect(calculate([row("Sports Management - TC999")]).credits(for: .physicalEducation) == 0)
    }

    @Test("Current athletics aliases share enrollment allocation and completed-credit limits")
    func currentAthleticsAliases() {
        let report = current([live("Water Polo"), live("Boys Waterpolo 1")])
        #expect(report.count == 1)
        #expect(report.first?.credits == 1)
        #expect(report.first?.subject == .physicalEducation)
        let earned = TranscriptCreditCalculator.calculate(courses: [],
            planningTranscriptCourses: [row("Water Polo", year: "2026-2027", terms: "1-2", spring: nil)],
            overrides: [], asOf: ISO8601DateFormatter().date(from: "2027-01-10T12:00:00Z")!)
        let afterFall = TranscriptCreditCalculator.currentCourses(courses: [live("Boys Water Polo")], earned: earned,
            asOf: ISO8601DateFormatter().date(from: "2027-01-10T12:00:00Z")!)
        #expect(earned.total == 0.5)
        #expect(afterFall.first?.credits == 0.5)
        var middle = live("English 8")
        middle.gradeYear = 8
        #expect(current([middle]).first?.status == .excluded)
        #expect(current([middle]).first?.credits == 0)
    }

    @Test("Conflicting equivalent grades remain reviewable without awarding that semester")
    func conflictingRows() {
        let report = calculate([row("English I", fall: "80"), row("English I Honors", fall: "90")])
        #expect(report.total == 0.5)
        #expect(report.unresolved.count == 1)
        let conflict = calculate([row("English I", fall: "80", spring: nil), row("English I", fall: "P", spring: nil)])
        #expect(conflict.total == 0)
    }

    @Test("Fall averaging needs provenance review; spring failure is never averaged up")
    func averagingBoundary() {
        let fallReview = calculate([row("English I", fall: "65", spring: "85")])
        #expect(fallReview.total == 0.5)
        #expect(fallReview.unresolved.first?.semester == .sm1)
        let springFail = calculate([row("English I", fall: "95", spring: "65")])
        #expect(springFail.total == 0.5)
        #expect(springFail.records.first { $0.semester == .sm2 }?.status == .notEarned)
        let unrecoverable = calculate([row("English I", fall: "64", spring: "95")])
        #expect(unrecoverable.unresolved.isEmpty)
    }

    @Test("Pass codes, missing and invalid scores never fabricate credits")
    func invalidScores() {
        for score in ["P", "CR", "NaN", "Infinity", "1e99", "-1", ""] {
            let report = calculate([row("English I", terms: "1-2", fall: score, spring: nil)])
            #expect(report.total == 0)
            #expect(report.unresolved.count == 1)
        }
        #expect(calculate([row("English I", terms: "1-2", fall: "70", spring: nil)]).total == 0.5)
        #expect(calculate([row("Unknown course", terms: "1-2", spring: nil)]).unresolved.count == 1)
        #expect(calculate([row("AP Cybersecurity", terms: "1-2", spring: nil)]).total == 0.5)
        #expect(calculate([row("Office Aide")]).total == 0)
    }

    @Test("Current and future semesters and unverified years do not become earned credit")
    func completionBoundary() {
        #expect(calculate([row("English I", year: "2026-2027")]).total == 0)
        #expect(calculate([row("English I", year: "2027-2028")]).total == 0)
        #expect(calculate([row("English I", year: "unknown")]).unresolved.count == 2)
        #expect(calculate([row("English I", grade: nil)]).total == 0)
        let olderPhysics = calculate([row("AP Physics 1&2", year: "2019-2020")])
        #expect(olderPhysics.unresolved.count == 2)
    }

    @Test("Corrections replace estimates, stay source-bound and survive source ordering")
    func correctionProvenance() throws {
        let rows = [row("English I"), row("Unknown course", terms: "1-2", spring: nil)]
        let initial = calculate(rows)
        let englishFall = try #require(initial.records.first { $0.name == "English I" && $0.semester == .sm1 })
        let unknown = try #require(initial.records.first { $0.name == "Unknown course" })
        let changes = [TranscriptCreditOverride(id: englishFall.id, credits: 0, subject: .english),
                       TranscriptCreditOverride(id: unknown.id, credits: 1, subject: .elective)]
        let corrected = TranscriptCreditCalculator.calculate(courses: [], planningTranscriptCourses: rows.reversed(), overrides: changes, asOf: date)
        #expect(corrected.total == 1.5)
        #expect(corrected.records.filter { $0.status == .corrected }.count == 2)
        #expect(corrected.orphanedOverrideIDs.isEmpty)
        var changed = rows
        changed[0].sm1 = "99"
        let refreshed = TranscriptCreditCalculator.calculate(courses: [], planningTranscriptCourses: changed, overrides: changes, asOf: date)
        #expect(refreshed.orphanedOverrideIDs == [englishFall.id])
        let conflicting = TranscriptCreditCalculator.calculate(courses: [], planningTranscriptCourses: rows,
            overrides: [changes[0], changes[0]], asOf: date)
        #expect(conflicting.records.first { $0.id == englishFall.id }?.status == .needsReview)
    }

    @Test("Legacy aggregate credits require reconciliation and missing additions cannot duplicate detected courses")
    func manualReconciliation() {
        let rows = [row("English I"), row("English II"), row("AP English Language and Composition")]
        let legacy = CoursePlanCourse(name: "English credits", credits: 3, subject: .english)
        var missing = CoursePlanCourse(name: "Transferred elective", credits: 1, subject: .elective)
        missing.isSupplemental = true
        var duplicate = CoursePlanCourse(name: "English I Honors", credits: 1, subject: .english)
        duplicate.isSupplemental = true
        let report = CoursePlanner.calculate(plan: CoursePlan(earnedCourses: [legacy, missing, duplicate]), officialCourses: [],
            planningTranscriptCourses: rows, asOf: date)
        #expect(report.earnedTotal == 4)
        #expect(report.requirements.first { $0.subject == .english }?.earned == 3)
        #expect(report.manualEarnedCourses.map(\.name) == ["Transferred elective"])
        #expect(report.manualReviewCourses.count == 2)
        #expect(report.gpa.allSatisfy { $0.officialBaseline == nil })
    }

    @Test("Parser preserves non-linked and middle-school rows without expanding official grades")
    func parserAndTransport() throws {
        let grids: [String: Any] = ["gradeGrid_1_2_3": ["tb": ["r": [
            header("2024 - 2025 Grade 8"), gridRow("Algebra I", linked: false),
            header("2025 - 2026 Grade 9"), gridRow("English I", linked: true), gridRow("AP Art History", linked: false), gridRow("PE", linked: true),
        ]]]]
        let history = try SkywardHistoryAPI.condenseAcademicHistory(grids)
        #expect(history["2024-2025"]?.courses.isEmpty == true)
        #expect(history["2025-2026"]?.courses.count == 1)
        let transported = UnifiedCourseTransformer.transform(history: history)
        #expect(transported.count == 1)
        #expect(transported[0].courseName == "English I")
        #expect(transported[0].historicalGrades.sm1 == "80")
        #expect(transported[0].planningTranscriptCourses?.count == 4)
        #expect(TranscriptCreditCalculator.calculate(courses: transported, asOf: date).total == 4)
        #expect(GPACalculator.termGPAs(courses: transported)["SM1"]?.unweighted == 80)
        let onlyMiddle = UnifiedCourseTransformer.transform(history: ["2024-2025": history["2024-2025"]!])
        #expect(onlyMiddle.count == 1)
        #expect(onlyMiddle[0].isPlanningOnly == true)
        #expect(onlyMiddle[0].currentScores.isEmpty)
        #expect(onlyMiddle[0].historicalGrades.sm1 == nil)
        #expect(onlyMiddle[0].historicalGrades.sm2 == nil)
        #expect(!onlyMiddle[0].hasGradebookParams)
        #expect(onlyMiddle[0].availableTerms.isEmpty)
        #expect(GPACalculator.termGPAs(courses: onlyMiddle).isEmpty)
        #expect(CourseHistoryReport(courses: onlyMiddle).knownAcademicYears.isEmpty)
        #expect(GPATimeline.allYears(courses: onlyMiddle, manualClassesByYear: [:]).isEmpty)
    }

    @Test("Older caches and plans decode while absent credit provenance remains absent")
    func backwardsCompatibility() throws {
        let plan = CoursePlan(earnedCourses: [CoursePlanCourse(name: "English credits", credits: 3, subject: .english)])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        object.removeValue(forKey: "creditOverrides")
        let restored = try JSONDecoder().decode(CoursePlan.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.creditOverrides.isEmpty)
        #expect(restored.earnedCourses[0].isSupplemental == nil)
        let history = try JSONDecoder().decode(AcademicYear.self, from: Data(#"{"grade":9,"courses":{}}"#.utf8))
        #expect(history.planningTranscriptCourses == nil)
        let official = UnifiedCourseTransformer.transform(history: ["2025-2026": AcademicYear(grade: 9, courses: [
            "English I": HistoryCourse(courseName: "English I", terms: "1-2", sm1: "85", isTranscriptRecord: true),
        ])])
        let decoded = try JSONDecoder().decode([UnifiedCourseData].self, from: JSONEncoder().encode(official))
        #expect(decoded[0].planningTranscriptCourses == nil)
        #expect(decoded[0].isPlanningOnly == nil)
        #expect(TranscriptCreditCalculator.calculate(courses: decoded, asOf: date).total == 0.5)
        var liveOnly = decoded[0]
        liveOnly.isTranscriptRecord = false
        liveOnly.postedHistoricalGrades = nil
        #expect(TranscriptCreditCalculator.calculate(courses: [liveOnly], asOf: date).total == 0)
        var annualSummaryOnly = decoded[0]
        annualSummaryOnly.historicalGrades = HistoricalGrades(rc1: "95", finalGrade: "95")
        annualSummaryOnly.postedHistoricalGrades = annualSummaryOnly.historicalGrades
        let unresolved = TranscriptCreditCalculator.calculate(courses: [annualSummaryOnly], asOf: date)
        #expect(unresolved.total == 0)
        #expect(unresolved.unresolved.count == 1)
    }

    @Test("Planning-only middle-school years cannot date or reclassify live enrollment")
    func planningYearsDoNotChangeLiveMerge() throws {
        let middle = row("Algebra I", year: "2024-2025", grade: 8)
        let combined = SkywardHistoryAPI.combine(history: [
            "2024-2025": AcademicYear(grade: 8, courses: [:], planningTranscriptCourses: [middle]),
        ], gradebook: [GradebookCourse(course: 1, courseName: "English I", instructor: "Synthetic", period: 1,
            scores: [(bucket: "SEM 1", score: 95)])], fallbackGrade: 9)
        let current = try #require(combined["current"])
        #expect(current.grade == 9)
        #expect(current.academicYearIsVerified == false)
        #expect(current.courses.count == 1)
        #expect(current.courses.values.first?.isTranscriptRecord == false)
        let transformed = UnifiedCourseTransformer.transform(history: combined)
        #expect(transformed.count == 1)
        #expect(transformed[0].gradeYear == 9)
        #expect(transformed[0].historicalGrades.sm1 == "95")
        #expect(transformed[0].planningTranscriptCourses == [middle])
        #expect(TranscriptCreditCalculator.calculate(courses: transformed, asOf: date).total == 1)
    }

    @Test("Stored plan validation bounds malformed corrections and duplicate identifiers")
    func storageBounds() {
        #expect(CoursePlan().isValidForStorage)
        #expect(CoursePlan(creditOverrides: [.init(id: "source", credits: 0, subject: .english)]).isValidForStorage)
        for credits in [Double.nan, .infinity, -1, 4.1] {
            #expect(!CoursePlan(creditOverrides: [.init(id: "source", credits: credits, subject: .english)]).isValidForStorage)
        }
        let override = TranscriptCreditOverride(id: "source", credits: 1, subject: .english)
        #expect(!CoursePlan(creditOverrides: [override, override]).isValidForStorage)
        #expect(!CoursePlan(creditOverrides: [.init(id: String(repeating: "x", count: 16_385), credits: 1, subject: .english)]).isValidForStorage)
        #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(CoursePlan.self, from: Data("{}".utf8)) }
    }

    @Test("Current enrollment preserves annual and single-semester catalog caps")
    func currentCatalogAllocations() {
        let report = current([
            live("AP Physics 1&2"), live("Multivariable Calculus", semester: .fall),
            live("Linear Algebra", semester: .spring), live("Robotics II"),
        ])
        #expect(report.first { $0.name == "AP Physics 1&2" }?.credits == 2)
        #expect(report.first { $0.name == "Multivariable Calculus" }?.credits == 1)
        #expect(report.first { $0.name == "Linear Algebra" }?.credits == 0.5)
        #expect(report.first { $0.name == "Robotics II" }?.subject == .elective)
        #expect(report.allSatisfy { $0.status == .expected })
        #expect(current([live("Multivariable Calculus")]).first?.credits == 1)
    }

    @Test("Duplicate live identities and split semesters produce one stable enrollment allocation")
    func currentEnrollmentDeduplication() throws {
        let fall = live("English III", semester: .fall)
        var spring = live("AP English Language and Composition", semester: .spring)
        spring.gbId = "spring"
        let report = current([fall, fall, spring])
        #expect(report.count == 1)
        #expect(report.first?.credits == 1)
        #expect(report.first?.sourceCourseIDs.count == 2)
        #expect(report.first?.semesters == [.sm1, .sm2])
        #expect(current([spring, fall]).map(\.id) == report.map(\.id))
        var changedGrade = fall
        changedGrade.currentScores = [BucketScore(bucket: "TERM 3", score: 100)]
        #expect(current([changedGrade, spring]).map(\.id) == report.map(\.id))
    }

    @Test("Completed semesters and already earned equivalents never count as current prospective credit")
    func currentEarnedBoundary() {
        let january = ISO8601DateFormatter().date(from: "2027-01-10T12:00:00Z")!
        let rows = [row("English III", year: "2026-2027", grade: 11, spring: nil)]
        let earned = TranscriptCreditCalculator.calculate(courses: [], planningTranscriptCourses: rows, asOf: january)
        #expect(earned.total == 0.5)
        let enrolled = TranscriptCreditCalculator.currentCourses(courses: [live("AP English Language and Composition")], earned: earned, asOf: january)
        #expect(enrolled.first?.credits == 0.5)
        #expect(enrolled.first?.semesters == [.sm2])
        let completed = TranscriptCreditCalculator.currentCourses(courses: [live("English III", semester: .fall)], earned: earned, asOf: january)
        #expect(completed.first?.credits == 0)
        let previous = calculate([row("English III")])
        #expect(current([live("AP English Language and Composition")], earned: previous).first?.credits == 0)
        let pe = calculate((2022...2025).map { row("PE", year: "\($0)-\($0 + 1)") })
        #expect(pe.total == 4)
        #expect(current([live("PE")], earned: pe).first?.credits == 0)
    }

    @Test("Past years, carriers and incomplete gradebook identity are never current enrollment")
    func currentProvenanceBoundary() {
        var past = live("English III")
        past.academicYear = "2025-2026"
        #expect(current([past]).isEmpty)
        var noParams = live("English III")
        noParams.gbId = ""
        #expect(current([noParams]).isEmpty)
        var carrier = live("English III")
        carrier.isPlanningOnly = true
        #expect(current([carrier]).isEmpty)
        var guessed = live("English III")
        guessed.academicYearIsVerified = false
        guessed.currentAcademicYearIsVerified = nil
        #expect(current([guessed]).first?.status == .needsReview)
        #expect(current([guessed]).first?.credits == 0)
        var ambiguous = live("English IV")
        ambiguous.academicYear = nil
        let mixed = current([live("English III"), ambiguous])
        #expect(mixed.first { $0.name == "English III" }?.credits == 1)
        #expect(mixed.first { $0.name == "English IV" }?.status == .needsReview)
        #expect(mixed.first { $0.name == "English IV" }?.credits == 0)
    }


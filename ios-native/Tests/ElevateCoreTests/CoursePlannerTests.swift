import Foundation
import Testing
@testable import ElevateCore

@Suite("Local course and credit planning")
struct CoursePlannerTests {
    @Test("Posted historical passing semesters establish catalog estimates separately from GPA")
    func inferredHistoricalCredits() {
        let report = calculate(CoursePlan(), official: [officialCourse(score: "95")])
        #expect(report.earnedTotal == 0.5)
        #expect(report.remainingTotal == 25.5)
        #expect(projection(report, .districtPercentage).officialBaseline == 95)
        #expect(report.transcriptCredits.usedLegacyFallback)
        #expect(report.transcriptCredits.records.first?.status == .estimated)
        #expect(report.requirements.first { $0.subject == .english }?.earned == 0.5)
    }

    @Test("Earned and planned credits stay separate and deficits retain partial credits")
    func creditDeficits() throws {
        let plan = CoursePlan(earnedCourses: [entry("English I", credits: 1, subject: .english)],
                              plannedCourses: [entry("English II semester", credits: 0.5, subject: .english)])
        let report = calculate(plan)
        let english = try #require(report.requirements.first { $0.subject == .english })
        #expect(english.earned == 1)
        #expect(english.planned == 0.5)
        #expect(english.earnedRemaining == 3)
        #expect(english.remaining == 2.5)
        #expect(report.earnedTotal == 1)
        #expect(report.plannedTotal == 0.5)
        #expect(report.remainingTotal == 24.5)
    }

    @Test("Surplus subjects fill electives at each actual requirement amount")
    func earnedOverflowAllocation() {
        let records = CoursePlanPath.westlakeDistinguished.requirements.filter { $0.subject != .elective }.flatMap { requirement in
            [entry("Required \(requirement.subject.title)", credits: requirement.credits, subject: requirement.subject),
             entry("Additional \(requirement.subject.title)", credits: 0.5, subject: requirement.subject)]
        }
        let report = calculate(CoursePlan(earnedCourses: records))
        for requirement in report.requirements where requirement.subject != .elective {
            #expect(requirement.earned == requirement.required)
        }
        #expect(report.requirements.first { $0.subject == .elective }?.earned == 4)
        #expect(report.earnedTotal == 24.5)
        #expect(report.requirements.reduce(0) { $0 + $1.earned } == report.earnedTotal)
        #expect(report.manualEarnedCourses == records)
    }

    @Test("Earned current and future allocations share subject capacity without duplicating credits")
    func sequentialOverflowAllocation() throws {
        let plan = CoursePlan(earnedCourses: [entry("Math from previous courses", credits: 3.5, subject: .math)],
            plannedCourses: [entry("Future statistics", credits: 1, subject: .math)])
        let report = calculate(plan, official: [currentCourse("Precalculus")])
        let math = try #require(report.requirements.first { $0.subject == .math })
        let electives = try #require(report.requirements.first { $0.subject == .elective })
        #expect(math.earned == 3.5)
        #expect(math.current == 0.5)
        #expect(math.planned == 0)
        #expect(electives.earned == 0)
        #expect(electives.current == 0.5)
        #expect(electives.planned == 1)
        #expect(report.earnedTotal == 3.5)
        #expect(report.currentTotal == 1)
        #expect(report.plannedTotal == 1)
        #expect(report.requirements.reduce(0) { $0 + $1.combined } == report.combinedTotal)
        #expect(report.currentCourses.first?.subject == .math)
        #expect(report.manualPlannedReviewCourses.isEmpty)
    }

    @Test("Transcript overflow keeps original subjects and does not enter GPA")
    func transcriptOverflowAllocation() {
        let rows = ["Algebra I", "Geometry", "Algebra II", "Precalculus", "AP Calculus AB"].map {
            PlanningTranscriptCourse(academicYear: "2025-2026", gradeYear: 10, name: $0, terms: "1-4", sm1: "90", sm2: "90")
        } + [PlanningTranscriptCourse(academicYear: "2025-2026", gradeYear: 10,
                name: "Principles of Health Science", terms: "1-4", sm1: "90", sm2: "90")]
        let report = CoursePlanner.calculate(plan: CoursePlan(), officialCourses: [], planningTranscriptCourses: rows, asOf: date)
        #expect(report.earnedTotal == 6)
        #expect(report.requirements.first { $0.subject == .math }?.earned == 4)
        #expect(report.requirements.first { $0.subject == .health }?.earned == 0.5)
        #expect(report.requirements.first { $0.subject == .elective }?.earned == 1.5)
        #expect(report.transcriptCredits.credits(for: .math) == 5)
        #expect(report.transcriptCredits.credits(for: .health) == 1)
        #expect(report.gpa.allSatisfy { $0.officialBaseline == nil && $0.projected == nil })
    }

    @Test("A 26-credit total alone cannot cover deficient subjects or an endorsement")
    func totalsAreInsufficient() {
        let electives = (0..<7).map { entry("Elective \($0)", credits: $0 == 6 ? 2 : 4, subject: .elective) }
        let report = calculate(CoursePlan(earnedCourses: electives))
        #expect(report.earnedTotal == 26)
        #expect(report.remainingTotal == 0)
        #expect(!report.creditTargetsCovered)
        #expect(report.uncheckedRequirements.contains(.multidisciplinaryEndorsement))
        #expect(report.requirements.first { $0.subject == .english }?.remaining == 4)
    }

    @Test("Covering credit targets retains independently unverified requirements")
    func checklistIndependent() {
        let courses = CoursePlanPath.westlakeDistinguished.requirements.flatMap { requirement in
            let full = Int(requirement.credits)
            var records = (0..<full).map { entry("\(requirement.subject.title) \($0)", credits: 1, subject: requirement.subject) }
            let partial = requirement.credits - Double(full)
            if partial > 0 { records.append(entry("Partial", credits: partial, subject: requirement.subject)) }
            return records
        }
        let report = calculate(CoursePlan(earnedCourses: courses, checkedRequirements: [.speech]))
        #expect(report.creditTargetsCovered)
        #expect(report.earnedTotal == 26)
        #expect(report.uncheckedRequirements.count == CoursePlanChecklistItem.allCases.count - 1)
        #expect(report.uncheckedRequirements.contains(.algebraII))
        #expect(report.uncheckedRequirements.contains(.sameWorldLanguage))
    }

    @Test("Manual earned grades cannot duplicate official GPA; planned grades cannot change baseline")
    func immutableOfficialBaseline() {
        let source = officialCourse(score: "80")
        let plan = CoursePlan(earnedCourses: [entry("Already imported", score: 100)],
                              plannedCourses: [entry("Future English", score: 100)])
        let report = calculate(plan, official: [source])
        let district = projection(report, .districtPercentage)
        #expect(district.officialBaseline == 80)
        #expect(district.projected == 90)
        #expect(district.officialCount == 1)
        #expect(district.plannedCount == 1)
        #expect(source.historicalGrades.sm1 == "80")
        #expect(GPAConversionCalculator.calculate(courses: [source], policy: .unweighted4Point,
                                                 completedOnly: true, asOf: date).value == 3)
    }

    @Test("GPA exclusions do not remove allocated credits or imply a passed course")
    func independentGPAAndCredits() {
        var excluded = entry("Athletics", subject: .physicalEducation, score: 90)
        excluded.excludedFromGPA = true
        let plan = CoursePlan(plannedCourses: [excluded, entry("Unknown grade"), entry("Future course", score: 50)])
        let report = calculate(plan)
        #expect(report.plannedTotal == 1.5)
        #expect(projection(report, .generic4Point).projected == 0)
        #expect(projection(report, .generic4Point).plannedCount == 1)
        #expect(projection(report, .generic4Point).skippedPlannedCount == 2)
        #expect(report.issues.contains { $0.reason == .excludedFromGPA })
        #expect(report.issues.contains { $0.reason == .missingScore })
    }

    @Test("Invalid credits and duplicate identities cannot inflate progress or GPA")
    func malformedCredits() {
        let invalid = [Double.nan, .infinity, -1, 0, 4.1].map { entry("Invalid", credits: $0, score: 90) }
        let duplicate = entry("Duplicate", score: 100)
        let report = calculate(CoursePlan(earnedCourses: [duplicate], plannedCourses: invalid + [duplicate]))
        #expect(report.earnedTotal == 0)
        #expect(report.plannedTotal == 0)
        #expect(projection(report, .districtPercentage).projected == nil)
        #expect(report.issues.filter { $0.reason == .invalidCredits }.count == 5)
        #expect(report.issues.filter { $0.reason == .duplicateID }.count == 2)
    }

    @Test("Invalid expected scores are skipped while valid allocated credits survive")
    func malformedScores() {
        let scores = [Double.nan, .infinity, -1, 1e10]
        let report = calculate(CoursePlan(plannedCourses: scores.map { entry("Bad grade", score: $0) }))
        #expect(report.plannedTotal == 2)
        #expect(report.issues.filter { $0.reason == .invalidScore }.count == 4)
        #expect(report.gpa.allSatisfy { $0.projected == nil && $0.plannedCount == 0 })
    }

    @Test("Projection uses existing generic cutoffs and selected levels, not course-name guesses")
    func projectedPolicies() {
        let report = calculate(CoursePlan(plannedCourses: [
            entry("Named AP but explicit regular", score: 89.99),
            entry("Advanced choice", level: .ap, score: 90),
            entry("Honors choice", level: .honors, score: 90),
        ]))
        #expect(projection(report, .generic4Point).projected == 11.0 / 3)
        #expect(projection(report, .generic5Point).projected == 12.5 / 3)
        #expect(projection(report, .districtWeightedPercentage).projected == (89.99 + 100 + 95) / 3)
        #expect(projection(report, .districtPercentage).officialBaseline == nil)
    }

    @Test("Planner GPA follows completed source records and excludes in-progress quarters")
    func noLiveSemesterProjection() {
        var live = officialCourse(score: "99")
        live.isTranscriptRecord = false
        live.postedHistoricalGrades = nil
        live.academicYear = "2026-2027"
        live.courseId = 1
        live.corNumId = "1"
        live.section = "1"
        live.gbId = "1"
        live.stuId = "synthetic"
        let report = calculate(CoursePlan(), official: [live])
        #expect(projection(report, .districtPercentage).officialBaseline == nil)
        #expect(report.officialSkippedCount > 0)
    }

    @Test("Credits do not invisibly change the equal-semester projection denominator")
    func semesterWeighting() {
        let report = calculate(CoursePlan(plannedCourses: [
            entry("One semester", credits: 0.5, score: 80), entry("Other credit allocation", credits: 1, score: 100),
        ]))
        #expect(report.plannedTotal == 1.5)
        #expect(projection(report, .districtPercentage).projected == 90)
        #expect(projection(report, .districtPercentage).plannedCount == 2)
    }

    @Test("Account-local planner payload preserves personal entries and checklist across encoding")
    func persistenceRoundTrip() throws {
        let plan = CoursePlan(earnedCourses: [entry("Earned")], plannedCourses: [entry("Future", level: .honors, score: 91)],
                              checkedRequirements: [.speech, .cprAndAED])
        #expect(try JSONDecoder().decode(CoursePlan.self, from: JSONEncoder().encode(plan)) == plan)
    }

    @Test("Verified current AP English reduces expected deficit without awarding credit or GPA")
    func currentEnrollmentProgress() throws {
        let live = currentCourse("AP English Language and Composition")
        let report = calculate(CoursePlan(), official: [live])
        let english = try #require(report.requirements.first { $0.subject == .english })
        #expect(english.earned == 0)
        #expect(english.current == 1)
        #expect(english.planned == 0)
        #expect(english.remaining == 3)
        #expect(english.earnedRemaining == 4)
        #expect(report.currentTotal == 1)
        #expect(report.earnedTotal == 0)
        #expect(report.combinedTotal == 1)
        #expect(report.earnedRemainingTotal == 26)
        #expect(report.currentCourses.first?.status == .expected)
        #expect(report.gpa.allSatisfy { $0.officialBaseline == nil && $0.projected == nil })
        #expect(live.currentScores.first?.score == 55)
    }

    @Test("Every current course stays visible and recognized subjects reduce the correct balances")
    func currentScheduleCoverage() {
        let recognized = ["AP English Language and Composition", "Precalculus", "AP Physics 1&2", "AP United States History",
                          "Spanish III", "Girls Swimming and Diving Varsity", "AP Computer Science Principles", "Sports Medicine"]
        let courses = (recognized + ["Uncatalogued Seminar"]).map { currentCourse($0) }
        let report = calculate(CoursePlan(), official: courses)
        #expect(report.currentCourses.count == courses.count)
        #expect(report.currentCourses.filter { $0.status == .expected }.count == recognized.count)
        #expect(report.currentTotal == 9)
        #expect(report.earnedTotal == 0)
        #expect(report.remainingTotal == 17)
        #expect(report.requirements.first { $0.subject == .english }?.remaining == 3)
        #expect(report.requirements.first { $0.subject == .science }?.remaining == 2)
        #expect(report.requirements.first { $0.subject == .physicalEducation }?.remaining == 0)
        #expect(report.requirements.first { $0.subject == .elective }?.current == 2)
        #expect(report.requirements.reduce(0) { $0 + $1.combined } == report.combinedTotal)
        let unknown = report.currentCourses.first { $0.name == "Uncatalogued Seminar" }
        #expect(unknown?.status == .needsReview)
        #expect(unknown?.credits == 0)
        #expect(unknown?.subject == nil)
    }

    @Test("A planned current-equivalent course is held unless its future scope is distinct")
    func plannedEnrollmentReconciliation() {
        let live = currentCourse("AP English Language and Composition", semester: .fall)
        let duplicate = entry("English III Honors", credits: 0.5, score: 100)
        var nextYear = duplicate
        nextYear.id = UUID()
        nextYear.academicYear = "2027-2028"
        var spring = duplicate
        spring.id = UUID()
        spring.academicYear = "2026-2027"
        spring.semester = .sm2
        let report = calculate(CoursePlan(plannedCourses: [duplicate, nextYear, spring]), official: [live])
        #expect(report.currentTotal == 0.5)
        #expect(report.plannedTotal == 1)
        #expect(report.manualPlannedReviewCourses.map(\.id) == [duplicate.id])
        #expect(report.issues.contains { $0.reason == .currentEnrollmentOverlap })
        #expect(projection(report, .districtPercentage).plannedCount == 2)
    }

    @Test("Manual earned additions matching current enrollment need reconciliation")
    func earnedEnrollmentReconciliation() {
        var duplicate = entry("English III Honors", credits: 1)
        duplicate.isSupplemental = true
        let report = calculate(CoursePlan(earnedCourses: [duplicate]), official: [currentCourse("AP English Language and Composition")])
        #expect(report.earnedTotal == 0)
        #expect(report.currentTotal == 1)
        #expect(report.manualReviewCourses.map(\.id) == [duplicate.id])
    }

    @Test("Unverified year and unknown course allocations remain reviewable")
    func currentReviewDoesNotFabricateCredits() {
        var unknownYear = currentCourse("English I")
        unknownYear.currentAcademicYearIsVerified = nil
        let unknown = calculate(CoursePlan(), official: [unknownYear])
        #expect(unknown.currentTotal == 0)
        #expect(unknown.currentCourses.first?.status == .needsReview)
        let unknownCourse = calculate(CoursePlan(), official: [currentCourse("Uncatalogued Seminar")])
        #expect(unknownCourse.currentTotal == 0)
        #expect(unknownCourse.currentCourses.first?.subject == nil)
        #expect(unknownCourse.currentCourses.first?.status == .needsReview)
    }

    @Test("Explicitly future-year plans remain usable when current enrollment year is unavailable")
    func futurePlanWithUndatedEnrollment() {
        var enrollment = currentCourse("English III")
        enrollment.academicYear = nil
        enrollment.academicYearIsVerified = nil
        enrollment.currentAcademicYearIsVerified = nil
        var future = entry("English III", credits: 1)
        future.academicYear = "2027-2028"
        let unscoped = entry("English III", credits: 1)
        let report = calculate(CoursePlan(plannedCourses: [future, unscoped]), official: [enrollment])
        #expect(report.currentTotal == 0)
        #expect(report.plannedTotal == 1)
        #expect(report.manualPlannedReviewCourses.map(\.id) == [unscoped.id])
    }

    @Test("Future scope fields round-trip and malformed scopes cannot count")
    func futureScopePersistence() throws {
        var next = entry("English III", score: 99)
        next.academicYear = "2027-2028"
        next.semester = .sm1
        let plan = CoursePlan(plannedCourses: [next])
        #expect(try JSONDecoder().decode(CoursePlan.self, from: JSONEncoder().encode(plan)) == plan)
        #expect(plan.isValidForStorage)
        next.semester = .q1
        let invalid = CoursePlan(plannedCourses: [next])
        #expect(!invalid.isValidForStorage)
        #expect(calculate(invalid).plannedTotal == 0)
        next.semester = .sm1
        next.academicYear = "current"
        #expect(!CoursePlan(plannedCourses: [next]).isValidForStorage)
    }

    private func currentCourse(_ name: String, semester: Semester = .both) -> UnifiedCourseData {
        UnifiedCourseData(courseId: 10, corNumId: "synthetic-course", stuId: "synthetic-student", section: "1", gbId: "10",
            courseName: name, semester: semester, termLength: semester == .fall ? "1-2" : semester == .spring ? "3-4" : "1-4",
            gradeYear: 11, currentScores: [BucketScore(bucket: "TERM 3", score: 55)], historicalGrades: HistoricalGrades(rc1: "55"),
            academicYear: "2026-2027", academicYearIsVerified: true, currentAcademicYearIsVerified: true, isTranscriptRecord: false)
    }

    private var date: Date { ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")! }
    private func calculate(_ plan: CoursePlan, official: [UnifiedCourseData] = []) -> CoursePlanReport {
        CoursePlanner.calculate(plan: plan, officialCourses: official, asOf: date)
    }
    private func projection(_ report: CoursePlanReport, _ policy: CoursePlanGPAPolicy) -> CoursePlanGPAProjection {
        report.gpa.first { $0.policy == policy }!
    }
    private func entry(_ name: String, credits: Double = 0.5, subject: CoursePlanSubject = .english,
                       level: CoursePlanLevel = .regular, score: Double? = nil) -> CoursePlanCourse {
        CoursePlanCourse(name: name, credits: credits, subject: subject, level: level, score: score)
    }
    private func officialCourse(score: String) -> UnifiedCourseData {
        let grades = HistoricalGrades(sm1: score)
        return UnifiedCourseData(courseId: nil, corNumId: "", stuId: "", section: "", gbId: "", courseName: "English I",
                                 semester: .fall, termLength: "1", gradeYear: 9, currentScores: [], historicalGrades: grades,
                                 academicYear: "2025-2026", historyRowKey: "synthetic", academicYearIsVerified: true,
                                 isTranscriptRecord: true, postedHistoricalGrades: grades)
    }
}

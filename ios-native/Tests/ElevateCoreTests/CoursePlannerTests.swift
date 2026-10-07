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


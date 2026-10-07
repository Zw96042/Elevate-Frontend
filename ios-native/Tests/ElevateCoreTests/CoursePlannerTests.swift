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


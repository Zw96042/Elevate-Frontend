import Foundation
import Testing
@testable import ElevateCore

@Suite("Grade math")
struct GradeMathTests {
    @Test("A real zero remains a grade instead of becoming missing")
    func zeroCourseTotal() {
        let assignment = CalcAssignment(
            id: "zero",
            className: "Algebra",
            name: "Test",
            term: "Q1",
            category: "Tests",
            grade: 0,
            outOf: 100,
            dueDate: "8/20/26",
            artificial: false,
            meta: []
        )

        let result = GradeCalculator.summary(
            assignments: [assignment],
            categoryWeights: ["Tests": 100]
        )

        #expect(result.courseTotal == 0)
    }

    @Test("Final-exam points are converted to a percentage")
    func finalExamPercentage() {
        #expect(GradeCalculator.percentage(earned: 45, outOf: 50) == 90)
        #expect(GradeCalculator.percentage(earned: 45, outOf: 0) == nil)
        #expect(GradeCalculator.percentage(earned: .infinity, outOf: 50) == nil)
    }

    @Test("Semester math applies the district 40/40/20 weights")
    func semesterWeighting() {
        #expect(SemesterMath.semesterAverage(rcA: "90", rcB: "80", exam: "100") == 88)
    }

    @Test("Quarter what-if work changes the semester headline")
    func semesterWhatIfUsesRecalculatedQuarter() {
        let base = CalcAssignment(
            id: "base", className: "Algebra", name: "Unit test", term: "Q1",
            category: "Tests", grade: 90, outOf: 100, dueDate: "8/20/26",
            artificial: false, meta: []
        )
        let hypothetical = CalcAssignment(
            id: "what-if", className: "Algebra", name: "Next test", term: "Q1",
            category: "Tests", grade: 100, outOf: 100, dueDate: "8/27/26",
            artificial: true, meta: []
        )
        let weights = ["Tests": 100.0]
        let originalQ1 = GradeCalculator.summary(assignments: [base], categoryWeights: weights).courseTotal
        let predictedQ1 = GradeCalculator.summary(
            assignments: [base, hypothetical],
            categoryWeights: weights
        ).courseTotal

        #expect(originalQ1 == 90)
        #expect(predictedQ1 == 95)
        #expect(GradeCalculator.semesterTotal(
            firstQuarter: originalQ1,
            secondQuarter: 80,
            finalExamGrade: 100
        ) == 88)
        #expect(GradeCalculator.semesterTotal(
            firstQuarter: predictedQ1,
            secondQuarter: 80,
            finalExamGrade: 100
        ) == 90)
    }

    @Test("Semester what-if assignments select an actual quarter")
    func semesterWhatIfQuarterRouting() {
        #expect(TermLabel.sm1.whatIfQuarterTerms == [.q1, .q2])
        #expect(TermLabel.sm2.whatIfQuarterTerms == [.q3, .q4])
        #expect(TermLabel.sm1.legacyWhatIfQuarter == .q2)
        #expect(TermLabel.q3.whatIfQuarterTerms == [.q3])
    }

    @Test("Foreground rollover preserves an explicitly selected historical term")
    func foregroundTermSelectionPolicy() {
        #expect(TermSelectionPolicy.selectionOnActivation(
            selected: .q1,
            current: .q3,
            lastAutomatic: .q2
        ) == .q1)
        #expect(TermSelectionPolicy.selectionOnActivation(
            selected: .q2,
            current: .q3,
            lastAutomatic: .q2
        ) == .q3)
    }

    @Test("Trailing H is honors without overriding AP or matching word endings")
    func trailingHHonorsDetection() {
        #expect(CourseLevelDetector.level(for: "ENGLISH 1 H") == .honors)
        #expect(CourseLevelDetector.level(for: "AP BIOLOGY H") == .ap)
        #expect(CourseLevelDetector.level(for: "English Honors") == .honors)
        #expect(CourseLevelDetector.level(for: "World History") == .regular)
        #expect(CourseLevelDetector.level(for: "Health") == .regular)
    }

    @Test("Manual GPA accepts a legitimate zero")
    func manualZeroGPA() {
        let result = GPACalculator.termGPAs(manualClasses: [
            ManualClass(className: "AP Biology", sm1: 0, sm2: nil),
            ManualClass(className: "English 1", sm1: 100, sm2: nil),
        ])

        #expect(result["SM1"]?.unweighted == 50)
        #expect(result["SM1"]?.weighted == 55)
    }

    @Test("All-time GPA combines manual years with Skyward years")
    func combinedManualAndSkywardGPA() {
        let course = UnifiedCourseData(
            courseId: 1, corNumId: "100", stuId: "student", section: "1",
            gbId: "gradebook", courseName: "English 2", instructor: nil,
            period: 1, time: nil, semester: .both, termLength: "1 - 4",
            gradeYear: 10, currentScores: [],
            historicalGrades: HistoricalGrades(
                pr1: nil, pr2: nil, pr3: nil, pr4: nil,
                pr5: nil, pr6: nil, pr7: nil, pr8: nil,
                rc1: nil, rc2: nil, rc3: nil, rc4: nil,
                ex1: nil, ex2: nil, sm1: "100", sm2: nil, finalGrade: nil
            )
        )

        let result = GPACalculator.termGPAs(
            courses: [course],
            manualClasses: [ManualClass(className: "Algebra 1", sm1: 0, sm2: nil)]
        )

        #expect(result["SM1"]?.unweighted == 50)
        #expect(result["SM1"]?.weighted == 50)
    }

    @Test("Skyward GPA keeps a posted zero")
    func skywardZeroGPA() {
        let course = UnifiedCourseData(
            courseId: 1,
            corNumId: "100",
            stuId: "student",
            section: "1",
            gbId: "gradebook",
            courseName: "Algebra",
            instructor: nil,
            period: 1,
            time: nil,
            semester: .both,
            termLength: "1 - 4",
            gradeYear: 9,
            currentScores: [],
            historicalGrades: HistoricalGrades(
                pr1: nil, pr2: nil, pr3: nil, pr4: nil,
                pr5: nil, pr6: nil, pr7: nil, pr8: nil,
                rc1: "0", rc2: nil, rc3: nil, rc4: nil,
                ex1: nil, ex2: nil, sm1: nil, sm2: nil, finalGrade: nil
            )
        )

        #expect(GPACalculator.termGPAs(courses: [course])["RC1"]?.weighted == 0)
    }

    @Test("Skyward weighted GPA caps at 110 without removing extra credit")
    func skywardWeightedCapKeepsExtraCredit() {
        let course = makeCourse(name: "AP Biology", sm1: "105")
        let result = GPACalculator.termGPAs(courses: [course])["SM1"]

        #expect(result?.unweighted == 105)
        #expect(result?.weighted == 110)
    }

    @Test("Manual weighted GPA caps at 110 without removing extra credit")
    func manualWeightedCapKeepsExtraCredit() {
        let result = GPACalculator.termGPAs(manualClasses: [
            ManualClass(className: "AP Biology", sm1: 105, sm2: nil),
            ManualClass(className: "Studio Art", sm1: 105, sm2: nil),
        ])["SM1"]

        #expect(result?.unweighted == 105)
        #expect(result?.weighted == 107.5)
    }

    @Test("Duplicate course names keep distinct navigation identities")
    func duplicateCourseIdentity() {
        let history = HistoricalGrades(
            pr1: nil, pr2: nil, pr3: nil, pr4: nil,
            pr5: nil, pr6: nil, pr7: nil, pr8: nil,
            rc1: "95", rc2: nil, rc3: nil, rc4: nil,
            ex1: nil, ex2: nil, sm1: nil, sm2: nil, finalGrade: nil
        )
        let first = UnifiedCourseData(
            courseId: 1, corNumId: "100", stuId: "student", section: "01",
            gbId: "gradebook-1", courseName: "Engineering", instructor: nil,
            period: 1, time: nil, semester: .both, termLength: "1 - 4",
            gradeYear: 11, currentScores: [], historicalGrades: history
        )
        let second = UnifiedCourseData(
            courseId: 2, corNumId: "100", stuId: "student", section: "02",
            gbId: "gradebook-2", courseName: "Engineering", instructor: nil,
            period: 2, time: nil, semester: .both, termLength: "1 - 4",
            gradeYear: 11, currentScores: [], historicalGrades: history
        )

        #expect(first.id != second.id)
    }

    @Test("May 31 remains in quarter four")
    func mayThirtyFirst() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 5
        components.day = 31
        #expect(AcademicCalendar.currentTerm(for: components.date!) == .q4)
    }

    private func makeCourse(name: String, sm1: String) -> UnifiedCourseData {
        UnifiedCourseData(
            courseId: 1, corNumId: "100", stuId: "student", section: "1",
            gbId: "gradebook", courseName: name, instructor: nil, period: 1,
            time: nil, semester: .both, termLength: "1 - 4", gradeYear: 11,
            currentScores: [],
            historicalGrades: HistoricalGrades(
                pr1: nil, pr2: nil, pr3: nil, pr4: nil,
                pr5: nil, pr6: nil, pr7: nil, pr8: nil,
                rc1: nil, rc2: nil, rc3: nil, rc4: nil,
                ex1: nil, ex2: nil, sm1: sm1, sm2: nil, finalGrade: nil
            )
        )
    }
}

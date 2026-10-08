import Testing
@testable import ElevateCore

struct GPATimelineTests {
    @Test("All years retain each year's terms and values in chronological order")
    func chronologicalYears() {
        let freshman = course(year: 9, pr1: "80", rc1: "82", sm1: "84", sm2: "86")
        let sophomore = course(year: 10, pr1: "94", rc1: "96", sm1: "98", sm2: "100")
        let timeline = GPATimeline.allYears(courses: [sophomore, freshman], manualClassesByYear: [:])
        #expect(timeline.map(\.id) == [
            "Freshman.PR1", "Freshman.RC1", "Freshman.SM1", "Freshman.SM2",
            "Sophomore.PR1", "Sophomore.RC1", "Sophomore.SM1", "Sophomore.SM2",
        ])
        #expect(timeline.map { $0.data.unweighted } == [80, 82, 84, 86, 94, 96, 98, 100])
        #expect(Set(timeline.map(\.id)).count == timeline.count)
    }

    @Test("Manual semesters fill only school years without real courses")
    func manualFallback() {
        let timeline = GPATimeline.allYears(
            courses: [course(year: 10, pr1: "95", rc1: nil, sm1: nil, sm2: nil)],
            manualClassesByYear: [
                9: [ManualClass(className: "AP Biology", sm1: 90, sm2: 92)],
                10: [ManualClass(className: "AP Biology", sm1: 10, sm2: 20)],
            ]
        )
        #expect(timeline.map(\.id) == ["Freshman.SM1", "Freshman.SM2", "Sophomore.PR1"])
        #expect(timeline.map { $0.data.weighted } == [100, 102, 95])
    }

    @Test("Missing terms stay missing, zeros are retained, current years remain distinct")
    func missingAndCurrent() {
        let timeline = GPATimeline.allYears(courses: [
            course(year: nil, pr1: "95", rc1: nil, sm1: nil, sm2: nil),
            course(year: 9, pr1: "0", rc1: "nan", sm1: nil, sm2: nil),
        ], manualClassesByYear: [:])
        #expect(timeline.map(\.id) == ["Freshman.PR1", "Current.PR1"])
        #expect(timeline.first?.data.unweighted == 0)
        #expect(GPATimeline.allYears(courses: [], manualClassesByYear: [:]).isEmpty)
    }

    private func course(year: Int?, pr1: String?, rc1: String?, sm1: String?, sm2: String?) -> UnifiedCourseData {
        UnifiedCourseData(
            courseId: 1, corNumId: "1", stuId: "fixture", section: "1",
            gbId: "1", courseName: "English", instructor: nil, period: 1,
            time: nil, semester: .both, termLength: "1 - 4", gradeYear: year,
            currentScores: [], historicalGrades: HistoricalGrades(
                pr1: pr1, pr2: nil, pr3: nil, pr4: nil, pr5: nil, pr6: nil, pr7: nil, pr8: nil,
                rc1: rc1, rc2: nil, rc3: nil, rc4: nil, ex1: nil, ex2: nil,
                sm1: sm1, sm2: sm2, finalGrade: nil
            )
        )
    }
}

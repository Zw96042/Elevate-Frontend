import Foundation
import Testing
@testable import ElevateCore

struct GPAConversionTests {
    @Test("The same percentage average can produce different course-based GPAs")
    func courseByCourse() {
        let first = report([course(id: 1, sm1: "90"), course(id: 2, sm1: "90")])
        let second = report([course(id: 1, sm1: "100"), course(id: 2, sm1: "80")])
        #expect(first.value == 4)
        #expect(second.value == 3.5)
    }

    @Test("Explicit thresholds preserve decimals and legitimate extra credit")
    func cutoffs() {
        let policy = GPAConversionPolicy.unweighted4Point
        #expect([0, 59.99, 60, 69.99, 70, 79.99, 80, 89.99, 90, 105].map {
            policy.points(for: $0, level: .regular)
        } == [0, 0, 1, 1, 2, 2, 3, 3, 4, 4])
        #expect(policy.points(for: -.infinity, level: .regular) == nil)
        #expect(policy.points(for: .nan, level: .regular) == nil)
        #expect(policy.points(for: -1, level: .regular) == nil)
        #expect(policy.points(for: 1e10, level: .regular) == nil)
    }

    @Test("Weighted estimates use local levels, passing bonuses, and zero for failure")
    func weights() {
        let value = report([
            course(id: 1, name: "AP Biology", sm1: "90"),
            course(id: 2, name: "English Honors", sm1: "90"),
            course(id: 3, name: "English", sm1: "90"),
        ], policy: .weighted5Point)
        #expect(value.includedRecords.map(\.points) == [5, 4.5, 4])
        #expect(value.value == 4.5)
        let localException = report([course(name: "Multivariable Calculus", sm1: "90")], policy: .weighted5Point)
        #expect(localException.value == 5)
        #expect(GPAConversionPolicy.weighted5Point.points(for: 59, level: .ap) == 0)
        #expect(GPAConversionPolicy.weighted5Point.points(for: 60, level: .ap) == 2)
    }

    @Test("Only known high-school years are eligible, and year filtering is explicit")
    func eligibleYears() {
        let courses = [
            course(id: 1, year: 8, sm1: "99"), course(id: 2, year: 9, sm1: "70"),
            course(id: 3, year: 10, sm1: "80"), course(id: 4, year: 11, sm1: "90"),
            course(id: 5, year: 12, sm1: "100"), course(id: 6, year: nil, sm1: "95"),
        ]
        let all = report(courses)
        #expect(all.includedRecords.map(\.gradeYear) == [9, 10, 11, 12])
        #expect(all.value == 3.25)
        #expect(all.skippedRecords.contains { $0.reason == .unknownYear })
        #expect(all.skippedRecords.contains { $0.reason == .outsideHighSchool })
        let filtered = GPAConversionCalculator.calculate(courses: courses, gradeYears: [10, 11], policy: .unweighted4Point)
        #expect(filtered.includedRecords.map(\.gradeYear) == [10, 11])
        #expect(filtered.value == 3.5)
        #expect(filtered.skippedRecords.contains { $0.reason == .outsideSelectedYears })
        #expect(GPAConversionCalculator.calculate(courses: courses, gradeYears: [], policy: .unweighted4Point).value == nil)
    }

    @Test("Half-year enrollments include only their posted semester, never projected quarters")
    func semesterRecords() {
        var fall = course(id: 1, sm1: "90", sm2: "50", semester: .fall)
        fall.historicalGrades.rc1 = "100"
        fall.historicalGrades.rc2 = "100"
        var spring = course(id: 2, sm1: "50", sm2: "80", semester: .spring)
        spring.historicalGrades.rc3 = "100"
        let result = report([fall, spring, course(id: 3, sm1: nil)])
        #expect(result.includedRecords.map(\.semester) == [.sm1, .sm2])
        #expect(result.value == 3.5)
        #expect(result.skippedCount == 2)
    }

    @Test("Transcript source grades take precedence over merged values and live bucket estimates")
    func sourceProvenance() {
        var transcript = course(id: 1, sm1: "100")
        transcript.isTranscriptRecord = true
        transcript.postedHistoricalGrades = grades(sm1: "80", sm2: nil)
        var live = course(id: 2, sm1: "70")
        live.currentScores = [BucketScore(bucket: "S1", score: 99)]
        let result = report([transcript, live])
        #expect(result.includedRecords.map(\.percentage) == [80, 70])
        #expect(result.includedRecords.map(\.source) == [.transcript, .skyward])
    }

    @Test("Missing and pass-code grades remain unavailable; numeric zeros are real failures")
    func unavailableGrades() {
        let result = report([
            course(id: 1, sm1: "P"), course(id: 2, sm1: " "),
            course(id: 3, sm1: "NaN"), course(id: 4, sm1: "Infinity"),
            course(id: 5, sm1: "-1"), course(id: 6, sm1: "1e100"),
            course(id: 7, sm1: "0"),
        ])
        #expect(result.includedCount == 1)
        #expect(result.value == 0)
        #expect(result.skippedRecords.filter { $0.reason == .invalidGrade }.count == 4)
        #expect(result.skippedRecords.filter { $0.reason == .nonnumericGrade }.count == 1)
        #expect(report([course(sm1: "P")]).value == nil)
        #expect(report([]).value == nil)
    }


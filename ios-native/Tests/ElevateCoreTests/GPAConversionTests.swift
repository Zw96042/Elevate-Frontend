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

    @Test("Duplicate source records count once and conflicting posted grades count neither")
    func duplicateRecords() {
        let source = course(sm1: "90", sm2: "80")
        let repeated = report([source, source])
        #expect(repeated.includedCount == 2)
        #expect(repeated.skippedRecords.allSatisfy { $0.reason == .duplicateRecord })
        #expect(Set(repeated.skippedRecords.map(\.id)).count == repeated.skippedCount)
        var conflict = source
        conflict.historicalGrades.sm1 = "70"
        let disputed = report([source, conflict])
        #expect(disputed.includedCount == 1)
        #expect(disputed.value == 3)
        #expect(disputed.skippedRecords.filter { $0.reason == .conflictingDuplicate }.count == 2)
        var missing = source
        missing.historicalGrades.sm1 = nil
        #expect(report([missing, source]).includedCount == 2)
    }

    @Test("Manual records fill only years with no Skyward courses, with full precision")
    func manualFallback() {
        let result = GPAConversionCalculator.calculate(
            courses: [course(year: 10, sm1: nil)],
            manualClassesByYear: [
                9: [ManualClass(className: "AP History", sm1: 90, sm2: nil)],
                10: [ManualClass(className: "English", sm1: 100, sm2: 100)],
                11: [ManualClass(className: "English", sm1: 80, sm2: 80)],
            ], policy: .unweighted4Point
        )
        #expect(result.includedCount == 3)
        #expect(result.includedRecords.allSatisfy { $0.source == .manual })
        #expect(result.value == 10.0 / 3.0)
        #expect(result.includedRecords.map(\.gradeYear) == [9, 11, 11])
    }

    @Test("Current semesters become eligible only after the district's final school day")
    func completedSemesterBoundaries() {
        var current = course(year: 11, sm1: "90", sm2: "80")
        current.academicYear = "2026-2027"
        current.academicYearIsVerified = true
        for (date, expectedTerms) in [
            (date(2026, 10, 4), [TermLabel]()),
            (date(2026, 12, 18, hour: 23, minute: 59, second: 59), []),
            (date(2026, 12, 19), [.sm1]),
            (date(2027, 1, 5), [.sm1]),
            (date(2027, 5, 21, hour: 23, minute: 59, second: 59), [.sm1]),
            (date(2027, 5, 22), [.sm1, .sm2]),
        ] {
            let result = completed([current], asOf: date)
            #expect(result.includedRecords.map(\.semester) == expectedTerms)
            #expect(result.skippedCount == 2 - expectedTerms.count)
            #expect(result.skippedRecords.allSatisfy { $0.reason == .inProgress })
        }
        // The ordinary converter retains its previous behavior when the gate
        // is omitted, including numeric fields on ongoing courses.
        #expect(report([current]).includedCount == 2)
    }

    @Test("Verified source years distinguish completed, current, and future records")
    func completedSourceYears() {
        var past = course(id: 1, year: 10, sm1: "0", sm2: "90")
        past.academicYear = "2025-2026"
        var current = course(id: 2, year: 11, sm1: "95", sm2: "95")
        current.academicYear = "2026-2027"
        var future = course(id: 3, year: 12, sm1: "100", sm2: "100")
        future.academicYear = "2027-2028"
        future.academicYearIsVerified = true
        let result = completed([past, current, future], asOf: date(2026, 10, 4))
        #expect(result.includedRecords.map(\.percentage) == [0, 90])
        #expect(result.value == 2)
        #expect(result.skippedRecords.filter { $0.reason == .inProgress }.count == 4)
        #expect(completed([future], asOf: date(2027, 5, 22)).includedCount == 0)
    }

    @Test("School years advance on Chicago August 1, independently of a displayed semester")
    func completedSchoolYearAndTimezone() {
        var current = course(sm1: "90", sm2: "80")
        current.academicYear = "2026-2027"
        let chicagoMidnight = date(2026, 8, 1)
        #expect(completed([current], asOf: chicagoMidnight.addingTimeInterval(-1)).includedCount == 0)
        #expect(completed([current], asOf: chicagoMidnight).includedCount == 0)
        let nextSchoolYear = date(2027, 8, 1)
        #expect(completed([current], asOf: nextSchoolYear.addingTimeInterval(-1)).includedCount == 2)
        #expect(completed([current], asOf: nextSchoolYear).includedCount == 2)
        let semesterMidnight = date(2026, 12, 19)
        #expect(completed([current], asOf: semesterMidnight.addingTimeInterval(-1)).includedCount == 0)
        #expect(completed([current], asOf: semesterMidnight).includedCount == 1)
    }

    @Test("Merged and manufactured live records cannot masquerade as completed transcript grades")
    func completedMergedAndManufactured() {
        var merged = course(id: 1, year: 11, sm1: "99", sm2: "99")
        merged.isTranscriptRecord = true
        merged.postedHistoricalGrades = grades(sm1: "90", sm2: "80")
        merged.currentAcademicYearIsVerified = nil
        var manufactured = course(id: 2, year: 11, sm1: "95", sm2: "95")
        manufactured.academicYear = "2025-2026"
        manufactured.academicYearIsVerified = false
        manufactured.isTranscriptRecord = true
        let october = completed([merged, manufactured], asOf: date(2026, 10, 4))
        #expect(october.value == nil)
        #expect(october.skippedRecords.allSatisfy { $0.reason == .inProgress })
        let december = completed([merged, manufactured], asOf: date(2026, 12, 19))
        #expect(december.includedRecords.map(\.percentage) == [90, 95])
        #expect(december.includedRecords.allSatisfy { $0.semester == .sm1 })
        manufactured.academicYear = "2027-2028"
        #expect(completed([manufactured], asOf: date(2026, 12, 19)).value == nil)
    }

    @Test("A real live overlay cannot inherit completion from a prior transcript year")
    func completedRealLiveMergeWithUnknownGrade() {
        let history: AcademicHistory = ["2025-2026": AcademicYear(grade: 11, courses: [
            "English": HistoryCourse(courseName: "English", terms: "1 - 4", sm1: "90", sm2: "80"),
        ])]
        let live: [GradebookCourse] = [
            GradebookCourse(course: 100, courseName: "English", instructor: "Synthetic", period: 1,
                time: nil, scores: [("SEM 1", 100), ("SEM 2", 100)], stuId: "synthetic",
                corNumId: 100, section: "01", gbId: "book-100"),
            GradebookCourse(course: 200, courseName: "AP Biology", instructor: "Synthetic", period: 2,
                time: nil, scores: [("SEM 1", 100), ("SEM 2", 100)], stuId: "synthetic",
                corNumId: 200, section: "01", gbId: "book-200"),
        ]
        let merged = SkywardHistoryAPI.combine(history: history, gradebook: live, fallbackGrade: nil)
        let courses = UnifiedCourseTransformer.transform(history: merged)
        let biology = courses.first { $0.courseName == "AP Biology" }
        #expect(biology?.isTranscriptRecord == false)
        #expect(biology?.academicYear == "2025-2026")
        #expect(biology?.academicYearIsVerified == true)
        #expect(biology?.currentAcademicYearIsVerified == nil)
        let october = completed(courses, asOf: date(2026, 10, 4))
        #expect(october.includedRecords.map(\.percentage) == [90, 80])
        #expect(october.includedRecords.allSatisfy { $0.courseName == "English" && $0.source == .transcript })
        #expect(october.skippedRecords.filter { $0.courseName == "AP Biology" }.allSatisfy { $0.reason == .inProgress })
        let december = completed(courses, asOf: date(2026, 12, 19))
        #expect(december.includedRecords.filter { $0.courseName == "AP Biology" }.map(\.semester) == [.sm1])
        let may = completed(courses, asOf: date(2027, 5, 22))
        #expect(may.includedRecords.filter { $0.courseName == "AP Biology" }.map(\.semester) == [.sm1, .sm2])
        #expect(may.includedRecords.filter { $0.courseName == "English" }.map(\.percentage) == [90, 80])
        #expect(report(courses).includedCount == 4)
    }

    @Test("Undated completed records require an immutable snapshot or an earlier known nonlive grade year")
    func completedUndatedEvidence() {
        var immutable = archived(course(id: 1, year: 9, sm1: "100"))
        immutable.isTranscriptRecord = true
        immutable.postedHistoricalGrades = grades(sm1: "80", sm2: nil)
        let ambiguous = archived(course(id: 2, year: 10, sm1: "90"))
        #expect(completed([immutable, ambiguous], asOf: date(2026, 10, 4)).includedRecords.map(\.percentage) == [80])
        let live = course(id: 3, year: 11, sm1: "95")
        let anchored = completed([immutable, ambiguous, live], asOf: date(2026, 10, 4))
        #expect(anchored.includedRecords.map(\.gradeYear) == [9, 10])
        var futureGrade = immutable
        futureGrade.gradeYear = 12
        #expect(completed([live, futureGrade], asOf: date(2027, 5, 22)).includedCount == 1)
        immutable.gradeYear = nil
        #expect(completed([immutable], asOf: date(2026, 10, 4)).skippedRecords.allSatisfy { $0.reason == .unknownYear })
    }

    @Test("Completed manual fallback excludes current and future work without guessing an unknown year")
    func completedManualFallback() {
        let manual: [Int: [ManualClass]] = [
            9: [ManualClass(className: "English", sm1: 80, sm2: 90)],
            11: [ManualClass(className: "Chemistry", sm1: 100, sm2: 100)],
            12: [ManualClass(className: "Physics", sm1: 100, sm2: 100)],
        ]
        let result = GPAConversionCalculator.calculate(
            courses: [course(year: 11, sm1: "90")], manualClassesByYear: manual,
            policy: .unweighted4Point, completedOnly: true, asOf: date(2026, 10, 4)
        )
        #expect(result.includedRecords.map(\.gradeYear) == [9, 9])
        #expect(result.includedRecords.allSatisfy { $0.source == .manual })
        #expect(result.skippedRecords.filter { $0.gradeYear == 12 }.allSatisfy { $0.reason == .inProgress })
        let noAnchor = GPAConversionCalculator.calculate(
            courses: [], manualClassesByYear: manual, policy: .unweighted4Point,
            completedOnly: true, asOf: date(2027, 5, 22)
        )
        #expect(noAnchor.value == nil)
        #expect(noAnchor.skippedCount == 6)
    }

    @Test("Completion filtering retains duplicate, zero, pass-code, and missing-grade behavior")
    func completedDiagnostics() {
        var past = course(id: 1, year: 10, sm1: "0", sm2: "P")
        past.academicYear = "2025-2026"
        var quartersOnly = course(id: 2, year: 10, sm1: nil)
        quartersOnly.academicYear = "2025-2026"
        quartersOnly.historicalGrades.rc1 = "100"
        quartersOnly.historicalGrades.rc2 = "100"
        let result = completed([past, past, quartersOnly], asOf: date(2026, 10, 4))
        #expect(result.value == 0)
        #expect(result.includedCount == 1)
        #expect(result.skippedRecords.filter { $0.reason == .duplicateRecord }.count == 2)
        #expect(result.skippedRecords.filter { $0.reason == .nonnumericGrade }.count == 1)
        #expect(result.skippedRecords.filter { $0.reason == .missingGrade }.count == 2)
        #expect(Set(result.skippedRecords.map(\.id)).count == result.skippedCount)
        // A manufactured ongoing duplicate must not replace or conflict with
        // the verified prior-year semester on the same source identity.
        var manufactured = past
        manufactured.academicYearIsVerified = false
        manufactured.historicalGrades.sm1 = "100"
        let mixed = completed([past, manufactured], asOf: date(2026, 10, 4))
        #expect(mixed.includedRecords.map(\.percentage) == [0])
        #expect(mixed.skippedRecords.filter { $0.reason == .inProgress }.count == 2)
        #expect(!mixed.skippedRecords.contains { $0.reason == .conflictingDuplicate })
    }


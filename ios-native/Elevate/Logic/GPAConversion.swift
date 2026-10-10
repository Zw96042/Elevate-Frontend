import Foundation

/// Explicit estimates, separate from the district's 100-point GPACalculator.
enum GPAConversionPolicy: String, CaseIterable, Identifiable, Hashable {
    case unweighted4Point
    case weighted5Point

    var id: String { rawValue }
    var title: String {
        switch self {
        case .unweighted4Point: return "4.0 unweighted"
        case .weighted5Point: return "5.0 weighted"
        }
    }
    var maximum: Double { self == .unweighted4Point ? 4 : 5 }
    var explanation: String {
        let cutoffs = "Each posted semester grade converts to points: 90 or above = 4, 80 to below 90 = 3, 70 to below 80 = 2, 60 to below 70 = 1, below 60 = 0. No plus/minus grades or rounding before conversion."
        switch self {
        case .unweighted4Point: return cutoffs
        case .weighted5Point:
            return cutoffs + " Passing grades (60 or above) receive +1 for AP-level courses or +0.5 for Honors; failing grades receive no bonus. Elevate's course-level policy includes district advanced-course exceptions and verified catalog codes. These labels do not verify a college's honors eligibility."
        }
    }

    func points(for percentage: Double, level: CourseLevel) -> Double? {
        guard percentage.isFinite, percentage >= 0,
              percentage <= AcademicScoreValue.magnitudeLimit else { return nil }
        let base: Double
        switch percentage {
        case 90...: base = 4
        case 80..<90: base = 3
        case 70..<80: base = 2
        case 60..<70: base = 1
        default: base = 0
        }
        guard self == .weighted5Point, base > 0 else { return base }
        switch level {
        case .ap: return base + 1
        case .honors: return base + 0.5
        case .regular: return base
        }
    }
}

enum GPAConversionSource: String, Hashable {
    case transcript = "Posted transcript"
    case skyward = "Skyward semester grade"
    case manual = "Manual entry"
}

struct GPAConversionRecord: Hashable, Identifiable {
    var id: String
    var courseName: String
    var gradeYear: Int
    var semester: TermLabel
    var percentage: Double
    var points: Double
    var source: GPAConversionSource
    var courseLevel: CourseLevel = .regular
}

enum GPAConversionSkipReason: String, Hashable, CaseIterable {
    case missingGrade = "No posted semester grade"
    case nonnumericGrade = "Pass code or nonnumeric grade"
    case invalidGrade = "Invalid numeric grade"
    case unknownYear = "Grade year unavailable"
    case outsideHighSchool = "Outside grades 9–12"
    case outsideSelectedYears = "Outside selected years"
    case duplicateRecord = "Duplicate semester record"
    case conflictingDuplicate = "Conflicting duplicate semester grades"
    case inProgress = "Semester not completed"
}

struct GPAConversionSkippedRecord: Hashable, Identifiable {
    var id: String
    var courseName: String
    var gradeYear: Int?
    var semester: TermLabel
    var reason: GPAConversionSkipReason
}

struct GPAConversionReport {
    var policy: GPAConversionPolicy
    var includedRecords: [GPAConversionRecord]
    var skippedRecords: [GPAConversionSkippedRecord]
    var completedOnly: Bool = false
    var includedCount: Int { includedRecords.count }
    var skippedCount: Int { skippedRecords.count }
    /// Keep calculation precision; the caller formats only for display.
    var value: Double? {
        guard !includedRecords.isEmpty else { return nil }
        return includedRecords.reduce(0) { $0 + $1.points } / Double(includedRecords.count)
    }
    var scopeExplanation: String {
        (completedOnly ? "Completed semesters only. " : "") + "Known grades 9–12 only, using posted semester grades. Every included semester counts equally because course credits are unavailable. Missing, pass-code, and invalid grades are skipped. Repeated courses retain separate source identities; no college repeat replacement or subject-eligibility rules are applied. Manual entries fill only years with no Skyward courses. This is an estimate, not an official transcript or admissions GPA."
    }
}

enum GPAConversionCalculator {
    static func calculate(
        courses: [UnifiedCourseData],
        manualClassesByYear: [Int: [ManualClass]] = [:],
        gradeYears: Set<Int>? = nil,
        policy: GPAConversionPolicy,
        completedOnly: Bool = false,
        asOf: Date = Date()
    ) -> GPAConversionReport {
        struct Candidate {
            var id: String
            var name: String
            var year: Int?
            var semester: TermLabel
            var grade: String?
            var source: GPAConversionSource
            var level: CourseLevel
            var isCompleted: Bool
        }
        let completion = GPAConversionCompletionContext(courses: courses, asOf: asOf)
        var candidates: [Candidate] = []
        for course in courses {
            let grades = course.isTranscriptRecord == true ? course.postedGrades : course.historicalGrades
            for semester in [TermLabel.sm1, .sm2] where course.availableTerms.contains(semester) {
                // A source year separates otherwise identical older cached identities.
                let identity = "\(course.id)|\(course.academicYear ?? "")|\(semester.historicalKey)"
                candidates.append(Candidate(
                    id: identity, name: course.courseName, year: course.gradeYear,
                    semester: semester, grade: grades[semester.historicalKey],
                    source: course.isTranscriptRecord == true ? .transcript : .skyward,
                    level: course.courseLevel,
                    isCompleted: completion.isCompleted(course: course, semester: semester)
                ))
            }
        }
        let realYears = Set(courses.compactMap(\.gradeYear))
        for year in manualClassesByYear.keys.sorted() where !realYears.contains(year) {
            for course in manualClassesByYear[year] ?? [] {
                for semester in [TermLabel.sm1, .sm2] {
                    let grade = semester == .sm1 ? course.sm1 : course.sm2
                    candidates.append(Candidate(
                        id: "manual|\(year)|\(course.id)|\(semester.historicalKey)",
                        name: course.className, year: year, semester: semester,
                        grade: grade.map { String($0) }, source: .manual,
                        level: CourseLevelDetector.level(for: course.className),
                        isCompleted: completion.isCompleted(manualGradeYear: year, semester: semester)
                    ))
                }
            }
        }
        var report = GPAConversionReport(policy: policy, includedRecords: [], skippedRecords: [], completedOnly: completedOnly)
        func skip(_ candidate: Candidate, reason: GPAConversionSkipReason, index: Int) {
            report.skippedRecords.append(GPAConversionSkippedRecord(
                id: "\(candidate.id)|skip|\(index)", courseName: candidate.name,
                gradeYear: candidate.year, semester: candidate.semester, reason: reason
            ))
        }
        // Process identities in source order; conflicting numeric values never
        // pick an arbitrary winner. Missing duplicate rows may yield to a posted row.
        let groups = Dictionary(grouping: candidates, by: \.id)
        var processed: Set<String> = []
        for first in candidates where processed.insert(first.id).inserted {
            let group = groups[first.id] ?? [first]
            // An ongoing duplicate cannot conflict with or replace a completed
            // source record. Retain original offsets for stable diagnostic IDs.
            let eligible = group.enumerated().filter { index, candidate in
                if completedOnly && !candidate.isCompleted {
                    skip(candidate, reason: .inProgress, index: index)
                    return false
                }
                return true
            }
            let numericValues = Set(eligible.compactMap { AcademicScoreValue.finiteDouble($0.element.grade) })
            if numericValues.count > 1 {
                for (index, candidate) in eligible {
                    skip(candidate, reason: .conflictingDuplicate, index: index)
                }
                continue
            }
            let selectedIndex = eligible.first {
                AcademicScoreValue.finiteDouble($0.element.grade) != nil
            }?.offset ?? eligible.first?.offset
            for (index, candidate) in eligible {
                guard index == selectedIndex else {
                    skip(candidate, reason: .duplicateRecord, index: index)
                    continue
                }
                guard let year = candidate.year else {
                    skip(candidate, reason: .unknownYear, index: index); continue
                }
                guard (9...12).contains(year) else {
                    skip(candidate, reason: .outsideHighSchool, index: index); continue
                }
                if let gradeYears, !gradeYears.contains(year) {
                    skip(candidate, reason: .outsideSelectedYears, index: index); continue
                }
                guard let text = candidate.grade?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    skip(candidate, reason: .missingGrade, index: index); continue
                }
                guard let percentage = Double(text) else {
                    skip(candidate, reason: .nonnumericGrade, index: index); continue
                }
                guard let points = policy.points(for: percentage, level: candidate.level) else {
                    skip(candidate, reason: .invalidGrade, index: index); continue
                }
                report.includedRecords.append(GPAConversionRecord(
                    id: candidate.id, courseName: candidate.name, gradeYear: year,
                    semester: candidate.semester, percentage: percentage,
                    points: points, source: candidate.source, courseLevel: candidate.level
                ))
            }
        }
        return report
    }
}

/// Completion evidence is independent of the GPA screen's selected term/year.
/// Undated records need an immutable transcript snapshot or a known live grade
/// year; a numeric semester field alone does not prove a semester has ended.
private struct GPAConversionCompletionContext {
    let schoolYearStart: Int
    let term: TermLabel
    let currentGradeYear: Int?

    init(courses: [UnifiedCourseData], asOf: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let year = calendar.component(.year, from: asOf)
        schoolYearStart = calendar.component(.month, from: asOf) >= 8 ? year : year - 1
        term = AcademicCalendar.currentTerm(for: asOf)
        let start = schoolYearStart
        currentGradeYear = courses.filter { course in
            guard course.hasGradebookParams else { return false }
            if let sourceStart = course.academicYear.flatMap(AcademicYearKey.startYear) {
                if sourceStart > start { return false }
                // combine() can attach an unmatched live row to the latest
                // prior transcript bucket when the live grade is unknown.
                // Its inherited year does not date that live enrollment.
                if course.isTranscriptRecord == false { return true }
                if course.academicYearIsVerified != false { return sourceStart == start }
            }
            // A fabricated bucket is not evidence of a completed prior year.
            return true
        }.compactMap(\.gradeYear).filter { (9...12).contains($0) }.max()
    }

    func isCompleted(course: UnifiedCourseData, semester: TermLabel) -> Bool {
        if course.isTranscriptRecord == false {
            // A live-only overlay has no immutable transcript semester. The
            // containing history bucket may be older than this enrollment.
            if let sourceStart = course.academicYear.flatMap(AcademicYearKey.startYear),
               sourceStart > schoolYearStart { return false }
            return currentSemesterHasEnded(semester)
        }
        if let sourceStart = course.academicYear.flatMap(AcademicYearKey.startYear) {
            // Even an unverified future bucket cannot establish completion.
            if sourceStart > schoolYearStart { return false }
            if sourceStart == schoolYearStart { return currentSemesterHasEnded(semester) }
            if course.academicYearIsVerified != false { return true }
        }
        if let year = course.gradeYear, let currentGradeYear {
            if year > currentGradeYear { return false }
            if year == currentGradeYear { return currentSemesterHasEnded(semester) }
            if !course.hasGradebookParams { return true }
        }
        // Only the immutable source snapshot establishes completion without a
        // trustworthy date. Merged historicalGrades may be midsemester values.
        return course.isTranscriptRecord == true && course.postedHistoricalGrades != nil
    }

    func isCompleted(manualGradeYear: Int, semester: TermLabel) -> Bool {
        guard let currentGradeYear else { return false }
        if manualGradeYear < currentGradeYear { return true }
        if manualGradeYear == currentGradeYear { return currentSemesterHasEnded(semester) }
        return false
    }

    private func currentSemesterHasEnded(_ semester: TermLabel) -> Bool {
        switch semester {
        case .sm1: return [.sm1, .q3, .q4, .sm2].contains(term)
        case .sm2: return term == .sm2
        default: return false
        }
    }
}

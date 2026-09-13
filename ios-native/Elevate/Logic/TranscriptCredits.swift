import Foundation

/// Immutable source rows used only for credit planning. No credit fields are
/// supplied by the current endpoint; inferred allocations remain estimates.
struct PlanningTranscriptCourse: Codable, Hashable, Identifiable {
    var academicYear: String
    var gradeYear: Int?
    var name: String
    var terms: String
    var sm1: String?
    var sm2: String?
    var ex1: String? = nil
    var ex2: String? = nil
    var isNonLinked: Bool = false
    var id: String { sourceSignature }
    var sourceSignature: String {
        [academicYear, gradeYear.map(String.init) ?? "", name, terms, sm1 ?? "", sm2 ?? "",
         ex1 ?? "", ex2 ?? "", String(isNonLinked)].map { "\($0.utf8.count):\($0)" }.joined()
    }
}

/// Corrections replace a source allocation (including zero to exclude it).
/// They never add a second earned record for the same source signature.
struct TranscriptCreditOverride: Codable, Equatable, Identifiable {
    var id: String
    var credits: Double
    var subject: CoursePlanSubject
}

enum TranscriptCreditStatus: String {
    case estimated = "Estimated from posted grades"
    case corrected = "Your correction"
    case needsReview = "Needs review"
    case notEarned = "No passing credit"
    case excluded = "Not counted"
    case inProgress = "Semester not completed"
}

struct TranscriptCreditRecord: Identifiable {
    var id: String
    var name: String
    var academicYear: String
    var gradeYear: Int?
    var semester: TermLabel
    var subject: CoursePlanSubject?
    var credits: Double
    var status: TranscriptCreditStatus
    var detail: String
}

struct TranscriptCreditReport {
    var records: [TranscriptCreditRecord]
    var usedLegacyFallback: Bool
    var orphanedOverrideIDs: [String]
    var unresolved: [TranscriptCreditRecord] { records.filter { $0.status == .needsReview } }
    var total: Double { records.reduce(0) { $0 + $1.credits } }
    func credits(for subject: CoursePlanSubject) -> Double {
        records.filter { $0.subject == subject }.reduce(0) { $0 + $1.credits }
    }
}

/// Prospective credit from verified live enrollment; never an awarded credit.
enum CurrentCourseCreditStatus: String {
    case expected = "Expected if passed"
    case needsReview = "Needs review"
    case excluded = "Not counted"
}

struct CurrentCourseCredit: Identifiable {
    var id: String
    var course: UnifiedCourseData
    var sourceCourseIDs: [String]
    var name: String
    var academicYear: String?
    var subject: CoursePlanSubject?
    var semesters: [TermLabel]
    var credits: Double
    var status: CurrentCourseCreditStatus
    var detail: String
}

enum TranscriptCreditCalculator {
    private struct Definition {
        var key: String
        var subject: CoursePlanSubject
        var credits: Double = 1
        var semesterOnly: Bool = false
        var middleSchoolEligible: Bool = false
        var repeatable: Bool = false
    }
    private struct Candidate {
        var course: PlanningTranscriptCourse
        var semester: TermLabel
        var grade: String?
        var definition: Definition?
        var normalizedName: String
        var groupingKey: String {
            "\(course.academicYear)|\(definition?.key ?? normalizedName)|\(semester.historicalKey)"
        }
    }

    /// nil projection means an older cache: use immutable posted snapshots only,
    /// preserving unknown names/grades for review rather than calling them empty.
    static func calculate(courses: [UnifiedCourseData], planningTranscriptCourses: [PlanningTranscriptCourse]? = nil,
                          overrides: [TranscriptCreditOverride] = [], asOf: Date = Date()) -> TranscriptCreditReport {
        let attached = courses.compactMap(\.planningTranscriptCourses)
        let source = planningTranscriptCourses ?? (attached.isEmpty ? nil : attached.flatMap { $0 })
        let fallback = source == nil
        let rows = source ?? courses.filter {
            $0.isPlanningOnly != true && $0.isTranscriptRecord != false
                && ($0.isTranscriptRecord == true || $0.postedHistoricalGrades != nil)
        }.map { course in
            let grades = course.postedGrades
            return PlanningTranscriptCourse(academicYear: course.academicYearIsVerified == false ? "" : course.academicYear ?? "",
                gradeYear: course.gradeYear, name: course.courseName, terms: course.termLength,
                sm1: grades.sm1, sm2: grades.sm2, ex1: grades.ex1, ex2: grades.ex2)
        }
        var candidates: [Candidate] = []
        for course in rows {
            let normalized = normalize(course.name)
            var definition = definition(for: course.name)
            if definition?.key == "ipc", course.gradeYear == 8,
               let year = AcademicYearKey.startYear(course.academicYear), year < 2021 {
                definition?.subject = .elective
                definition?.middleSchoolEligible = true
            }
            let semester = UnifiedCourseTransformer.inferSemester(course.terms)
            var terms: [TermLabel]
            switch semester {
            case .fall: terms = [.sm1]
            case .spring: terms = [.sm2]
            case .both: terms = [.sm1, .sm2]
            case .unknown:
                terms = []
                if nonempty(course.sm1) != nil { terms.append(.sm1) }
                if nonempty(course.sm2) != nil { terms.append(.sm2) }
                if terms.isEmpty { terms = [.sm1] }
            }
            // Semester catalog courses must never acquire twice their credit
            // because a malformed source has both grade slots populated.
            for term in terms {
                candidates.append(Candidate(course: course, semester: term,
                    grade: term == .sm1 ? course.sm1 : course.sm2, definition: definition, normalizedName: normalized))
            }
        }
        let groups = Dictionary(grouping: candidates, by: \.groupingKey)
        let overrideGroups = Dictionary(grouping: overrides, by: \.id)
        var usedOverrideIDs: Set<String> = []
        var records: [TranscriptCreditRecord] = []
        // First successful credit per equivalent course/semester, including
        // Honors/AP variants. Repeatable catalog electives retain later years.
        var countedUnits: Set<String> = []
        var awardedByDefinition: [String: Double] = [:]
        var physicalEducationCredits = 0.0
        for key in groups.keys.sorted() {
            let group = groups[key]!.sorted { $0.course.sourceSignature < $1.course.sourceSignature }
            let first = group[0]
            let signatures = Set(group.map { $0.course.sourceSignature }).sorted()
            let recordID = "credit|\(first.semester.historicalKey)|" + signatures.map { "\($0.utf8.count):\($0)" }.joined()
            let definition = first.definition
            var record = TranscriptCreditRecord(id: recordID, name: first.course.name, academicYear: first.course.academicYear,
                gradeYear: first.course.gradeYear, semester: first.semester, subject: definition?.subject,
                credits: 0, status: .needsReview, detail: "Course subject or credit value is not recognized in the district catalog.")
            let corrections = overrideGroups[recordID] ?? []
            if !corrections.isEmpty { usedOverrideIDs.insert(recordID) }
            let eligibleCorrection = corrections.count == 1 ? corrections.first : nil
            if let correction = eligibleCorrection, correction.credits.isFinite,
               (0...4).contains(correction.credits) {
                record.subject = correction.subject
                record.credits = correction.credits
                record.status = .corrected
                record.detail = "Your allocation replaces the automatic estimate for this exact source record."
            } else if !corrections.isEmpty {
                record.detail = "Conflicting or invalid saved corrections need review."
            } else if let gradeYear = first.course.gradeYear, gradeYear < 9,
                      definition.map({ eligibleMiddleSchool($0, gradeYear: gradeYear) }) != true {
                // The academic-history endpoint includes the entire middle-school
                // schedule. Unrecognized ordinary rows are not credit candidates.
                // Keep the source identity so an explicit correction can replace
                // this exclusion without sending every row to credit review.
                record.status = .excluded
                record.detail = "This pre-high-school course is not a recognized high-school credit course."
            } else if AcademicYearKey.startYear(first.course.academicYear) == nil {
                record.detail = "A verified school year is unavailable."
            } else if !semesterCompleted(year: first.course.academicYear, semester: first.semester, asOf: asOf) {
                record.status = .inProgress
                record.detail = "This source semester has not ended."
            } else if let definition {
                if definition.credits == 0 {
                    record.status = .excluded
                    record.detail = "The district catalog awards no credit for this course."
                } else if first.course.gradeYear == nil || !(6...12).contains(first.course.gradeYear!) {
                    record.detail = "Source grade level is unavailable or outside the supported credit years."
                } else if definition.key == "physics12", (AcademicYearKey.startYear(first.course.academicYear) ?? 0) < 2020 {
                    record.detail = "The two-credit Physics 1&2 rule is documented from 2020–21; this older record needs review."
                } else {
                    let texts = Set(group.compactMap { nonempty($0.grade) })
                    let values = Set(texts.compactMap { AcademicScoreValue.finiteDouble($0) })
                    let hasInvalid = texts.contains { AcademicScoreValue.finiteDouble($0) == nil }
                    if values.count > 1 || (hasInvalid && !values.isEmpty) {
                        record.detail = "Equivalent source rows have conflicting posted semester grades."
                    } else if hasInvalid {
                        record.detail = "Pass codes and nonnumeric grades do not establish an awarded credit value."
                    } else if let value = values.first, value >= 0 {
                        if value >= 70 {
                            record.credits = definition.semesterOnly ? definition.credits : definition.credits / 2
                            record.status = .estimated
                            record.detail = "Passing posted semester grade; catalog credit allocation. Attendance, transfer and award conditions are not verified."
                        } else if first.semester == .sm1, value >= 65, !definition.semesterOnly,
                                  mayRecoverFall(first, fallScore: value, allCandidates: candidates) {
                            record.detail = "Fall grade may qualify for same-year averaging. Summer, correspondence and exam provenance must be reviewed before awarding fall credit."
                        } else {
                            record.status = .notEarned
                            record.detail = "Posted semester grade is below 70. A failing spring grade is not averaged up for credit."
                        }
                    } else {
                        record.detail = texts.isEmpty ? "No posted semester grade is available." : "Posted semester grade is invalid."
                    }
                }
            }
            if let definition, record.credits > 0 {
                let scope = definition.repeatable ? first.course.academicYear : "allYears"
                let unit = "\(scope)|\(definition.key)|\(definition.semesterOnly ? "course" : first.semester.historicalKey)"
                let awardKey = "\(scope)|\(definition.key)"
                if countedUnits.contains(unit) {
                    record.credits = 0
                    record.status = .excluded
                    record.detail = "An equivalent course semester has already been counted; a repeat does not add duplicate credit."
                } else if record.status != .corrected {
                    let available = max(0, definition.credits - awardedByDefinition[awardKey, default: 0])
                    record.credits = min(record.credits, available)
                    if record.credits == 0 {
                        record.status = .excluded
                        record.detail = "The catalog credit maximum for this equivalent course has already been counted."
                    }
                }
                if record.credits > 0 {
                    countedUnits.insert(unit)
                    awardedByDefinition[awardKey, default: 0] += record.credits
                }
            }
            // The published district cap is four PE credits; music/dance are
            // allocated once to fine arts here, not also counted as PE.
            if record.subject == .physicalEducation, record.credits > 0, record.status != .corrected {
                let allowed = max(0, 4 - physicalEducationCredits)
                record.credits = min(record.credits, allowed)
                if record.credits == 0 {
                    record.status = .excluded
                    record.detail = "The district maximum of four PE credits has already been counted."
                }
            }
            if record.subject == .physicalEducation { physicalEducationCredits += record.credits }
            records.append(record)
        }
        return TranscriptCreditReport(records: records, usedLegacyFallback: fallback,
            orphanedOverrideIDs: Set(overrides.map(\.id)).subtracting(usedOverrideIDs).sorted())
    }

    /// Independent live membership can establish the observed semester without
    /// claiming a source academic year. Verified year/terms additionally support
    /// upcoming enrolled semesters. Latest transcript buckets are not proof.
    static func currentCourses(courses: [UnifiedCourseData], earned: TranscriptCreditReport,
                               asOf: Date = Date()) -> [CurrentCourseCredit] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let ongoingYear = calendar.component(.year, from: asOf) - (calendar.component(.month, from: asOf) < 8 ? 1 : 0)
        let live = courses.filter { course in
            guard course.isPlanningOnly != true, !course.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  course.isCurrentEnrollment == true || course.hasGradebookParams else { return false }
            // A saved historical gradebook identity does not become enrollment.
            if course.isCurrentEnrollment != true, let year = course.academicYear, course.academicYearIsVerified != false,
               let start = AcademicYearKey.startYear(year), start != ongoingYear { return false }
            return true
        }
        let groups = Dictionary(grouping: live) { course in
            let scope = course.isCurrentEnrollment == true && course.currentAcademicYearIsVerified != true
                ? "observed-enrollment" : course.academicYear ?? ""
            return "\(scope)|\(equivalenceKey(for: course.courseName))"
        }
        var records: [CurrentCourseCredit] = []
        var allocatedByDefinition: [String: Double] = [:]
        var allocatedUnits: Set<String> = []
        var physicalEducationCredits = earned.credits(for: .physicalEducation)
        for key in groups.keys.sorted() {
            let group = groups[key]!.sorted { $0.id < $1.id }
            let first = group[0]
            let definition = definition(for: first.courseName)
            let sourceIDs = Set(group.map(\.id)).sorted()
            // A different course with incomplete year metadata must not erase
            // this enrollment's independently verified school-year evidence.
            let verifiedYear = first.academicYear.flatMap { year -> String? in
                guard AcademicYearKey.startYear(year) == ongoingYear,
                      group.allSatisfy({ $0.academicYear == year && $0.academicYearIsVerified != false && $0.currentAcademicYearIsVerified == true }) else { return nil }
                return year
            }
            let activeSemester: TermLabel = AcademicCalendar.currentTerm(for: asOf).isFall ? .sm1 : .sm2
            let independentEnrollment = group.allSatisfy { course in
                guard course.isCurrentEnrollment == true,
                      let observedAt = course.currentEnrollmentObservedAt,
                      observedAt.timeIntervalSince1970.isFinite, observedAt <= asOf else { return false }
                let observedYear = calendar.component(.year, from: observedAt) - (calendar.component(.month, from: observedAt) < 8 ? 1 : 0)
                return observedYear == ongoingYear && AcademicCalendar.currentTerm(for: observedAt).isFall == activeSemester.isFall
            }
            var semesters: Set<TermLabel> = []
            var hasUnknownTerms = false
            for course in group {
                if verifiedYear == nil {
                    switch course.currentEnrollmentSemester {
                    case .fall: semesters.insert(.sm1)
                    case .spring: semesters.insert(.sm2)
                    case .both: semesters.formUnion([.sm1, .sm2])
                    case .unknown, nil: hasUnknownTerms = true
                    }
                    continue
                }
                let inferred = UnifiedCourseTransformer.inferSemester(course.termLength)
                let semester = course.semester == .unknown ? inferred : course.semester
                if inferred != .unknown && semester != inferred { hasUnknownTerms = true }
                switch semester {
                case .fall: semesters.insert(.sm1)
                case .spring: semesters.insert(.sm2)
                case .both: semesters.formUnion([.sm1, .sm2])
                case .unknown: hasUnknownTerms = true
                }
            }
            let terms = [TermLabel.sm1, .sm2].filter { semesters.contains($0) }
            var record = CurrentCourseCredit(id: "current|\(key.utf8.count):\(key)", course: first,
                sourceCourseIDs: sourceIDs, name: first.courseName,
                academicYear: verifiedYear,
                subject: definition?.subject, semesters: verifiedYear == nil ? terms.filter { $0 == activeSemester } : terms, credits: 0, status: .needsReview,
                detail: "Current enrollment evidence is unavailable or out of date; this course does not yet count toward expected credit targets.")
            guard verifiedYear != nil || independentEnrollment else {
                records.append(record)
                continue
            }
            guard !hasUnknownTerms, !terms.isEmpty else {
                record.detail = "The enrolled semester is unknown or conflicting. Review the schedule before counting prospective credits."
                records.append(record)
                continue
            }
            let enrollmentGrade = verifiedYear == nil ? first.currentEnrollmentGradeYear : first.gradeYear
            if let gradeYear = enrollmentGrade, gradeYear < 9,
               group.allSatisfy({ (verifiedYear == nil ? $0.currentEnrollmentGradeYear : $0.gradeYear) == gradeYear }),
               definition.map({ eligibleMiddleSchool($0, gradeYear: gradeYear) }) != true {
                record.status = .excluded
                record.detail = "This pre-high-school enrollment is not a recognized high-school credit course."
                records.append(record)
                continue
            }
            guard let definition else {
                record.detail = "Course subject or credit value is not recognized in the district catalog."
                records.append(record)
                continue
            }
            guard let gradeYear = enrollmentGrade, (6...12).contains(gradeYear),
                  group.allSatisfy({ (verifiedYear == nil ? $0.currentEnrollmentGradeYear : $0.gradeYear) == gradeYear }) else {
                record.detail = "Source grade level is unavailable or conflicting."
                records.append(record)
                continue
            }
            if definition.credits == 0 || (gradeYear < 9 && !eligibleMiddleSchool(definition, gradeYear: gradeYear)) {
                record.status = .excluded
                record.detail = "This course is not a recognized credit-bearing course for the source grade level."
                records.append(record)
                continue
            }
            // Scope repeatable classes to this year, matching earned-credit rules.
            // Corrections remain earned, but cannot also create prospective credit.
            let earnedEquivalent = earned.records.filter {
                $0.credits > 0 && equivalenceKey(for: $0.name) == definition.key
                    && (!definition.repeatable || AcademicYearKey.startYear($0.academicYear) == ongoingYear)
            }
            let scope = definition.repeatable ? "observed-year-\(ongoingYear)" : "allYears"
            let awardKey = "\(scope)|\(definition.key)"
            let alreadyEarned = earnedEquivalent.reduce(0) { $0 + $1.credits }
            var available = max(0, definition.credits - alreadyEarned - allocatedByDefinition[awardKey, default: 0])
            let eligibleTerms = (verifiedYear == nil ? terms.filter { $0 == activeSemester } : terms).filter {
                !semesterCompleted(year: "\(ongoingYear)-\(ongoingYear + 1)", semester: $0, asOf: asOf)
            }
            for term in eligibleTerms {
                let unit = "\(awardKey)|\(definition.semesterOnly ? "course" : term.historicalKey)"
                guard !allocatedUnits.contains(unit),
                      !earnedEquivalent.contains(where: { definition.semesterOnly || $0.semester == term }) else { continue }
                let credit = min(available, definition.semesterOnly ? definition.credits : definition.credits / 2)
                guard credit > 0 else { continue }
                allocatedUnits.insert(unit)
                record.credits += credit
                available -= credit
            }
            if definition.subject == .physicalEducation {
                record.credits = min(record.credits, max(0, 4 - physicalEducationCredits))
                physicalEducationCredits += record.credits
            }
            allocatedByDefinition[awardKey, default: 0] += record.credits
            if record.credits > 0 {
                record.semesters = eligibleTerms
                record.status = .expected
                record.detail = verifiedYear == nil
                    ? "Expected credit for the observed current semester if passed. The school year and full course duration are unverified, so no upcoming semester is added. Live grades do not award credit."
                    : "Expected credit for the enrolled, unfinished semester(s), including an upcoming semester in this school year. Assumes passing completion and eligibility; live grades do not award credit."
            } else {
                record.status = .excluded
                record.detail = "The enrolled semesters have ended or equivalent catalog credits have already been counted."
            }
            records.append(record)
        }
        return records.sorted {
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
    }

    private static func eligibleMiddleSchool(_ definition: Definition, gradeYear: Int) -> Bool {
        guard definition.middleSchoolEligible else { return false }
        switch definition.key {
        case "algebra1": return (6...8).contains(gradeYear)
        case "geometry": return (7...8).contains(gradeYear)
        case "algebra2", "health", "ipc": return gradeYear == 8
        default: return definition.subject == .worldLanguage && gradeYear == 8
        }
    }

    private static func mayRecoverFall(_ candidate: Candidate, fallScore: Double, allCandidates: [Candidate]) -> Bool {
        let spring = allCandidates.filter {
            $0.course.academicYear == candidate.course.academicYear && $0.semester == .sm2
                && $0.definition?.key == candidate.definition?.key
        }
        let values = Set(spring.compactMap { AcademicScoreValue.finiteDouble($0.grade) })
        guard values.count == 1, let score = values.first, score >= 70 else { return false }
        return (fallScore + score) / 2 >= 70
    }

    private static func semesterCompleted(year: String, semester: TermLabel, asOf: Date) -> Bool {
        guard let start = AcademicYearKey.startYear(year) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let current = calendar.component(.year, from: asOf) - (calendar.component(.month, from: asOf) < 8 ? 1 : 0)
        if start < current { return true }
        if start > current { return false }
        let term = AcademicCalendar.currentTerm(for: asOf)
        return semester == .sm1 ? [.sm1, .q3, .q4, .sm2].contains(term) : term == .sm2
    }

    private static func nonempty(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// Mechanical typography/rigor normalization for bounded aliases. There is
    /// deliberately no substring match on “history”, “art”, or “science”.
    static func normalize(_ name: String) -> String {
        let words = name.lowercased().replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "pre-ap", with: "honors").replacingOccurrences(of: "pre ap", with: "honors")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let numbers = ["i": "1", "ii": "2", "iii": "3", "iv": "4", "v": "5", "vi": "6"]
        return words.filter { !["honors", "honor", "h", "advanced", "preap"].contains($0) }
            .map { numbers[$0] ?? $0 }.joined(separator: " ")
    }

    static func equivalenceKey(for name: String) -> String {
        definition(for: name)?.key ?? normalize(name)
    }

    private static func definition(for name: String) -> Definition? {
        // Catalog display titles can include a trailing department code and
        // short-name annotation. Remove that bounded suffix, then still require
        // the entire remaining title to match a catalog course or roster alias.
        let titleName = name.replacingOccurrences(
            of: #"(?i)\s*(?:[-–—:]|\s)\s*(?:LA|MA|SC|SS|FL|VA|PA|TC|AT|PE)\s*\d{3}[A-Z]*(?:/[A-Z]+)?\*?(?:\s*\([^)]*\))?\s*$"#,
            with: "", options: .regularExpression)
        let normalized = normalize(titleName)
        if let exact = definitions[normalized] { return exact }
        // Athletics titles vary by gender, team and grade. Strip only bounded
        // roster qualifiers, then require a complete known PE title. A phrase
        // merely containing a sport (for example Football History) cannot match.
        let qualifiers: Set<String> = ["boys", "girls", "boy", "girl", "and", "varsity", "junior", "jv",
            "freshman", "freshmen", "grade", "9th", "10th", "11th", "12th", "9", "10", "11", "12",
            "1", "2", "3", "4", "athletic", "athletics", "ath"]
        let words = normalized.split(separator: " ").map(String.init)
        let title = words.filter { !qualifiers.contains($0) }.joined(separator: " ")
        if title.isEmpty, words.contains(where: { ["athletic", "athletics", "ath"].contains($0) }) {
            return definitions["athletics"]
        }
        guard let athletics = definitions[title], athletics.subject == .physicalEducation else { return nil }
        return athletics
    }

    private static let definitions: [String: Definition] = {
        var result: [String: Definition] = [:]
        func add(_ key: String, _ subject: CoursePlanSubject, _ names: [String], credits: Double = 1,
                 semesterOnly: Bool = false, middle: Bool = false, repeatable: Bool = false) {
            let definition = Definition(key: key, subject: subject, credits: credits, semesterOnly: semesterOnly,
                middleSchoolEligible: middle, repeatable: repeatable)
            for name in names {
                result[normalize(name)] = definition
                result[normalize("AP " + name)] = definition
                result[normalize(name + " AP")] = definition
            }
        }
        // Primary district catalog: la/courses, math, science/science-courses,
        // science/electives and social-studies/social-studies-courses.
        add("english1", .english, ["English I", "English 1", "ENG1"])
        add("english2", .english, ["English II", "English 2", "ENG2"])
        add("english3", .english, ["English III", "English 3", "English Language and Composition", "English Language 3", "English 3 Language and Composition", "Language and Composition", "Language and Composition English III", "AP Language and Composition (AP English III)", "ENG3", "APENG3", "APENGLAN"])
        add("english4", .english, ["English IV", "English 4", "English Literature and Composition", "English 4 Literature and Composition", "English Literature and Composition English IV", "AP English Literature and Composition (AP English IV)", "ENG4", "APENG4", "APENGLIT"])
        add("algebra1", .math, ["Algebra I", "Algebra 1", "ALG1", "ALG1H", "ALG I", "ALG 1"], middle: true)
        add("geometry", .math, ["Geometry", "GEOM", "GEOMH", "GEOMP", "GEO"], middle: true)
        add("algebra2", .math, ["Algebra II", "Algebra 2", "ALG2", "ALG2H", "ALG II", "ALG 2"], middle: true)
        add("mathmodels", .math, ["Mathematical Models with Applications", "Math Models with Applications", "MTHMOD"])
        add("precalculus", .math, ["Precalculus", "Pre Calculus", "PRECALC"])
        add("statistics", .math, ["Statistics", "STATS", "UT OnRamps Statistics"])
        add("apstatistics", .math, ["AP Statistics", "APSTATS"])
        add("statistics2", .math, ["Stats 2: Beyond AP Statistics", "Statistics 2", "Statistics 2 Beyond Statistics", "Statistics 2 Beyond AP Statistics"])
        add("calculus", .math, ["Calculus"])
        add("calculusab", .math, ["Calculus AB", "APCALCAB"])
        add("calculusbc", .math, ["Calculus BC", "APCALCBC"])
        add("multivariable", .math, ["Multivariable Calculus", "MUTLCAL"], credits: 1, semesterOnly: true)
        add("linearalgebra", .math, ["Linear Algebra", "LINALG"], credits: 0.5, semesterOnly: true)
        add("biology", .science, ["Biology", "Biology I", "BIO"])
        add("biology2", .science, ["Biology 2", "Biology II", "APBIO2", "AP Biology", "AP BIO"])
        add("chemistry", .science, ["Chemistry", "Chemistry I", "CHEM"])
        add("chemistry2", .science, ["Chemistry 2", "Chemistry II", "APCHEM2", "AP Chemistry", "AP CHEM"])
        add("physics", .science, ["Physics", "PHYS"])
        add("physics1", .science, ["Physics 1", "Physics I", "APPHYS1"])
        add("physics2", .science, ["Physics 2", "Physics II", "APPHYS2"])
        add("physics12", .science, ["Physics 1&2", "Physics I & 2", "Physics 1 and 2"], credits: 2)
        add("physicsc", .science, ["Physics C", "APPHYSC"], credits: 2)
        add("ipc", .science, ["IPC", "Integrated Physics and Chemistry"])
        add("environmentalsystems", .science, ["Environmental Systems"])
        add("environmentalscience", .science, ["Environmental Science", "APENVIR"])
        add("earthspace", .science, ["Earth and Space Science", "Earth Systems Science"])
        add("astronomy", .science, ["Astronomy"])
        add("organicchemistry", .science, ["Organic Chemistry"])
        add("anatomy", .science, ["Anatomy & Physiology", "Anatomy and Physiology"])
        add("biotechnology", .science, ["Biotechnology"])
        add("robotics3", .science, ["Robotics III", "Robotics 3"])
        add("engineering", .science, ["Engineering"])
        add("worldgeography", .socialStudies, ["World Geography", "Human Geography", "WHGEO", "APHUMGEO"])
        add("worldhistory", .socialStudies, ["World History", "World History Modern", "WHIST", "APWHIST"])
        add("ushistory", .socialStudies, ["United States History", "U.S. History", "US History", "APUSH", "APUSHIST"])
        add("government", .socialStudies, ["United States Government", "U.S. Government", "US Government", "Government", "US Government and Politics", "U.S. Government and Politics", "GOVT", "APUSGOVT"], credits: 0.5, semesterOnly: true)
        add("economics", .socialStudies, ["Economics", "ECO FE"], credits: 0.5, semesterOnly: true)
        add("macro", .socialStudies, ["Macroeconomics", "APMACECO"], credits: 0.5, semesterOnly: true)
        add("micro", .socialStudies, ["Microeconomics", "APMICECO"], credits: 0.5, semesterOnly: true)
        add("financialliteracy", .socialStudies, ["Personal Financial Literacy"], credits: 0.5, semesterOnly: true)
        // Fine-arts placement has precedence because every entry is exact.
        add("arthistory", .fineArts, ["Art History", "APHISART"])
        add("artmethods", .fineArts, ["Art Historical Methods", "Art Historical Methods 1", "HUMANIT2"])
        add("artmethods2", .fineArts, ["Art Historical Methods II", "Art Historical Methods 2", "RESHUM"])
        for level in 1...4 { add("art\(level)", .fineArts, ["Art \(level)"], repeatable: false) }
        for name in ["Band", "Choir", "Orchestra", "Jazz Band", "Dance", "Color Guard", "Theatre Arts", "Technical Theatre"] {
            add(normalize(name), .fineArts, [name], repeatable: true)
            for level in 1...4 { add("\(normalize(name))\(level)", .fineArts, ["\(name) \(level)"], repeatable: true) }
        }
        add("musictheory", .fineArts, ["Music Theory"])
        add("guitar", .fineArts, ["Beginning Guitar", "MUS1GTR"])
        add("appliedmusic", .fineArts, ["Applied Music", "MUS1APL", "MUS2APL"], repeatable: true)
        // A posted MS Course 8 is the Level-I transcript grade; Course 7 alone
        // is not a high-school credit. Never count both as separate credits.
        let languageCodes: [String: [String]] = ["Spanish": ["SPAN", "SPN"], "French": ["FREN", "FRN"],
            "Latin": ["LAT"], "Chinese": ["CHIN"], "American Sign Language": ["ASL"], "ASL": ["ASL"]]
        for language in ["Spanish", "French", "Latin", "Chinese", "American Sign Language", "ASL"] {
            for level in 1...6 {
                let keyLanguage = language == "ASL" ? "American Sign Language" : language
                var aliases = ["\(language) \(level)", "\(language) Level \(level)"]
                for code in languageCodes[language, default: []] { aliases += ["\(code)\(level)", "\(code)\(level)H", "\(code) \(level)"] }
                if level == 1 && ["Spanish", "French", "Latin"].contains(language) { aliases.append("\(language) 8") }
                add("\(normalize(keyLanguage))\(level)", .worldLanguage, aliases, middle: level == 1)
            }
            add("\(normalize(language))7", .worldLanguage, ["\(language) 7"], credits: 0)
        }
        add("health", .health, ["Health", "Health 1", "Health1", "Health Education", "Health Ed", "HLTH ED", "HLTH", "HLTH1", "PE800", "Health Education - PE800 (HLTH ED)"], credits: 0.5, semesterOnly: true, middle: true)
        add("healthscience", .health, ["Principles of Health Science", "PRINHLSC", "TC770"])
        add("outdooreducation", .physicalEducation, ["Outdoor Education", "Lifetime Recreation and Outdoor Pursuits", "PE802"], credits: 0.5, semesterOnly: true, repeatable: true)
        for name in ["Physical Education", "PE", "Personal Fitness", "Team Sports", "PE Personal Fitness and Team Sports", "Skill Based Lifetime Activities", "Lifetime Fitness and Wellness Pursuits", "PE Yoga", "Yoga"] {
            add(normalize(name), .physicalEducation, [name], repeatable: true)
        }

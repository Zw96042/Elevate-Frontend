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


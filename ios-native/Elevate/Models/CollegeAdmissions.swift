import Foundation

/// Each published figure keeps its own cohort and population. An institution's
/// test-score sample need not match its admission or enrollment population.
struct CollegeAdmissionsRange: Codable, Hashable {
    var lower: Double
    var upper: Double
    var population: String
    var cohort: String
    var sourceURL: URL
    func isValid(in bounds: ClosedRange<Double>) -> Bool {
        lower.isFinite && upper.isFinite && bounds.contains(lower) && bounds.contains(upper) && lower <= upper
    }
}

struct CollegeSATSectionRange: Codable, Hashable {
    var section: String
    var lower: Double
    var upper: Double
    var population: String
    var cohort: String
    var sourceURL: URL
    var isValid: Bool { !section.isEmpty && lower.isFinite && upper.isFinite && (200...800).contains(lower) && (200...800).contains(upper) && lower <= upper }
}

struct CollegeTestMean: Codable, Hashable {
    var test: String
    var value: Double
    var population: String
    var cohort: String
    var sourceURL: URL
    var isValid: Bool {
        value.isFinite && (test == "SAT" ? (400...1600).contains(value) : test == "ACT" && (1...36).contains(value))
    }
}

struct CollegeAcceptance: Codable, Hashable {
    var applicants: Int? = nil
    var admitted: Int? = nil
    var ratePercent: Double? = nil
    var isApproximate = false
    var population: String
    var cohort: String
    var sourceURL: URL

    var isValid: Bool {
        guard applicants.map({ $0 > 0 }) ?? true, admitted.map({ $0 >= 0 }) ?? true,
              ratePercent.map({ $0.isFinite && (0...100).contains($0) }) ?? true else { return false }
        if let applicants, let admitted, admitted > applicants { return false }
        return ratePercent != nil || (applicants != nil && admitted != nil)
    }
    /// Approximate/lower-bound counts do not establish a precise admission rate.
    var resolvedRatePercent: Double? {
        guard isValid else { return nil }
        if let ratePercent { return ratePercent }
        guard !isApproximate, let applicants, let admitted else { return nil }
        return Double(admitted) / Double(applicants) * 100
    }

    private enum CodingKeys: String, CodingKey { case applicants, admitted, ratePercent, isApproximate, population, cohort, sourceURL }
    init(applicants: Int? = nil, admitted: Int? = nil, ratePercent: Double? = nil, isApproximate: Bool = false,
         population: String, cohort: String, sourceURL: URL) {
        self.applicants = applicants; self.admitted = admitted; self.ratePercent = ratePercent
        self.isApproximate = isApproximate; self.population = population; self.cohort = cohort; self.sourceURL = sourceURL
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        applicants = try c.decodeIfPresent(Int.self, forKey: .applicants)
        admitted = try c.decodeIfPresent(Int.self, forKey: .admitted)
        ratePercent = try c.decodeIfPresent(Double.self, forKey: .ratePercent)
        isApproximate = try c.decodeIfPresent(Bool.self, forKey: .isApproximate) ?? false
        population = try c.decode(String.self, forKey: .population)
        cohort = try c.decode(String.self, forKey: .cohort)
        sourceURL = try c.decode(URL.self, forKey: .sourceURL)
        guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid published admission figures.")) }
    }
}

struct CollegeEnrollment: Codable, Hashable {
    var count: Int
    var population: String
    var cohort: String
    var sourceURL: URL
}

enum CollegePreparationKind: String, Codable, Hashable { case required, recommended }
enum CollegePreparationComparisonScope: String, Codable, Hashable { case seniorEnglish }

struct CollegePreparationRequirement: Codable, Hashable {
    var subject: String
    var units: Double
    var kind: CollegePreparationKind
    var note: String
    var sourceURL: URL
    var comparisonScope: CollegePreparationComparisonScope? = nil
}

struct CollegeGPAPolicyFact: Codable, Hashable {
    var text: String
    var sourceURL: URL
}

struct CollegeAdmissionsDetails: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var isNew = false
    var searchAliases: [String] = []
    var location: String? = nil
    var locationSourceURL: URL? = nil
    var admissionsURL: URL? = nil
    var sourceURL: URL
    var cohort: String
    var population: String
    var checkedOn: String
    var preparation: [CollegePreparationRequirement] = []
    var gpaPolicyFacts: [CollegeGPAPolicyFact] = []
    var satRange: CollegeAdmissionsRange? = nil
    var actRange: CollegeAdmissionsRange? = nil
    var satSections: [CollegeSATSectionRange] = []
    var testMeans: [CollegeTestMean] = []
    var acceptance: CollegeAcceptance? = nil
    var enrollment: CollegeEnrollment? = nil
    var publicationNote: String? = nil
    var preparationScope: String? = nil

    var isValid: Bool {
        !id.isEmpty && !name.isEmpty && (satRange?.isValid(in: 400...1600) ?? true)
            && (actRange?.isValid(in: 1...36) ?? true) && satSections.allSatisfy(\.isValid)
            && testMeans.allSatisfy(\.isValid) && (acceptance?.isValid ?? true)
            && (enrollment.map { $0.count >= 0 } ?? true)
            && preparation.allSatisfy { !$0.subject.isEmpty && $0.units.isFinite && $0.units > 0 && $0.units <= 10 }
    }
}

enum CollegeAdmissionsCatalog {
    private struct Resource: Decodable { var checkedOn: String; var profiles: [CollegeAdmissionsDetails] }
    static let profiles: [CollegeAdmissionsDetails] = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "CollegeAdmissions", withExtension: "json"),
              let data = try? Data(contentsOf: url), let resource = try? JSONDecoder().decode(Resource.self, from: data),
              resource.profiles.allSatisfy(\.isValid), Set(resource.profiles.map(\.id)).count == resource.profiles.count else { return [] }
        return resource.profiles
    }()
    private static let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    static func details(for id: String) -> CollegeAdmissionsDetails? { byID[id] }
    static var additions: [CollegeProfile] {
        profiles.filter(\.isNew).map {
            CollegeProfile(id: $0.id, name: $0.name, cohort: $0.cohort, population: .admissionsGuidance, method: .reported4Point,
                sourceURL: $0.sourceURL, verifiedOn: $0.checkedOn, searchAliases: $0.searchAliases,
                publishedSummary: $0.gpaPolicyFacts.first?.text,
                publicationNote: $0.publicationNote ?? "Published admissions guidance; no verified GPA distribution or complete recalculation formula is available.",
                publishedGPAScale: .unspecified)
        }
    }
}

struct CollegePreparationRow: Identifiable {
    var id: String
    var subject: String
    var units: Double
    var kind: CollegePreparationKind
    var earned: Double?
    var current: Double?
    var remaining: Double?
    var availabilityReason: String?
    var note: String
    var sourceURL: URL
}

/// Local high-school credit context only. College course eligibility, lab
/// experiences, sequence rules and language substitutions are not established.
enum CollegePreparationContext {
    static func rows(details: CollegeAdmissionsDetails, courses: [UnifiedCourseData],
                     creditOverrides: [TranscriptCreditOverride] = [], asOf: Date = Date()) -> [CollegePreparationRow] {
        let transcript = TranscriptCreditCalculator.calculate(courses: courses, overrides: creditOverrides, asOf: asOf)
        let current = TranscriptCreditCalculator.currentCourses(courses: courses, earned: transcript, asOf: asOf)
        let highSchoolRecords = transcript.records.filter { ($0.gradeYear ?? 0) >= 9 && ($0.gradeYear ?? 0) <= 12 }
        let hasTranscript = !transcript.usedLegacyFallback || !transcript.records.isEmpty
        let highSchoolCurrent = current.filter {
            let grade = $0.course.currentAcademicYearIsVerified == true ? $0.course.gradeYear : $0.course.currentEnrollmentGradeYear
            return grade.map { (9...12).contains($0) } ?? false
        }
        let subjects: [String: CoursePlanSubject] = ["English": .english, "Mathematics": .math,
            "Science": .science, "Social studies": .socialStudies, "Fine arts": .fineArts]
        return details.preparation.enumerated().map { index, requirement in
            var row = CollegePreparationRow(id: "\(details.id)|\(index)", subject: requirement.subject, units: requirement.units,
                kind: requirement.kind, earned: nil, current: nil, remaining: nil, availabilityReason: nil,
                note: requirement.note, sourceURL: requirement.sourceURL)
            if requirement.comparisonScope == .seniorEnglish {
                row.availabilityReason = "Senior/Grade 12 equivalent English needs individual course review; earlier English credits do not establish this prerequisite."
                return row
            }
            guard let subject = subjects[requirement.subject] else {
                switch requirement.subject {
                case "Laboratory science": row.availabilityReason = "Lab-course eligibility and lab experiences are not verified; general science credits are not a lab-science total."
                case "World language": row.availabilityReason = "Credits in the same language, accepted course levels and substitutions need individual review; pooled language credits do not establish this requirement."
                default: row.availabilityReason = "College-approved academic electives are not verified; general elective credits are not comparable."
                }
                return row
            }
            guard !courses.isEmpty else {
                row.availabilityReason = "Load school courses to see completed and expected high-school credits."
                return row
            }
            row.earned = hasTranscript ? highSchoolRecords.filter { $0.subject == subject }.reduce(0) { $0 + $1.credits } : nil
            row.current = highSchoolCurrent.filter { $0.subject == subject && $0.status == .expected }.reduce(0) { $0 + $1.credits }
            let needsReview = transcript.records.contains {
                $0.status == .needsReview && ($0.gradeYear.map { (9...12).contains($0) } ?? true)
            }
                || current.contains { $0.status == .needsReview }
            if let earned = row.earned, !needsReview {
                row.remaining = max(0, requirement.units - earned - (row.current ?? 0))
            }
            if !hasTranscript { row.availabilityReason = "Completed semester records are unavailable; current credits assume passing completion." }
            else if needsReview { row.availabilityReason = "Some school courses need classification or credit review; the remaining amount is unavailable." }
            else { row.availabilityReason = "Local credit estimate. College course eligibility and required sequences still need review; current credits assume passing completion." }
            return row
        }
    }
}

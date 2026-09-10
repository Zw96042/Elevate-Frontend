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


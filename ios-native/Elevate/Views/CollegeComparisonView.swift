import SwiftUI

fileprivate extension CollegeProfilePopulation {
    /// Who a published share or range describes, in full.
    var classDescription: String {
        switch self {
        case .admitted: return "admitted first-year students"
        case .enrolled: return "enrolled first-year students who reported a GPA"
        case .publishedProfile: return "students in the published class profile"
        case .admissionsGuidance: return "students described by this guidance"
        }
    }
}

extension CollegeProfile {
    /// "Fall 2025, admitted first-year students", or the publication alone
    /// where it names no population.
    fileprivate var cohortDescription: String {
        switch population {
        case .admitted, .enrolled: return "\(cohort), \(population.sentenceDescription)"
        case .publishedProfile, .admissionsGuidance: return cohort
        }
    }

    /// The sourced admissions metadata for this college, where verified.
    fileprivate var admissions: CollegeAdmissionsDetails? {
        CollegeAdmissionsCatalog.details(for: id)
    }

    /// Published GPA figures on a high-school admissions scale. Anything
    /// above 5.0 is some other scale, such as a university's own grading,
    /// and is never shown as an admissions figure.
    fileprivate var showsGPAFigures: Bool {
        guard hasPublishedStatistics else { return false }
        if let quartiles, !(quartiles.upper <= 5) { return false }
        if let reportedMean, !(reportedMean <= 5) { return false }
        return bands.allSatisfy { $0.minimum <= 5 }
    }

    /// The one published figure a list row leads with: the GPA middle 50%,
    /// the GPA average, or the SAT middle 50% where no GPA was published.
    fileprivate func headlineFigure(_ details: CollegeAdmissionsDetails?) -> (label: String, value: String)? {
        if showsGPAFigures, let quartiles {
            return ("GPA middle 50%", CollegeFormat.gpaRange(quartiles))
        }
        if showsGPAFigures, let reportedMean { return ("GPA average", Self.mean(reportedMean)) }
        if let sat = details?.satRange { return ("SAT middle 50%", CollegeFormat.range(sat.lower, sat.upper)) }
        if let act = details?.actRange { return ("ACT middle 50%", CollegeFormat.range(act.lower, act.upper)) }
        return nil
    }

    /// What the college published and on which scale, for a list row with
    /// no location or admission figures.
    fileprivate var rowDescription: String {
        if showsGPAFigures { return "\(publishedGPAScale.title), \(cohort)" }
        if publishedSummary != nil {
            return population == .admissionsGuidance ? "Admissions guidance" : "Published admissions profile"
        }
        return "No verified GPA figures here"
    }

    /// Whether the student's estimate can sit beside the published figures:
    /// only a published calculation, against figures on the same kind of
    /// scale. Unspecified figures are never compared.
    fileprivate var comparesWithEstimate: Bool {
        guard method.hasPublishedCalculation, showsGPAFigures else { return false }
        if publishedGPAScale == .weighted { return !method.isUnweighted }
        if publishedGPAScale == .unweighted { return method.isUnweighted }
        return false
    }

    /// Whether Elevate's 4.0 reference can sit beside the published figures:
    /// only where no college method is known and the figures are published
    /// as unweighted. It's placed in a range, never given a rank.
    fileprivate var comparesWithReference: Bool {
        !method.hasPublishedCalculation && showsGPAFigures && publishedGPAScale == .unweighted
    }

    /// How a published method reads GPA, in one line under the estimate.
    fileprivate var methodSummary: String? {
        switch method {
        case .ucFullyWeighted: return "Grades 10–11. Out-of-state AP/IB +1 at C or better."
        case .ucUnweighted: return "Grades 10–11. No honors bonus."
        case .ugaWeighted: return "Academic core. AP/IB +1."
        case .ufWeighted: return "Academic core. AP/IB/AICE and core dual enrollment +1, Honors +0.5."
        case .fsuWeighted: return "Academic core. AP/IB/AICE and dual enrollment +1, Honors +0.5, at C or better."
        case .ucfWeighted: return "Academic core. AP/IB/AICE and dual enrollment +1, Honors +0.5."
        case .reported4Point: return nil
        }
    }

    /// "weighted GPA", "unweighted GPA" or "reported GPA", mid-sentence.
    fileprivate var publishedScaleInSentence: String {
        if publishedGPAScale == .weighted { return "weighted GPA" }
        if publishedGPAScale == .unweighted { return "unweighted GPA" }
        return "reported GPA"
    }

    fileprivate static func mean(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2...3)))
    }
}

fileprivate enum CollegeFormat {
    static func truncatedGPA(_ value: Double) -> String {
        truncatedGPA(value, places: 2)
    }

    private static func truncatedGPA(_ value: Double, places: Int) -> String {
        var decimal = Decimal(value)
        var truncated = Decimal()
        NSDecimalRound(&truncated, &decimal, places, .down)
        return String(format: "%.*f", places, NSDecimalNumber(decimal: truncated).doubleValue)
    }

    /// Keep the displayed number consistent with the full-value comparison.
    /// Extra digits are needed only when truncation lands on a range boundary.
    static func comparisonGPA(_ value: Double, display: String, quartiles: CollegeGPAQuartiles?,
                              maximum: Double, position: CollegeRangePosition?) -> String {
        guard let quartiles, let position, let displayedValue = Double(display),
              CollegeRangePosition(displayedValue, in: quartiles, maximum: maximum) != position else { return display }
        for places in 3...6 {
            let precise = truncatedGPA(value, places: places)
            if let displayedValue = Double(precise),
               CollegeRangePosition(displayedValue, in: quartiles, maximum: maximum) == position {
                return precise
            }
        }
        // Extremely close boundaries still need an accurate visible value.
        return String(value)
    }

    /// "1340–1500", "30–34".
    static func range(_ lower: Double, _ upper: Double) -> String {
        "\(GradeFormat.upToTwoDecimals(lower))–\(GradeFormat.upToTwoDecimals(upper))"
    }

    /// "3.58–3.95".
    static func gpaRange(_ quartiles: CollegeGPAQuartiles) -> String {
        "\(GradeFormat.gpa(quartiles.lower))–\(GradeFormat.gpa(quartiles.upper))"
    }

    /// "42%", "3.9%".
    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    /// Credit units: "4", "0.5".
    static func units(_ value: Double) -> String {
        GradeFormat.upToTwoDecimals(value)
    }

    /// "Admitted first-year students" read mid-sentence. Acronyms and
    /// names keep their capitals.
    static func midSentence(_ text: String) -> String {
        let characters = Array(text)
        guard characters.count > 1, characters[0].isUppercase, characters[1].isLowercase else { return text }
        return characters[0].lowercased() + String(characters.dropFirst())
    }

    /// "Fall 2025, admitted first-year students".
    static func provenance(cohort: String, population: String) -> String {
        "\(cohort), \(midSentence(population))"
    }

    /// "October 4, 2026".
    static func day(_ iso: String) -> String {
        guard let parts = AttendanceSchoolDate.components(iso),
              let date = Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month,
                                                                    day: parts.day, hour: 12)) else { return iso }
        return date.formatted(.dateTime.month(.wide).day().year())
    }
}

/// Where a GPA sits against a published middle 50%. Only ever computed for
/// figures on the same verified scale; it's a position, not a percentile.
fileprivate enum CollegeRangePosition: Equatable {
    case below, inside, above

    init?(_ value: Double, in quartiles: CollegeGPAQuartiles, maximum: Double) {
        guard value.isFinite, quartiles.lower.isFinite, quartiles.upper.isFinite, quartiles.lower >= 0,
              quartiles.lower <= quartiles.upper, quartiles.upper <= maximum else { return nil }
        if value < quartiles.lower { self = .below }
        else if value > quartiles.upper { self = .above }
        else { self = .inside }
    }


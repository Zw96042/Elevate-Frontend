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


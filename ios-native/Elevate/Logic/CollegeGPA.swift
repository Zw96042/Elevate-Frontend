import Foundation

struct CollegeGPAResult {
    var profile: CollegeProfile
    var records: [GPAConversionRecord]
    var skipped: [GPAConversionSkippedRecord]
    var calculationNotes: [String] = []
    /// Retained for explanation, never silently included as academic core.
    var omittedRecords: [GPAConversionRecord] = []
    var unavailableReason: String? = nil
    var value: Double? {
        guard unavailableReason == nil, !records.isEmpty else { return nil }
        return records.map(\.points).reduce(0, +) / Double(records.count)
    }
    var standing: CollegeGPAStanding? { value.flatMap { CollegeGPAStanding.compare($0, profile: profile) } }
    /// A weighted result must never be described as a perfect unweighted GPA
    /// without separately checking its underlying completed semester grades.
    var unweightedValue: Double? {
        guard unavailableReason == nil, !records.isEmpty else { return nil }
        let points = records.compactMap { GPAConversionPolicy.unweighted4Point.points(for: $0.percentage, level: .regular) }
        guard points.count == records.count else { return nil }
        return points.reduce(0, +) / Double(points.count)
    }
    /// Never display 3.999 as 4.00 beside a different GPA band.
    var displayValue: String {
        guard let value else { return "—" }
        var decimal = Decimal(value)
        var truncated = Decimal()
        NSDecimalRound(&truncated, &decimal, 2, .down)
        return String(format: "%.2f", NSDecimalNumber(decimal: truncated).doubleValue)
    }
}

struct CollegeGPAStanding: Equatable {
    var title: String
    var detail: String
    var bandLabel: String? = nil
    /// Legacy UI compatibility. A cohort histogram cannot establish a student's rank.
    var higherBandPercent: Double? { nil }
    /// The share of the published reporting cohort in one band, not a percentile.
    var sameBandPercent: Double? = nil
    var cohortContext: String? = nil

    static func compare(_ value: Double, profile: CollegeProfile) -> Self? {
        guard value.isFinite, value >= 0, value <= profile.method.maximum else { return nil }
        let weighted = !profile.method.isUnweighted
        let perfectUnweighted = !weighted && value == 4
        var standing = Self(
            title: perfectUnweighted ? "Highest possible unweighted GPA" : weighted ? (profile.method == .ucFullyWeighted ? "Your fully weighted GPA" : "Your weighted GPA") : "Your unweighted GPA",
            detail: perfectUnweighted
                ? "All A grades in the completed semesters used for this estimate. A 4.0 is the highest possible GPA on this unweighted scale. Course selection and college policies may differ."
                : weighted
                    ? "Your estimate includes the published course-level bonuses. Its weighted value does not establish your unweighted GPA. Course eligibility and college policies may differ."
                    : "Your estimate is on a 4.0 unweighted scale. Course selection and college policies may differ.")
        // A published weighted cohort cannot be compared to a generic unweighted
        // conversion, even when a few of its values happen to fall below 4.0.
        guard !(profile.publishedGPAScale == .weighted && !weighted),
              !(profile.publishedGPAScale == .unweighted && weighted) else { return standing }
        guard profile.reportedMean.map({ $0.isFinite && (0...profile.method.maximum).contains($0) }) ?? true,
              profile.reportingPercent.map({ $0.isFinite && (0...100).contains($0) }) ?? true else { return standing }
        if let quartiles = profile.quartiles {
            guard quartiles.lower.isFinite, quartiles.upper.isFinite,
                  quartiles.lower >= 0, quartiles.lower <= quartiles.upper,
                  quartiles.upper <= profile.method.maximum,
                  quartiles.median.map({ $0.isFinite && (quartiles.lower...quartiles.upper).contains($0) }) ?? true else { return standing }
            standing.cohortContext = "\(profile.cohort), \(profile.population.sentenceDescription): the published middle 50% was \(String(format: "%.2f", quartiles.lower))–\(String(format: "%.2f", quartiles.upper)). This describes a past class, not your individual percentile or admission chances."
            return standing
        }
        guard !profile.bands.isEmpty,
              profile.bands.allSatisfy({ $0.percent.isFinite && (0...100).contains($0.percent) && $0.minimum.isFinite
                  && (0...profile.method.maximum).contains($0.minimum)
                  && ($0.maximum == nil ? $0.minimum == profile.method.maximum : ($0.maximum!.isFinite && $0.maximum! > $0.minimum && $0.maximum! <= profile.method.maximum)) }),
              abs(profile.bands.map(\.percent).reduce(0, +) - 100) <= 0.05,
              profile.bands.filter({ $0.contains(value) }).count == 1,
              let band = profile.bands.first(where: { $0.contains(value) }) else { return standing }
        let share = percent(band.percent)
        standing.bandLabel = band.label
        standing.sameBandPercent = band.percent
        standing.cohortContext = "\(share)% of \(profile.cohort) \(profile.population.sentenceDescription) were in the published \(band.label) GPA band. This is the share of that reporting cohort, not your individual percentile. Reported course selection, credits and weighting may differ from this estimate."
        return standing
    }
    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

enum CollegeGPACalculator {
    static func calculate(profile: CollegeProfile, courses: [UnifiedCourseData],
                          manualClassesByYear: [Int: [ManualClass]] = [:], asOf: Date = Date()) -> CollegeGPAResult {
        let report = GPAConversionCalculator.calculate(courses: courses, manualClassesByYear: manualClassesByYear,
            gradeYears: profile.method.gradeYears, policy: .unweighted4Point, completedOnly: true, asOf: asOf)
        if profile.method.usesAcademicCore {
            return academicCoreResult(profile: profile, report: report)
        }
        let isUC = profile.method == .ucFullyWeighted || profile.method == .ucUnweighted
        var result = CollegeGPAResult(profile: profile, records: [], skipped: report.skippedRecords)
        for source in report.includedRecords {
            let classification = CollegeCourseClassification(source.courseName)
            if isUC, classification.isKnownNonAcademic {
                result.omittedRecords.append(source)
                continue
            }
            var record = source
            if profile.method == .ucFullyWeighted, record.percentage >= 70, classification.isAPOrIB {
                record.points += 1
            }
            result.records.append(record)
        }
        if isUC {
            result.calculationNotes.append("UC A–G eligibility is unverified for the remaining courses, including arts and electives. Course names and recognized district aliases identify levels approximately; credits and summer placement are unavailable.")
            if !result.omittedRecords.isEmpty {
                let count = result.omittedRecords.count
                result.calculationNotes.append("\(count) completed semester record\(count == 1 ? " is" : "s are") recognized as PE, athletics, health or nonacademic support and omitted from the UC estimate.")
            }
        }
        return result
    }
    /// Local advanced-course exceptions and Honors labels do not establish UC
    /// out-of-state eligibility. Explicit AP/IB names are still an estimate.
    static func isExplicitAPOrIB(_ name: String) -> Bool {
        let level = CollegeCourseClassification(name)
        return level.isAPOrIB
    }


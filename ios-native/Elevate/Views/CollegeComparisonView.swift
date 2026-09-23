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

    var word: String {
        switch self {
        case .below: return "below"
        case .inside: return "inside"
        case .above: return "above"
        }
    }
}

/// The student's GPA as one college can read it: its published method's
/// estimate, or Elevate's 4.0 reference where no method is known.
fileprivate struct CollegePersonalGPA {
    var isReference: Bool
    var value: Double
    var display: String
    var maximum: Double
    var position: CollegeRangePosition?

    static func estimate(_ result: CollegeGPAResult) -> Self? {
        guard let value = result.value else { return nil }
        let profile = result.profile
        let position = profile.comparesWithEstimate
            ? profile.quartiles.flatMap { CollegeRangePosition(value, in: $0, maximum: profile.method.maximum) } : nil
        let display = CollegeFormat.comparisonGPA(value, display: result.displayValue, quartiles: profile.quartiles,
                                                  maximum: profile.method.maximum, position: position)
        return Self(isReference: false, value: value, display: display,
                    maximum: profile.method.maximum, position: position)
    }

    /// Compare the full value; formatting must not move it across a boundary.
    static func reference(_ report: GPAConversionReport, profile: CollegeProfile) -> Self? {
        guard let value = report.value else { return nil }
        let position = profile.comparesWithReference
            ? profile.quartiles.flatMap { CollegeRangePosition(value, in: $0, maximum: 4) } : nil
        let display = CollegeFormat.comparisonGPA(value, display: CollegeFormat.truncatedGPA(value),
                                                  quartiles: profile.quartiles, maximum: 4, position: position)
        return Self(isReference: true, value: value, display: display, maximum: 4, position: position)
    }

    /// "Your generic 4.0 reference 3.86, inside the middle 50%".
    func rowLine(_ profile: CollegeProfile) -> String {
        let title = isReference ? CollegeComparison.referenceTitle : "Your \(profile.method.title)"
        guard let position else { return "\(title) \(display)" }
        return "\(title) \(display), \(position.word) the middle 50%"
    }

    /// The published figures beside this GPA: its position where the scales
    /// match, otherwise the college's numbers and why they aren't compared.
    func comparisonLine(_ profile: CollegeProfile) -> String? {
        guard profile.showsGPAFigures else { return nil }
        if let position, let quartiles = profile.quartiles {
            let scale = profile.publishedGPAScale == .weighted ? "weighted" : "unweighted"
            return "\(position.word.capitalized) its \(scale) middle 50%, \(CollegeFormat.gpaRange(quartiles))."
        }
        let comparable = isReference ? profile.comparesWithReference : profile.comparesWithEstimate
        if let quartiles = profile.quartiles {
            guard !comparable else { return nil }
            let range = CollegeFormat.gpaRange(quartiles)
            switch profile.publishedGPAScale {
            case .unspecified: return "Its published \(range) doesn't state a scale, so it isn't compared."
            case .weighted: return "Its published \(range) is weighted, so it isn't compared."
            case .unweighted: return "Its published \(range) is unweighted, so it isn't compared."
            }
        }
        if let mean = profile.reportedMean {
            let scale = profile.publishedGPAScale == .weighted ? "weighted " : profile.publishedGPAScale == .unweighted ? "unweighted " : ""
            return "Its published \(scale)average is \(CollegeProfile.mean(mean))."
        }
        return nil
    }
}

/// AP and Honors semesters among the included records, by each course's
/// actual level.
fileprivate struct CollegeRigorCount {
    var ap = 0
    var honors = 0

    init(_ records: [GPAConversionRecord]) {
        for record in records {
            switch record.courseLevel {
            case .ap: ap += 1
            case .honors: honors += 1
            case .regular: break
            }
        }
    }

    /// "4 AP, 6 Honors semesters", or nil with neither.
    var text: String? {
        func semesters(_ count: Int) -> String { count == 1 ? "semester" : "semesters" }
        switch (ap, honors) {
        case (0, 0): return nil
        case (_, 0): return "\(ap) AP \(semesters(ap))"
        case (0, _): return "\(honors) Honors \(semesters(honors))"
        default: return "\(ap) AP, \(honors) Honors semesters"
        }
    }
}

/// Subject preparation for a list row, counted only where the remaining
/// amount is known. Unavailable subjects are never treated as unmet.
fileprivate struct CollegePreparationSummary {
    var met: Int
    var known: [CollegePreparationRow]
    var total: Int
    var reliesOnCurrent: Bool

    init?(_ rows: [CollegePreparationRow]) {
        let known = rows.filter { $0.remaining != nil }
        guard !known.isEmpty else { return nil }
        let met = known.filter { ($0.remaining ?? 1) <= 0 }
        self.met = met.count
        self.known = known
        self.total = rows.count
        self.reliesOnCurrent = met.contains { ($0.earned ?? 0) < $0.units }
    }

    /// "Credit targets reached in 3 of 4 checked subjects, if current classes are passed",
    /// or "English credit target reached" for a single checked subject.
    var text: String {
        let current = reliesOnCurrent ? ", if current classes are passed" : ""
        if known.count == 1, let row = known.first {
            return met == 1 ? "\(row.subject) credit target reached\(current)"
                : "\(row.subject): \(CollegeFormat.units(row.remaining ?? 0)) more to reach \(CollegeFormat.units(row.units))"
        }
        let scope = known.count == total ? "subjects" : "checked subjects"
        let count = met == known.count ? "all \(known.count)" : "\(met) of \(known.count)"
        return "Credit targets reached in \(count) \(scope)\(current)"
    }
}

fileprivate extension CollegeGPAResult {
    /// The published band holding this estimate, for its class share. Only
    /// where the published scale matches the estimate's.
    var band: CollegeGPABand? {
        guard profile.comparesWithEstimate, let label = standing?.bandLabel else { return nil }
        return profile.bands.first { $0.label == label }
    }

    /// The college's bonus on one record, beyond its plain 4.0 points.
    func bonus(_ record: GPAConversionRecord) -> Double? {
        guard let base = GPAConversionPolicy.unweighted4Point.points(for: record.percentage, level: .regular),
              record.points > base else { return nil }
        return record.points - base
    }

    /// Exactly the top of an unweighted scale; weighted scales run higher.
    var isAtUnweightedCeiling: Bool {
        guard let value, profile.method.isUnweighted else { return false }
        return value == profile.method.maximum
    }
}

/// Whether completed grades can be estimated. Published figures never wait
/// on this; only each estimate does.
enum CollegeEstimateInput {
    case loading
    case failed(String)
    case unavailable
    case loaded([UnifiedCourseData])

    @MainActor init(_ store: AppStore) {
        if let courses = store.courses { self = .loaded(courses) }
        else if store.coursesLoading { self = .loading }
        else if let error = store.coursesError { self = .failed(error) }
        else { self = .unavailable }
    }

    /// A college-specific estimate, only where the college published how it
    /// calculates GPA. Other colleges get none, never a generic stand-in.
    @MainActor func result(for profile: CollegeProfile) -> CollegeGPAResult? {
        guard profile.method.hasPublishedCalculation, case .loaded(let courses) = self else { return nil }
        return CollegeGPACalculator.calculate(profile: profile, courses: courses,
                                              manualClassesByYear: GPAConversionInputs.manualClassesByYear)
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Elevate's generic 4.0 over every completed semester: the reference
    /// shown where a college publishes no GPA method. Never a college's
    /// calculation.
    @MainActor func reference() -> GPAConversionReport? {
        guard case .loaded(let courses) = self else { return nil }
        return GPAConversionInputs.completedReport(courses: courses, policy: .unweighted4Point)
    }

    /// Completed and current credits against a college's published subject
    /// preparation, or nil until courses load.
    @MainActor func preparation(_ details: CollegeAdmissionsDetails?, creditOverrides: [TranscriptCreditOverride] = []) -> [CollegePreparationRow]? {
        guard case .loaded(let courses) = self, let details, !details.preparation.isEmpty else { return nil }
        return CollegePreparationContext.rows(details: details, courses: courses, creditOverrides: creditOverrides, asOf: Date())
    }
}

fileprivate extension CollegeProfileCatalog {
    /// Profiles by ID; the first wins, as in route resolution.
    static let byID: [String: CollegeProfile] = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
}

/// One college's comparison, shared by its My Colleges row and its profile
/// so the two always say the same thing: which GPA leads, where it sits
/// against the published figures, or why nothing is compared. It only
/// reads the existing estimate, reference and scale guards.
fileprivate struct CollegeComparison {
    enum Lead {
        /// Courses are loading; the row keeps its shape.
        case loading
        /// Grades aren't loaded or failed to load. Published figures still show.
        case gradesMissing
        /// The college's own estimate, or the generic 4.0 reference where it
        /// publishes no method and its figures are unweighted.
        case gpa(CollegePersonalGPA, title: String)
        /// The college's estimate, withheld by the calculator.
        case withheld(title: String)
        /// No completed semesters in the years it reads.
        case notYet(title: String)
        /// No published method, and no figures the reference can sit beside.
        case notCompared
    }

    static let referenceTitle = "Your generic 4.0 reference"

    var lead: Lead
    /// Where the GPA sits against the published figures, or why there's no
    /// GPA to place.
    var standing: String?

    /// Whether the GPA is placed in a published range on the same scale.
    var isPlaced: Bool {
        if case .gpa(let gpa, _) = lead { return gpa.position != nil }
        return false
    }

    /// Whether the standing quotes a published figure, so its cohort and
    /// source go with it.
    var quotesPublishedFigure: Bool {
        if case .gpa = lead { return standing != nil }
        return false
    }

    @MainActor init(profile: CollegeProfile, input: CollegeEstimateInput) {
        self.init(profile: profile, input: input, result: input.result(for: profile),
                  reference: profile.comparesWithReference ? input.reference() : nil)
    }

    @MainActor init(profile: CollegeProfile, input: CollegeEstimateInput,
                    result: CollegeGPAResult?, reference: GPAConversionReport?) {
        let hasMethod = profile.method.hasPublishedCalculation
        guard hasMethod || profile.comparesWithReference else {
            lead = .notCompared
            standing = Self.notComparedReason(profile)
            return
        }
        switch input {
        case .loading:
            lead = .loading
            standing = nil
        case .failed, .unavailable:
            lead = .gradesMissing
            standing = nil
        case .loaded:
            if hasMethod {
                let title = "Your \(profile.method.title)"
                if let result, let gpa = CollegePersonalGPA.estimate(result) {
                    lead = .gpa(gpa, title: title)
                    standing = gpa.comparisonLine(profile)
                } else if let reason = result?.unavailableReason {
                    lead = .withheld(title: title)
                    standing = reason
                } else {
                    lead = .notYet(title: title)
                    standing = "No completed semesters from \(profile.method.yearsLabel.lowercased()) yet."
                }
            } else if let reference, let gpa = CollegePersonalGPA.reference(reference, profile: profile) {
                lead = .gpa(gpa, title: Self.referenceTitle)
                standing = gpa.comparisonLine(profile)
            } else {
                lead = .notYet(title: Self.referenceTitle)
                standing = "No completed semesters yet."
            }
        }
    }

    /// Why a college without a published method gets no GPA beside it. The
    /// reference is placed only against unweighted figures.
    private static func notComparedReason(_ profile: CollegeProfile) -> String {
        guard profile.showsGPAFigures else { return "No verified GPA formula or class GPA figures here." }
        if profile.publishedGPAScale == .weighted {
            return "Its GPA figures are weighted; no matching formula is verified here."
        }
        return "Its GPA figures don't state a comparable scale."
    }
}

/// A saved college ID, resolved against this version's catalog. Unknown IDs
/// are kept, never dropped, until the student removes them.
fileprivate enum ChosenCollege: Identifiable {
    case profile(CollegeProfile)
    case unavailable(String)

    var id: String {
        switch self {
        case .profile(let profile): return profile.id
        case .unavailable(let id): return id
        }
    }
}

/// The account a picker opened for; it saves only for that account.
fileprivate struct CollegePickerRequest: Identifiable {
    var id: String
}

/// My Colleges: only the colleges the student chose, in the order chosen,
/// each led by their own GPA as that college reads it beside its published
/// figures. Choices are saved per account on this iPhone. Nothing here
/// ranks or predicts admission.
struct CollegeComparisonView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var picker: CollegePickerRequest?
    @State private var resetScope: String?
    @State private var confirmingReset = false

    private var planning: StudentPlanningStore { store.planning }

    /// The signed-in account whose saved colleges are loaded, or nil.
    private var scope: String? {
        guard let scope = store.localAccountScope, planning.accountScope == scope else { return nil }
        return scope
    }

    var body: some View {
        let input = CollegeEstimateInput(store)
        let scope = self.scope
        let chosen: [ChosenCollege] = scope == nil ? [] : planning.selectedCollegeIDs.map { id in
            CollegeProfileCatalog.byID[id].map(ChosenCollege.profile) ?? .unavailable(id)
        }
        let canChoose = scope != nil && !planning.collegeSelectionUnavailable
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if scope == nil {
                    EmptyStateView(
                        title: "Connect Skyward to choose colleges",
                        message: "Your colleges are saved with your account."
                    )
                    .accessibilityIdentifier("colleges.noAccount")
                } else if planning.collegeSelectionUnavailable {
                    recovery
                } else if chosen.isEmpty {
                    emptyState
                } else {
                    selectedList(chosen, input: input)
                }

                VStack(alignment: .leading, spacing: 0) {
                    converterRow
                    InsetDivider()
                    about
                }
                .padding(.top, Metrics.sectionGap)
            }
            .padding(.horizontal, Metrics.page)
            .padding(.bottom, 32)
        }
        .visibleRefreshable { await store.refreshCourses(force: true) }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("My Colleges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canChoose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(chosen.isEmpty ? "Choose" : "Edit") { openPicker() }
                        .accessibilityLabel(chosen.isEmpty ? "Choose colleges" : "Edit My Colleges")
                        .accessibilityIdentifier("colleges.choose")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                CollegeSearchToolbarButton { router.openCollegeSearch() }
            }
        }
        .sheet(item: $picker) { request in
            CollegePickerSheet(originScope: request.id)
        }
        .confirmationDialog("Reset My Colleges?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { resetSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your saved college list on this iPhone. Published profiles and your grades aren't affected.")
        }
        .onChange(of: store.accountRevision) { _, _ in closeAccountScopedUI() }
        .onChange(of: scope) { _, _ in closeAccountScopedUI() }
        .accessibilityIdentifier("collegeProfiles.screen")
    }


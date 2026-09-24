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

    /// Nothing opened for one account stays open for another.
    private func closeAccountScopedUI() {
        picker = nil
        confirmingReset = false
        resetScope = nil
    }

    private func openPicker() {
        guard let scope, !planning.collegeSelectionUnavailable else { return }
        picker = CollegePickerRequest(id: scope)
    }

    private func remove(_ id: String, expectedScope: String?) {
        guard let expectedScope, expectedScope == scope else { return }
        planning.setCollegeSelected(false, collegeID: id, expectedAccountScope: expectedScope)
    }

    private func resetSelection() {
        guard let resetScope, resetScope == scope else { return }
        planning.resetCollegeSelection(expectedAccountScope: resetScope)
        self.resetScope = nil
    }

    // MARK: States

    /// Nothing chosen yet: one sentence on what the page does and one way in.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            EmptyStateView(
                title: "Choose colleges to compare",
                message: "See how your record compares at the colleges you choose."
            )
            .accessibilityIdentifier("colleges.selection.empty")
            Button("Choose Colleges") { openPicker() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("colleges.choose.empty")
        }
    }

    /// A saved list that can't be read is never shown, merged or
    /// overwritten. Only an explicit, confirmed reset removes it.
    private var recovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your saved colleges can't be read")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Elevate isn't showing or changing them. Reset to choose colleges again.")
                .font(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                resetScope = scope
                confirmingReset = resetScope != nil
            } label: {
                Text("Reset My Colleges…")
                    .foregroundStyle(Color.gradeAttention)
            }
            .buttonStyle(ActionTextButtonStyle())
            .accessibilityIdentifier("colleges.selection.reset")
        }
        .frame(maxWidth: 440, alignment: .leading)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("colleges.selection.recovery")
    }

    // MARK: Chosen colleges

    /// The chosen colleges in the order chosen. Freshness and grade states
    /// appear only when a row actually reads the student's grades.
    private func selectedList(_ chosen: [ChosenCollege], input: CollegeEstimateInput) -> some View {
        // A menu can outlive the row that opened it; retain that row's account.
        let expectedScope = scope
        let corrections = planning.accountScope == store.localAccountScope ? planning.coursePlan.creditOverrides : []
        let usesGrades = chosen.contains { entry in
            guard case .profile(let profile) = entry else { return false }
            return profile.method.hasPublishedCalculation || profile.comparesWithReference
                || !(profile.admissions?.preparation.isEmpty ?? true)
        }
        return VStack(alignment: .leading, spacing: 0) {
            if usesGrades {
                StatusStrip(
                    lastUpdated: store.coursesLastUpdated,
                    isRefreshing: store.coursesLoading && store.courses != nil,
                    error: store.courses != nil ? store.coursesError : nil
                ) {
                    await store.refreshCourses(force: true)
                }
                gradesState(input)
                    .padding(.top, 4)
            }

            if planning.collegeSelectionError != nil {
                Text("Couldn't save your colleges. Try again.")
                    .font(.footnote)
                    .foregroundStyle(Color.gradeAttention)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("colleges.selection.error")
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(chosen.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { InsetDivider() }
                    switch entry {
                    case .profile(let profile):
                        CollegeSelectedRow(profile: profile, input: input, creditOverrides: corrections) {
                            remove(profile.id, expectedScope: expectedScope)
                        }
                    case .unavailable(let id):
                        unavailableRow(id, expectedScope: expectedScope)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("colleges.list")

            InsetDivider()
            chooseRow
        }
    }

    /// The page-level grade state, once. Loading shows inside each row.
    @ViewBuilder
    private func gradesState(_ input: CollegeEstimateInput) -> some View {
        switch input {
        case .loading:
            EmptyView()
        case .failed(let error):
            InlineErrorState(title: "Couldn't load courses", message: error) {
                await store.refreshCourses(force: true)
            }
            .padding(.vertical, 8)
            .accessibilityIdentifier("colleges.coursesError")
        case .unavailable:
            EmptyStateView(
                title: "Your grades aren't loaded",
                message: "Published figures are still shown for each college."
            )
            .accessibilityIdentifier("colleges.unavailable")
        case .loaded:
            if input.reference()?.value == nil {
                EmptyStateView(
                    title: "No completed semesters yet",
                    message: "Your GPA appears after a semester ends and its grades are posted."
                )
                .accessibilityIdentifier("colleges.summary.empty")
            }
        }
    }

    /// A saved ID this version's catalog doesn't have. It stays saved until
    /// removed here, for this account only.
    private func unavailableRow(_ id: String, expectedScope: String?) -> some View {
        let text = VStack(alignment: .leading, spacing: 2) {
            Text("Unavailable college")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.muted)
            Text("This saved college isn't available in this version.")
                .font(.footnote)
                .foregroundStyle(Color.muted)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        let button = Button("Remove") { remove(id, expectedScope: expectedScope) }
            .buttonStyle(ActionTextButtonStyle())
            .accessibilityLabel("Remove unavailable college")
            .accessibilityIdentifier("colleges.selected.\(id).remove")
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    text
                    button
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    text
                    button
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("colleges.selected.\(id)")
    }

    private var chooseRow: some View {
        Button { openPicker() } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.themeAccent)
                    .accessibilityHidden(true)
                Text("Add or remove colleges")
                    .font(.body)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("colleges.choose.list")
    }

    private var converterRow: some View {
        NavigationLink(value: CoursesRoute.gpaConverter) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GPA converter")
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    Text("Generic unweighted and weighted, by year")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                RowChevron()
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("colleges.summary.converter")
    }

    /// What the list does and doesn't say, behind one row. Its note keeps
    /// the admissions limit in view.
    private var about: some View {
        GPADisclosure(title: "About these comparisons", note: "Past classes, not chances.",
                      identifier: "colleges.about") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Figures describe a past class, each labeled with its cohort and source. A range isn't a cutoff.")
                Text("A college-specific estimate appears only where the college publishes its GPA method. Elsewhere, Elevate's generic 4.0 reference is placed only against unweighted figures; it's never the college's calculation or an official GPA.")
                Text("Estimates use completed semester grades only. Current classes and What-if changes aren't included.")
                Text("Your colleges are saved with your account on this iPhone.")
            }
            .font(.footnote)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Chosen college row

/// One chosen college, led by the student's own GPA as that college reads
/// it, then where it sits against the published figures and who they
/// describe. Opens the profile; Remove is in the context menu and a
/// VoiceOver action.
private struct CollegeSelectedRow: View {
    var profile: CollegeProfile
    var input: CollegeEstimateInput
    var creditOverrides: [TranscriptCreditOverride]
    var onRemove: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The row's second line: a GPA, why it's missing, or, without grades,
    /// the college's own lead figure.
    private struct LeadFigure {
        var label: String
        var value: String
        var isMuted: Bool
        var spoken: String
    }

    var body: some View {
        let comparison = CollegeComparison(profile: profile, input: input)
        let figure = leadFigure(comparison)
        let cohort = comparison.quotesPublishedFigure ? profile.cohortDescription : nil
        let preparation = input.preparation(profile.admissions, creditOverrides: creditOverrides)
            .flatMap(CollegePreparationSummary.init)?.text
        let isLoading: Bool = { if case .loading = comparison.lead { return true }; return false }()
        let spoken = isLoading ? "Loading your GPA"
            : ([figure?.spoken, comparison.standing, cohort, preparation].compactMap { $0 }).joined(separator: ". ")

        NavigationLink(value: CoursesRoute.collegeProfile(profile.id)) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.ink)
                    if isLoading {
                        SkeletonText(.subheadline, length: 24)
                            .padding(.top, 2)
                        SkeletonText(.footnote, length: 30, tone: .secondary)
                    } else {
                        if let figure { lead(figure) }
                        if let standing = comparison.standing {
                            Text(standing)
                                .font(.footnote)
                                .foregroundStyle(comparison.isPlaced ? Color.ink : Color.muted)
                        }
                        if let cohort {
                            Text(cohort)
                                .font(.footnote)
                                .foregroundStyle(Color.muted)
                        }
                    }
                    if let preparation {
                        Text(preparation)
                            .font(.footnote)
                            .foregroundStyle(Color.muted)
                            .padding(.top, 2)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                RowChevron()
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.name)
        .accessibilityValue(spoken)
        .accessibilityHint("Opens its profile")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Remove from My Colleges", onRemove)
        .accessibilityIdentifier("colleges.selected.\(profile.id)")
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove from My Colleges", systemImage: "minus.circle")
            }
        }
    }

    private func leadFigure(_ comparison: CollegeComparison) -> LeadFigure? {
        switch comparison.lead {
        case .gpa(let gpa, let title):
            return LeadFigure(label: title, value: gpa.display, isMuted: false,
                              spoken: "\(title), \(gpa.display) of \(GradeFormat.gpa(gpa.maximum))")
        case .withheld(let title):
            return LeadFigure(label: title, value: "Unavailable", isMuted: true, spoken: "\(title), unavailable")
        case .notYet(let title):
            return LeadFigure(label: title, value: "Not yet", isMuted: true, spoken: "\(title), not yet")
        case .gradesMissing:
            // Published figures don't wait on grades; the page says why
            // the student's GPA is missing.
            return profile.headlineFigure(profile.admissions).map {
                LeadFigure(label: $0.label, value: $0.value, isMuted: true, spoken: "\($0.label), \($0.value)")
            }
        case .loading, .notCompared:
            return nil
        }
    }

    @ViewBuilder
    private func lead(_ figure: LeadFigure) -> some View {
        let tone = figure.isMuted ? Color.muted : Color.ink
        if dynamicTypeSize.isAccessibilitySize {
            Text(figure.label)
                .font(.subheadline)
                .foregroundStyle(tone)
            Text(figure.value)
                .font(.figure(.body))
                .foregroundStyle(tone)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(figure.label)
                    .font(.subheadline)
                    .foregroundStyle(tone)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(figure.value)
                    .font(.figure(.body))
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Picker

/// Choosing colleges for My Colleges: the whole catalog on its own search
/// field, separate from Search's college query. Each tap saves at once.
/// It opens for one account and saves only for that account; switching
/// accounts closes it.
private struct CollegePickerSheet: View {
    var originScope: String

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var themeManager = ThemeManager.shared
    @State private var query = ""
    /// The choices when the sheet opened, so rows don't move as they're tapped.
    @State private var openedWith: [String]?
    @State private var changes = 0

    private var planning: StudentPlanningStore { store.planning }

    private var canSave: Bool {
        store.localAccountScope == originScope && planning.accountScope == originScope
            && !planning.collegeSelectionUnavailable
    }

    private var queryBinding: Binding<String> {
        Binding(get: { query }, set: { query = String($0.prefix(AppRouter.searchQueryLimit)) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, Metrics.page)
                .padding(.bottom, 24)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("colleges.picker")
            }
            .softScrollEdges()
            .scrollDismissesKeyboard(.immediately)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Choose Colleges")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: queryBinding, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "College name or abbreviation")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("colleges.picker.done")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .tint(Color.themeAccent)
        .foregroundStyle(Color.ink)
        .preferredColorScheme(themeManager.appearance.colorScheme)
        .sensoryFeedback(.selection, trigger: changes)
        .onAppear {
            guard canSave else { dismiss(); return }
            if openedWith == nil { openedWith = planning.selectedCollegeIDs }
        }
        .onChange(of: store.accountRevision) { _, _ in dismiss() }
        .onChange(of: store.localAccountScope) { _, _ in dismiss() }
        .onChange(of: planning.accountScope) { _, _ in dismiss() }
    }

    @ViewBuilder
    private var content: some View {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if planning.collegeSelectionError != nil {
            Text("Couldn't save your colleges. Try again.")
                .font(.footnote)
                .foregroundStyle(Color.gradeAttention)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .accessibilityIdentifier("colleges.picker.error")
        }
        if search.isEmpty {
            let chosen = (openedWith ?? []).compactMap { CollegeProfileCatalog.byID[$0] }
            let chosenIDs = Set(chosen.map(\.id))
            if !chosen.isEmpty {
                group("Chosen", chosen, isFirst: true)
            }
            group(chosen.isEmpty ? "All colleges" : "Other colleges",
                  CollegeProfileCatalog.profiles.filter { !chosenIDs.contains($0.id) }, isFirst: chosen.isEmpty)
        } else {
            let results = CollegeProfileCatalog.search(search)
            if results.isEmpty {
                EmptyStateView(
                    title: "No colleges found",
                    message: "No college name or abbreviation matches “\(search)”."
                )
                .accessibilityIdentifier("colleges.picker.empty")
            } else {
                group("\(results.count) \(results.count == 1 ? "match" : "matches")", results, isFirst: true)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ profiles: [CollegeProfile], isFirst: Bool) -> some View {
        GroupLabel(title)
            .padding(.top, isFirst ? 8 : 20)
        ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
            if index > 0 { InsetDivider() }
            row(profile)
        }
    }

    private func row(_ profile: CollegeProfile) -> some View {
        let isSelected = planning.selectedCollegeIDs.contains(profile.id)
        let location = profile.admissions?.location
        return ChoiceRow(title: profile.name, note: (location?.isEmpty ?? true) ? nil : location,
                         isSelected: isSelected) {
            toggle(profile.id, selected: !isSelected)
        }
        .disabled(!canSave)
        .accessibilityIdentifier("colleges.picker.row.\(profile.id)")
    }

    private func toggle(_ id: String, selected: Bool) {
        guard canSave else { dismiss(); return }
        if planning.setCollegeSelected(selected, collegeID: id, expectedAccountScope: originScope) {
            changes += 1
        }
    }
}

// MARK: - Row

/// What one list row says: a lead published figure, where the college is
/// and how many it admitted, and at most one personal line.
fileprivate struct CollegeRowContent {
    enum Personal {
        case empty
        case loading
        case line(String)
    }

    var figure: (label: String, value: String)?
    var context: String
    var personal: Personal

    @MainActor init(profile: CollegeProfile, input: CollegeEstimateInput, creditOverrides: [TranscriptCreditOverride] = []) {
        let details = profile.admissions
        figure = profile.headlineFigure(details)

        var parts: [String] = []
        if let location = details?.location, !location.isEmpty { parts.append(location) }
        // A resolved rate is published or exact; approximate counts give none.
        if let rate = details?.acceptance?.resolvedRatePercent {
            parts.append("Admitted \(CollegeFormat.percent(rate))")
        }
        context = parts.isEmpty ? profile.rowDescription : parts.joined(separator: ". ")

        // Only a placed GPA or a college's own estimate earns the line; the
        // same 4.0 reference on every row would say nothing new.
        let placesReference = profile.comparesWithReference && profile.quartiles != nil
        if input.isLoading, profile.method.hasPublishedCalculation || placesReference {
            personal = .loading
            return
        }
        if profile.method.hasPublishedCalculation,
           let result = input.result(for: profile), let gpa = CollegePersonalGPA.estimate(result) {
            personal = .line(gpa.rowLine(profile))
        } else if placesReference, let report = input.reference(),
                  let gpa = CollegePersonalGPA.reference(report, profile: profile), gpa.position != nil {
            personal = .line(gpa.rowLine(profile))
        } else if let rows = input.preparation(details, creditOverrides: creditOverrides), let summary = CollegePreparationSummary(rows) {
            personal = .line(summary.text)
        } else {
            personal = .empty
        }
    }

    var spoken: String {
        var parts = [context]
        if let figure { parts.append("\(figure.label), \(figure.value)") }
        if case .line(let line) = personal { parts.append(line) }
        return parts.joined(separator: ". ")
    }
}

/// A college's name and lead published figure, where it is and how many it
/// admitted, and one personal line where there's something to say. Opens
/// the profile by route, or through `onOpen` from Search.
struct CollegeProfileRow: View {
    var profile: CollegeProfile
    var input: CollegeEstimateInput
    var onOpen: (() -> Void)? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let corrections = store.planning.accountScope == store.localAccountScope ? store.planning.coursePlan.creditOverrides : []
        let content = CollegeRowContent(profile: profile, input: input, creditOverrides: corrections)
        if let onOpen {
            Button(action: onOpen) { label(content) }
                .buttonStyle(RowPressStyle())
                .modifier(RowAccessibility(profile: profile, spoken: content.spoken))
        } else {
            NavigationLink(value: CoursesRoute.collegeProfile(profile.id)) { label(content) }
                .buttonStyle(RowPressStyle())
                .modifier(RowAccessibility(profile: profile, spoken: content.spoken))
        }
    }

    private var stacks: Bool { dynamicTypeSize >= .xxLarge }

    private func label(_ content: CollegeRowContent) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ink)
                if stacks, let figure = content.figure {
                    Text("\(figure.label) \(figure.value)")
                        .font(.figure(.subheadline))
                        .foregroundStyle(Color.ink)
                }
                Text(content.context)
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                switch content.personal {
                case .empty:
                    EmptyView()
                case .loading:
                    SkeletonText(.footnote, length: 24)
                        .padding(.top, 2)
                case .line(let line):
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Color.ink)
                        .padding(.top, 2)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            if !stacks, let figure = content.figure {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(figure.value)
                        .font(.figure(.body))
                        .foregroundStyle(Color.ink)
                    Text(figure.label)
                        .font(.caption)
                        .foregroundStyle(Color.muted)
                }
                .lineLimit(1)
                .fixedSize()
            }
            RowChevron()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct RowAccessibility: ViewModifier {
    var profile: CollegeProfile
    var spoken: String

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(profile.name)
            .accessibilityValue(spoken)
            .accessibilityHint("Shows your GPA beside published figures, preparation, and sources")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("colleges.profile.\(profile.id)")
    }
}

/// The navigation bar's way into college search, on the list and on each
/// college.
private struct CollegeSearchToolbarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Search colleges")
        .accessibilityIdentifier("colleges.search.toolbar")
    }
}

/// A sourced caption under a group of figures: who and when they describe,
/// opening the primary source. One per run of figures sharing a source.
private struct ProvenanceLink: View {
    var caption: String
    var url: URL
    var subject: String

    var body: some View {
        Link(destination: url) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.faint)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(subject) source")
        .accessibilityValue(caption)
        .accessibilityHint("Opens \(url.host() ?? "the source") in Safari")
        .accessibilityAddTraits(.isLink)
    }
}

/// One published figure and who it describes.
fileprivate struct CollegeFact: Identifiable {
    struct Source: Hashable {
        var cohort: String
        var population: String
        var url: URL
        var caption: String { CollegeFormat.provenance(cohort: cohort, population: population) }
    }

    var id: String
    var label: String
    var value: String
    var detail: String? = nil
    var source: Source

    /// Consecutive figures sharing a source, so each run takes one caption.
    static func runs(_ facts: [CollegeFact]) -> [[CollegeFact]] {
        var runs: [[CollegeFact]] = []
        for fact in facts {
            if let last = runs.last?.last, last.source == fact.source {
                runs[runs.count - 1].append(fact)
            } else {
                runs.append([fact])
            }
        }
        return runs
    }
}

// MARK: - Detail

/// A published preparation subject, with the student's local credits once
/// courses load.
fileprivate struct CollegePreparationLine: Identifiable {
    var id: String
    var subject: String
    var units: Double
    var kind: CollegePreparationKind
    var note: String
    var sourceURL: URL
    var personal: CollegePreparationRow?
}

/// One college. "You and [college]" leads with the same comparison as its
/// My Colleges row: the student's estimate on its published method, or
/// Elevate's generic 4.0 reference beside unweighted figures, placed in the
/// published range only on a matching scale, with that range's source; then
/// rigor and subject preparation. The published class, how the college
/// reads GPA, every record used and the sources sit behind disclosures.
struct CollegeProfileDetailView: View {
    var profile: CollegeProfile

    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectionChanges = 0
    @State private var selectionFailed = false

    /// The signed-in account whose readable college list is loaded, or nil.
    private var selectionScope: String? {
        guard let scope = store.localAccountScope, store.planning.accountScope == scope,
              !store.planning.collegeSelectionUnavailable else { return nil }
        return scope
    }

    var body: some View {
        let input = CollegeEstimateInput(store)
        let details = profile.admissions
        let result = input.result(for: profile)
        let reference = input.reference()
        let comparison = CollegeComparison(profile: profile, input: input, result: result, reference: reference)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    lastUpdated: store.coursesLastUpdated,
                    isRefreshing: store.coursesLoading && store.courses != nil,
                    error: store.courses != nil ? store.coursesError : nil
                ) {
                    await store.refreshCourses(force: true)
                }

                if let location = details?.location, !location.isEmpty {
                    Text(location)
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .accessibilityIdentifier("colleges.location")
                }

                you(input, details: details, comparison: comparison, result: result, reference: reference)
                    .padding(.top, 12)
                published(result, details: details)
                    .padding(.top, Metrics.sectionGap)
                InsetDivider()
                method(result, reference: reference, details: details)
                InsetDivider()
                sources(details)
                InsetDivider()
                searchAnother
            }
            .padding(.horizontal, Metrics.page)
            .padding(.bottom, 32)
        }
        .visibleRefreshable { await store.refreshCourses(force: true) }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let scope = selectionScope {
                ToolbarItem(placement: .topBarTrailing) {
                    let isChosen = store.planning.selectedCollegeIDs.contains(profile.id)
                    Button { toggleSelection(!isChosen, scope: scope) } label: {
                        Image(systemName: isChosen ? "checkmark" : "plus")
                    }
                    .accessibilityLabel(isChosen ? "Remove from My Colleges" : "Add to My Colleges")
                    .accessibilityIdentifier("colleges.detail.selection")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                CollegeSearchToolbarButton { router.openCollegeSearch() }
            }
        }
        .sensoryFeedback(.selection, trigger: selectionChanges)
        .alert("Couldn't save your colleges", isPresented: $selectionFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again.")
        }
        .onChange(of: store.accountRevision) { _, _ in selectionFailed = false }
        .accessibilityIdentifier("colleges.detail.\(profile.id)")
    }

    /// Saves only for the account shown when the button was tapped.
    private func toggleSelection(_ selected: Bool, scope: String) {
        guard selectionScope == scope else { return }
        if store.planning.setCollegeSelected(selected, collegeID: profile.id, expectedAccountScope: scope) {
            selectionChanges += 1
        } else {
            selectionFailed = true
        }
    }

    // MARK: You and the college

    /// Published figures don't depend on the account, so only the personal
    /// lines wait for courses or report their failure.
    private func you(_ input: CollegeEstimateInput, details: CollegeAdmissionsDetails?, comparison: CollegeComparison,
                     result: CollegeGPAResult?, reference: GPAConversionReport?) -> some View {
        let corrections = store.planning.accountScope == store.localAccountScope ? store.planning.coursePlan.creditOverrides : []
        let preparation = preparationLines(details, rows: input.preparation(details, creditOverrides: corrections))
        let rigor = reference.flatMap { $0.includedRecords.isEmpty ? nil : CollegeRigorCount($0.includedRecords) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeading("You and \(profile.name)")
            yourGPA(input, comparison: comparison, result: result)
            if let rigor {
                InsetDivider()
                rigorRow(rigor)
            }
            if !preparation.isEmpty {
                preparationBlock(preparation, scope: details?.preparationScope)
                    .padding(.top, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("colleges.you")
    }

    /// The same comparison as the college's My Colleges row. A college with
    /// nothing comparable says why, whatever the state of the grades.
    @ViewBuilder
    private func yourGPA(_ input: CollegeEstimateInput, comparison: CollegeComparison,
                         result: CollegeGPAResult?) -> some View {
        switch input {
        case .loading:
            if case .notCompared = comparison.lead {
                notCompared(comparison)
            } else {
                SkeletonRow(lines: [SkeletonLine(.body, 16), SkeletonLine(.footnote, 26)],
                            trailing: [SkeletonLine(.figure(.title2), 4)])
                    .loadingPlaceholder("Loading your GPA")
            }
        case .failed(let error):
            InlineErrorState(title: "Couldn't load courses", message: error) {
                await store.refreshCourses(force: true)
            }
            .padding(.vertical, 8)
            .accessibilityIdentifier("colleges.coursesError")
        case .unavailable:
            EmptyStateView(
                title: "Your grades aren't loaded",
                message: "Refresh to see your GPA here. Published figures below don't depend on it."
            )
            .accessibilityIdentifier("colleges.unavailable")
        case .loaded:
            switch comparison.lead {
            case .gpa(let gpa, let title):
                if !gpa.isReference, let result {
                    gpaRow(gpa, title: title, lines: estimateLines(comparison, result: result))
                } else {
                    gpaRow(gpa, title: title, lines: referenceLines(comparison, gpa: gpa))
                }
                if comparison.quotesPublishedFigure {
                    // The range or average the GPA is read against, with
                    // its cohort and source, right where it's used.
                    ProvenanceLink(caption: "\(profile.publishedGPAScale.title), \(profile.cohortDescription)",
                                   url: profile.sourceURL, subject: "GPA comparison")
                        .accessibilityIdentifier("colleges.comparisonSource")
                }
                if !gpa.isReference, let band = result?.band {
                    classShare(band)
                }
            case .withheld:
                EmptyStateView(title: "Estimate unavailable",
                               message: "\(comparison.standing ?? "") Details are under How \(profile.name) reads GPA.")
                    .accessibilityIdentifier("colleges.estimateUnavailable")
            case .notYet:
                EmptyStateView(
                    title: "No completed grades",
                    message: profile.method.hasPublishedCalculation
                        ? "This estimate uses semesters that have ended in \(profile.method.yearsLabel.lowercased()). None are posted yet."
                        : "Your generic 4.0 reference appears after a semester ends and its grades are posted."
                )
                .accessibilityIdentifier("colleges.empty")
            case .notCompared:
                notCompared(comparison)
            case .loading, .gradesMissing:
                EmptyView()
            }
        }
    }

    private func notCompared(_ comparison: CollegeComparison) -> some View {
        EmptyStateView(title: "Your GPA isn't compared here", message: comparison.standing)
            .accessibilityIdentifier("colleges.notCompared")
    }

    /// Placement first, since it's what the number means here; then how
    /// the method reads GPA.
    private func estimateLines(_ comparison: CollegeComparison, result: CollegeGPAResult) -> [(text: String, isEmphasized: Bool)] {
        var lines: [(text: String, isEmphasized: Bool)] = []
        if let standing = comparison.standing { lines.append((standing, comparison.isPlaced)) }
        if let summary = profile.methodSummary { lines.append((summary, false)) }
        if result.isAtUnweightedCeiling { lines.append(("4.00 is this scale's ceiling.", false)) }
        return lines
    }

    /// Its title already names it Elevate's generic reference, never the
    /// college's calculation.
    private func referenceLines(_ comparison: CollegeComparison, gpa: CollegePersonalGPA) -> [(text: String, isEmphasized: Bool)] {
        var lines: [(text: String, isEmphasized: Bool)] = []
        if let standing = comparison.standing { lines.append((standing, comparison.isPlaced)) }
        if gpa.value == 4 { lines.append(("4.00 is this scale's ceiling.", false)) }
        return lines
    }

    private func gpaRow(_ gpa: CollegePersonalGPA, title: String,
                        lines: [(text: String, isEmphasized: Bool)]) -> some View {
        let value = HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(gpa.display)
                .font(.figure(.title2))
                .foregroundStyle(Color.ink)
            Text("of \(GradeFormat.gpa(gpa.maximum))")
                .font(.footnote)
                .foregroundStyle(Color.muted)
        }
        .lineLimit(1)
        .fixedSize()
        return VStack(alignment: .leading, spacing: 2) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.ink)
                value
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    value
                }
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(.footnote)
                    .foregroundStyle(line.isEmphasized ? Color.ink : Color.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue((["\(gpa.display) of \(GradeFormat.gpa(gpa.maximum))"] + lines.map(\.text)).joined(separator: ". "))
        .accessibilityIdentifier("colleges.result")
    }

    private func rigorRow(_ rigor: CollegeRigorCount) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Rigor")
                .font(.body)
                .foregroundStyle(Color.ink)
            Text(rigor.text.map { "\($0) completed." } ?? "No AP or Honors semesters completed.")
                .font(.footnote)
                .foregroundStyle(Color.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("colleges.rigor")
    }

    // MARK: Preparation

    /// The published subjects, with local credits once courses load.
    private func preparationLines(_ details: CollegeAdmissionsDetails?,
                                  rows: [CollegePreparationRow]?) -> [CollegePreparationLine] {
        if let rows {
            return rows.map {
                CollegePreparationLine(id: $0.id, subject: $0.subject, units: $0.units, kind: $0.kind,
                                       note: $0.note, sourceURL: $0.sourceURL, personal: $0)
            }
        }
        guard let details else { return [] }
        return details.preparation.enumerated().map { index, requirement in
            CollegePreparationLine(id: "\(details.id)|\(index)", subject: requirement.subject, units: requirement.units,
                                   kind: requirement.kind, note: requirement.note, sourceURL: requirement.sourceURL,
                                   personal: nil)
        }
    }

    /// One row per subject. A reason several subjects share is said once
    /// beneath them; one subject's own reason stays on its row.
    private func preparationBlock(_ lines: [CollegePreparationLine], scope: String?) -> some View {
        let sources = lines.map(\.sourceURL).reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Preparation")
            if let scope { footnote(scope).padding(.vertical, 8) }
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 { InsetDivider() }
                preparationRow(line)
            }
            footnote("Local credit estimates. Current classes assume passing.")
            GPADisclosure(title: "Course eligibility and notes", identifier: "colleges.preparationNotes") {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.subject).font(.footnote.weight(.semibold))
                        if !line.note.isEmpty { footnote(line.note) }
                        if let reason = line.personal?.availabilityReason { footnote(reason) }
                    }
                    .padding(.vertical, 8)
                }
            }
            ForEach(sources, id: \.self) { url in
                ProvenanceLink(caption: sources.count == 1 ? "Preparation guidelines" : "Preparation guidelines, \(url.host() ?? "source")",
                               url: url, subject: "Preparation")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("colleges.preparation")
    }

    private func preparationRow(_ line: CollegePreparationLine) -> some View {
        let requirement = "\(CollegeFormat.units(line.units)) \(line.kind == .required ? "required" : "recommended")"
        let status = preparationStatus(line)
        return VStack(alignment: .leading, spacing: 2) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(line.subject)
                    .font(.body)
                Text(requirement)
                    .font(.figure(.subheadline, weight: .regular))
                    .foregroundStyle(Color.muted)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(line.subject)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(requirement)
                        .font(.figure(.subheadline, weight: .regular))
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if let status {
                Text(status.text)
                    .font(.footnote)
                    .foregroundStyle(status.hasGap ? Color.ink : Color.muted)
            }
            if line.personal != nil, line.personal?.remaining == nil {
                Text("Course eligibility needs review")
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
            }
        }
        .foregroundStyle(Color.ink)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "You: 3 completed, 1 current." Muted when the plan meets the subject;
    /// ink with the gap in words when it doesn't. Nothing where credits are
    /// unknown, so an unchecked subject never reads as unmet.
    private func preparationStatus(_ line: CollegePreparationLine) -> (text: String, hasGap: Bool)? {
        guard let row = line.personal else { return nil }
        var parts: [String] = []
        if let earned = row.earned { parts.append("\(CollegeFormat.units(earned)) completed") }
        if let current = row.current, current > 0 { parts.append("\(CollegeFormat.units(current)) current") }
        guard !parts.isEmpty else { return nil }
        let text = "You: \(parts.joined(separator: ", "))."
        if let remaining = row.remaining, remaining > 0 {
            return ("\(text) \(CollegeFormat.units(remaining)) more to reach \(CollegeFormat.units(row.units)).", true)
        }
        return (text, false)
    }

    // MARK: Published class data

    /// Each group of figures keeps its own cohort and source; SAT, ACT and
    /// admission counts can describe different students. The disclosure's
    /// note says what all of it is.
    private func published(_ result: CollegeGPAResult?, details: CollegeAdmissionsDetails?) -> some View {
        let comparable = profile.comparesWithEstimate ? result : nil
        let tests = testFacts(details)
        let admission = admissionFacts(details)
        let guidance = guidanceText(details)
        let detailsNote = details?.publicationNote.flatMap { $0 == profile.publicationNote ? nil : $0 }
        return GPADisclosure(title: "Published class", note: "Past class, not a cutoff.", identifier: "colleges.published") {
            VStack(alignment: .leading, spacing: 0) {
                GroupLabel("GPA")
                if profile.showsGPAFigures {
                    gpaFigures(comparable)
                } else {
                    EmptyStateView(
                        title: "No verified GPA figures here",
                        message: guidance == nil ? (profile.publicationNote ?? "The linked source has no class GPA figures.") : nil
                    )
                    .accessibilityIdentifier("colleges.noPublished")
                }
                if let guidance {
                    // Already inside a disclosure, so the guidance reads
                    // openly under its own label.
                    let cohort = profile.cohort.localizedCaseInsensitiveContains("guidance") ? nil : profile.cohort
                    GroupLabel(cohort.map { "Admissions guidance, \(CollegeFormat.midSentence($0))" } ?? "Admissions guidance")
                        .padding(.top, 12)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(guidance)
                        if !profile.showsGPAFigures, let note = profile.publicationNote { Text(note) }
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("colleges.guidance")
                }

                if details != nil {
                    GroupLabel("Tests")
                        .padding(.top, 20)
                    if tests.isEmpty {
                        Text("No verified test-score figures here.")
                            .font(.subheadline)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 8)
                            .accessibilityIdentifier("colleges.noTests")
                    } else {
                        factRuns(tests, subject: "Test score")
                            .accessibilityIdentifier("colleges.tests")
                    }
                }

                if !admission.isEmpty {
                    GroupLabel("Admission")
                        .padding(.top, 20)
                    factRuns(admission, subject: "Admission")
                        .accessibilityIdentifier("colleges.admission")
                }

                if let detailsNote {
                    footnote(detailsNote)
                }
            }
        }
    }

    /// The college's published GPA figures, their source caption, and any
    /// note that changes what they mean. The band holding a comparable
    /// estimate is marked; its share leads under You and the college.
    @ViewBuilder
    private func gpaFigures(_ comparable: CollegeGPAResult?) -> some View {
        if let quartiles = profile.quartiles {
            quartileFigures(quartiles)
        }
        if !profile.bands.isEmpty {
            bandFigures(highlighting: comparable?.band?.label)
        }
        if let mean = profile.reportedMean {
            if profile.quartiles != nil || !profile.bands.isEmpty { InsetDivider() }
            figureRow("Average", value: CollegeProfile.mean(mean))
        }
        ProvenanceLink(caption: "\(profile.publishedGPAScale.title), \(profile.cohortDescription)",
                       url: profile.sourceURL, subject: "GPA")
            .accessibilityIdentifier("colleges.publishedScale")
        if profile.publishedGPAScale == .unspecified, profile.publicationNote == nil {
            footnote("The source doesn't say whether these GPAs are weighted.")
        }
        if let note = profile.publicationNote {
            footnote(note)
                .accessibilityIdentifier("colleges.publicationNote")
        }
        if let reporting = profile.reportingPercent {
            footnote("\(CollegeGPAStanding.percent(reporting))% of enrolled first-year students reported a GPA.")
        }
    }

    /// The college's own guidance, unless it's already one of the GPA
    /// policy facts shown under How it reads GPA.
    private func guidanceText(_ details: CollegeAdmissionsDetails?) -> String? {
        guard let summary = profile.publishedSummary, !summary.isEmpty else { return nil }
        if details?.gpaPolicyFacts.contains(where: { $0.text == summary }) == true { return nil }
        return summary
    }

    /// SAT and ACT ranges, SAT sections and averages, each with its own
    /// cohort and population. Sections are never a total.
    private func testFacts(_ details: CollegeAdmissionsDetails?) -> [CollegeFact] {
        guard let details else { return [] }
        var facts: [CollegeFact] = []
        if let sat = details.satRange {
            facts.append(CollegeFact(id: "sat", label: "SAT middle 50%", value: CollegeFormat.range(sat.lower, sat.upper),
                                     source: .init(cohort: sat.cohort, population: sat.population, url: sat.sourceURL)))
        }
        for (index, section) in details.satSections.enumerated() {
            let name = section.section.lowercased().hasSuffix("section") ? section.section : "\(section.section) section"
            facts.append(CollegeFact(id: "sat.section.\(index)", label: "SAT \(name), middle 50%",
                                     value: CollegeFormat.range(section.lower, section.upper),
                                     source: .init(cohort: section.cohort, population: section.population, url: section.sourceURL)))
        }
        if let act = details.actRange {
            facts.append(CollegeFact(id: "act", label: "ACT middle 50%", value: CollegeFormat.range(act.lower, act.upper),
                                     source: .init(cohort: act.cohort, population: act.population, url: act.sourceURL)))
        }
        for (index, mean) in details.testMeans.enumerated() {
            facts.append(CollegeFact(id: "mean.\(index)", label: "\(mean.test) average", value: GradeFormat.upToTwoDecimals(mean.value),
                                     source: .init(cohort: mean.cohort, population: mean.population, url: mean.sourceURL)))
        }
        return facts
    }

    /// The admission rate with its counts, and enrollment. Approximate
    /// counts say so and never yield a rate.
    private func admissionFacts(_ details: CollegeAdmissionsDetails?) -> [CollegeFact] {
        guard let details else { return [] }
        var facts: [CollegeFact] = []
        if let acceptance = details.acceptance {
            let source = CollegeFact.Source(cohort: acceptance.cohort, population: acceptance.population, url: acceptance.sourceURL)
            let suffix = acceptance.isApproximate ? "+" : ""
            if let rate = acceptance.resolvedRatePercent {
                var detail: String?
                if let admitted = acceptance.admitted, let applicants = acceptance.applicants {
                    detail = "\(admitted.formatted())\(suffix) of \(applicants.formatted())\(suffix) applicants."
                }
                facts.append(CollegeFact(id: "rate", label: "Admitted", value: CollegeFormat.percent(rate), detail: detail, source: source))
            } else if let admitted = acceptance.admitted {
                let detail = acceptance.applicants.map { "Of \($0.formatted())\(suffix) applicants. No exact rate." }
                facts.append(CollegeFact(id: "admitted", label: "Admitted", value: "\(admitted.formatted())\(suffix)",
                                         detail: detail, source: source))
            } else if let applicants = acceptance.applicants {
                facts.append(CollegeFact(id: "applicants", label: "Applicants", value: "\(applicants.formatted())\(suffix)",
                                         source: source))
            }
        }
        if let enrollment = details.enrollment {
            facts.append(CollegeFact(id: "enrolled", label: "Enrolled", value: enrollment.count.formatted(),
                                     source: .init(cohort: enrollment.cohort, population: enrollment.population, url: enrollment.sourceURL)))
        }
        return facts
    }

    /// Figures in runs that share a source, each run captioned once.
    private func factRuns(_ facts: [CollegeFact], subject: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(CollegeFact.runs(facts).enumerated()), id: \.offset) { _, run in
                ForEach(Array(run.enumerated()), id: \.element.id) { index, fact in
                    if index > 0 { InsetDivider() }
                    figureRow(fact.label, value: fact.value, detail: fact.detail)
                }
                if let source = run.first?.source {
                    ProvenanceLink(caption: source.caption, url: source.url, subject: subject)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The published share of the class in the estimate's band, labeled in
    /// full so it can't read as a percentile.
    private func classShare(_ band: CollegeGPABand) -> some View {
        let described = band.maximum == nil ? "a GPA of \(band.label)" : "a GPA in the \(band.label) band"
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(CollegeGPAStanding.percent(band.percent))%")
                .font(.figure(.title3, weight: .semibold))
                .foregroundStyle(Color.ink)
            Text("of \(profile.population.classDescription) had \(described), the band holding your estimate")
                .font(.body)
                .foregroundStyle(Color.ink)
            Text("This describes that class, not your percentile or rank.")
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .padding(.top, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("colleges.classShare")
    }


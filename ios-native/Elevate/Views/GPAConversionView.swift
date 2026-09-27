import SwiftUI

/// Saved manual classes for every high-school year; the calculator uses them
/// only for years with no Skyward courses.
enum GPAConversionInputs {
    static var manualClassesByYear: [Int: [ManualClass]] {
        Dictionary(uniqueKeysWithValues: [GradeLevel.freshman, .sophomore, .junior, .senior].compactMap { level in
            level.gradeYear.map { ($0, WhatIfStore.manualClasses(gradeLevel: level)) }
        })
    }

    /// Completed semesters only, independent of the GPA screen's school year.
    static func completedReport(courses: [UnifiedCourseData]?, gradeYears: Set<Int>? = nil,
                                policy: GPAConversionPolicy) -> GPAConversionReport {
        GPAConversionCalculator.calculate(
            courses: courses ?? [],
            manualClassesByYear: manualClassesByYear,
            gradeYears: gradeYears,
            policy: policy,
            completedOnly: true
        )
    }

    /// Both generic scales over the same completed semesters.
    static func completedScales(courses: [UnifiedCourseData]?, gradeYears: Set<Int>? = nil) -> GPAScaleReports {
        GPAScaleReports(
            unweighted: completedReport(courses: courses, gradeYears: gradeYears, policy: .unweighted4Point),
            weighted: completedReport(courses: courses, gradeYears: gradeYears, policy: .weighted5Point)
        )
    }

    /// Out-of-scope and unfinished semesters are intentionally excluded, not data gaps.
    static func notConverted(_ skipped: [GPAConversionSkippedRecord]) -> [GPAConversionSkippedRecord] {
        skipped.filter { $0.reason != .outsideSelectedYears && $0.reason != .inProgress }
    }

    /// The years actually included, not the full eligible high-school range.
    static func yearScope(_ records: [GPAConversionRecord]) -> String {
        let years = Array(Set(records.map(\.gradeYear))).sorted()
        guard let first = years.first, let last = years.last else { return "Completed grades" }
        if years.count == 1 { return "Grade \(first)" }
        if years.count == last - first + 1 { return "Grades \(first)–\(last)" }
        return "Grades " + ListFormatter.localizedString(byJoining: years.map(String.init))
    }

    /// "1 semester grade", "12 semester grades".
    static func semesterGrades(_ count: Int) -> String {
        "\(count) semester \(count == 1 ? "grade" : "grades")"
    }

    /// "Grade 11, Semester 1".
    static func recordName(year: Int?, semester: TermLabel) -> String {
        let term = semester.displayName
        guard let year else { return term }
        return "Grade \(year), \(term)"
    }

    static func courseName(_ raw: String) -> String {
        ClassNameFormatter.format(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_"))
    }
}

/// Elevate's generic unweighted 4.0 and weighted 5.0 reports for one scope.
/// Both come from `GPAConversionCalculator`; nothing is recalculated here.
struct GPAScaleReports {
    var unweighted: GPAConversionReport
    var weighted: GPAConversionReport

    /// Both values, or nil when no completed semester is included.
    var values: (unweighted: Double, weighted: Double)? {
        guard let unweighted = unweighted.value, let weighted = weighted.value else { return nil }
        return (unweighted, weighted)
    }

    /// The weighted scale's bonus for each included record, by record ID,
    /// where the weighted report gave more points than the unweighted one.
    var bonuses: [String: Double] {
        let base = Dictionary(unweighted.includedRecords.map { ($0.id, $0.points) }, uniquingKeysWith: { first, _ in first })
        var result: [String: Double] = [:]
        for record in weighted.includedRecords {
            if let points = base[record.id], record.points > points { result[record.id] = record.points - points }
        }
        return result
    }

    /// Included semesters that received an AP/Honors bonus.
    var advancedCount: Int { bonuses.count }

    /// Skipped records are the same on both scales; the unweighted list is used.
    var notConverted: [GPAConversionSkippedRecord] {
        GPAConversionInputs.notConverted(unweighted.skippedRecords)
    }
}

/// Elevate's two generic scales from every completed semester grade, shown
/// together and separate from the district GPA. Each year opens its own
/// semesters; conversion rules, the student's AP and Honors bonuses, and
/// skipped records wait behind a tap. Percentages are never divided down
/// to a scale.
struct GPAConversionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if store.coursesLoading && store.courses == nil {
                GPAEstimatePlaceholder(label: "Loading GPA converter", rows: 3)
            } else if let error = store.coursesError, store.courses == nil {
                ErrorStateView(title: "Couldn't load courses", message: error) {
                    await store.refreshCourses(force: true)
                }
            } else {
                content(GPAConversionInputs.completedScales(courses: store.courses))
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("GPA Converter")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("gpaConverter.screen")
    }

    private func content(_ scales: GPAScaleReports) -> some View {
        let skipped = scales.notConverted
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    lastUpdated: store.coursesLastUpdated,
                    isRefreshing: store.coursesLoading && store.courses != nil,
                    error: store.courses != nil ? store.coursesError : nil
                ) {
                    await store.refreshCourses(force: true)
                }

                if let values = scales.values {
                    GPAScalePair(unweighted: values.unweighted, weighted: values.weighted,
                                 isProminent: true, identifier: "gpaConverter.result")
                        .padding(.top, 12)
                    Text(summary(scales.unweighted, skipped: skipped.count))
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .accessibilityIdentifier("gpaConverter.scope")

                    yearsSection(scales.unweighted)
                        .padding(.top, 20)
                } else {
                    EmptyStateView(
                        title: "No completed semesters yet",
                        message: "The converter uses posted grades from semesters that have ended. Semesters in progress aren't converted."
                    )
                    .padding(.top, 4)
                    .accessibilityIdentifier("gpaConverter.empty")
                }

                detailsSection(scales, skipped: skipped)
                    .padding(.top, Metrics.sectionGap)
            }
            .padding(.horizontal, Metrics.page)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .visibleRefreshable { await store.refreshCourses(force: true) }
    }

    /// "Grades 9–11, from 40 completed semester grades, each counted equally. 3 not converted."
    private func summary(_ report: GPAConversionReport, skipped: Int) -> String {
        let count = report.includedCount
        var text = "\(GPAConversionInputs.yearScope(report.includedRecords)), from \(count) completed semester \(count == 1 ? "grade" : "grades"), each counted equally."
        if skipped > 0 { text += " \(skipped) not converted." }
        return text
    }

    // MARK: - Weighting

    /// What separates the two figures, under the bonus rule in How grades
    /// convert: how many of the student's semesters received it, and that
    /// the scales are Elevate's own.
    private func weightingSection(_ scales: GPAScaleReports, unweighted: Double) -> some View {
        let advanced = scales.advancedCount
        let total = scales.weighted.includedCount
        let yours: String
        if advanced == 0 {
            yours = "None of your completed semester grades received a bonus, so both scales show the same grades."
        } else if unweighted == 4 {
            yours = "Every completed grade is an A, so unweighted is at its 4.00 ceiling. Weighted is higher because \(advanced) of your \(total) semester grades received a bonus."
        } else {
            yours = "\(advanced) of your \(total) semester grades received a bonus."
        }
        return VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Your AP and Honors grades")
            Text(yours)
                .font(.body)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .accessibilityIdentifier("gpaConverter.advanced")
            Text("These are Elevate's generic scales, not any college's formula. Colleges that recalculate GPA choose their own courses and bonuses.")
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    // MARK: - By year

    private func yearsSection(_ report: GPAConversionReport) -> some View {
        let years = Array(Set(report.includedRecords.map(\.gradeYear))).sorted()
        return VStack(alignment: .leading, spacing: 0) {
            GroupLabel("By year")
            ForEach(Array(years.enumerated()), id: \.element) { index, year in
                if index > 0 { InsetDivider() }
                yearRow(year, scales: GPAConversionInputs.completedScales(courses: store.courses, gradeYears: [year]))
            }
        }
    }

    /// Stacks its figures under the name from xxLarge text, where two
    /// labeled figures beside a name stop fitting a phone's width.
    private func yearRow(_ year: Int, scales: GPAScaleReports) -> some View {
        let unweighted = GradeFormat.gpa(scales.unweighted.value)
        let weighted = GradeFormat.gpa(scales.weighted.value)
        let records = scales.unweighted.includedRecords
        var note = GPAConversionInputs.semesterGrades(records.count)
        if !records.isEmpty, records.allSatisfy({ $0.source == .manual }) {
            note += ", added by you"
        }
        let stacks = dynamicTypeSize >= .xxLarge
        return NavigationLink(value: CoursesRoute.gpaConverterYear(year, .unweighted4Point)) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grade \(year)")
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                    if stacks {
                        Group {
                            Text("Unweighted \(unweighted)")
                            Text("Weighted \(weighted)")
                        }
                        .font(.figure(.body))
                        .foregroundStyle(Color.ink)
                        .padding(.top, 2)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                if !stacks {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        yearFigure(unweighted, caption: "Unweighted")
                        yearFigure(weighted, caption: "Weighted")
                    }
                    .fixedSize()
                }
                RowChevron()
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Grade \(year)")
        .accessibilityValue("Unweighted \(unweighted) of 4.0, weighted \(weighted) of 5.0. \(note)")
        .accessibilityHint("Shows each semester grade")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("gpaConverter.year.\(year)")
    }

    private func yearFigure(_ value: String, caption: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .font(.figure(.body))
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption)
                .foregroundStyle(Color.muted)
        }
        .lineLimit(1)
    }

    // MARK: - Details

    private func detailsSection(_ scales: GPAScaleReports, skipped: [GPAConversionSkippedRecord]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupLabel("Details")
            GPADisclosure(title: "How grades convert", note: "Letter bands and AP or Honors bonuses",
                          identifier: "gpaConverter.details") {
                VStack(alignment: .leading, spacing: 0) {
                    GPAConversionMapping()
                    if let values = scales.values {
                        weightingSection(scales, unweighted: values.unweighted)
                            .padding(.top, 20)
                    }
                    GPAGradeCheck()
                        .padding(.top, 20)
                    Text(scales.unweighted.scopeExplanation)
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }
            }
            if !skipped.isEmpty {
                InsetDivider()
                GPADisclosure(title: "Not converted", note: "Kept out of both scales", count: skipped.count,
                              identifier: "gpaConverter.skipped") {
                    GPANotConvertedList(skipped: skipped)
                }
            }
        }
    }
}

// MARK: - Year detail

/// One high-school year on both scales, then each semester's converted
/// grades with any weighted bonus. Opened from the converter's By year rows.
struct GPAConversionYearView: View {
    var year: Int
    /// The route's legacy scale. Both scales are always shown, so it no
    /// longer changes this screen.
    var policy: GPAConversionPolicy = .unweighted4Point

    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.coursesLoading && store.courses == nil {
                GPAEstimatePlaceholder(label: "Loading grade \(year)", rows: 5)
            } else if let error = store.coursesError, store.courses == nil {
                ErrorStateView(title: "Couldn't load courses", message: error) {
                    await store.refreshCourses(force: true)
                }
            } else {
                content(GPAConversionInputs.completedScales(courses: store.courses, gradeYears: [year]))
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Grade \(year)")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("gpaConverter.yearDetail")
    }

    private func content(_ scales: GPAScaleReports) -> some View {
        let skipped = scales.notConverted
        let bonuses = scales.bonuses
        let report = scales.unweighted
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StatusStrip(
                    lastUpdated: store.coursesLastUpdated,
                    isRefreshing: store.coursesLoading && store.courses != nil,
                    error: store.courses != nil ? store.coursesError : nil
                ) {
                    await store.refreshCourses(force: true)
                }

                if let values = scales.values {
                    GPAScalePair(unweighted: values.unweighted, weighted: values.weighted,
                                 isProminent: true, identifier: "gpaConverter.result")
                        .padding(.top, 12)
                    Text(yearSummary(count: report.includedCount, advanced: scales.advancedCount))
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    ForEach([TermLabel.sm1, .sm2], id: \.self) { semester in
                        let records = report.includedRecords.filter { $0.semester == semester }
                        if !records.isEmpty {
                            GroupLabel(semester.displayName)
                                .padding(.top, Metrics.sectionGap)
                            ForEach(Array(records.enumerated()), id: \.element.id) { row, record in
                                if row > 0 { InsetDivider() }
                                GPAConversionRecordRow(record: record, note: note(record, bonus: bonuses[record.id]))
                            }
                        }
                    }
                } else {
                    EmptyStateView(
                        title: "No completed semesters in grade \(year)",
                        message: "Grades appear here after a semester ends and its grade is posted."
                    )
                    .padding(.top, 4)
                    .accessibilityIdentifier("gpaConverter.empty")
                }

                if !skipped.isEmpty {
                    GPADisclosure(title: "Not converted", note: "Kept out of both scales", count: skipped.count,
                                  identifier: "gpaConverter.skipped") {
                        GPANotConvertedList(skipped: skipped)
                    }
                    .padding(.top, Metrics.sectionGap)
                }
            }
            .padding(.horizontal, Metrics.page)
            .padding(.bottom, 32)
        }
        .visibleRefreshable { await store.refreshCourses(force: true) }
    }

    /// "From 12 semester grades, each counted equally. 4 received an AP or Honors bonus."
    private func yearSummary(count: Int, advanced: Int) -> String {
        var text = "From \(GPAConversionInputs.semesterGrades(count)), each counted equally."
        if advanced > 0 {
            text += " \(advanced) received an AP or Honors bonus on the weighted scale."
        }
        return text
    }

    /// Provenance, and the weighted bonus where one applied. Rows show the
    /// unweighted points; the bonus is added only on the weighted scale.
    private func note(_ record: GPAConversionRecord, bonus: Double?) -> String {
        var parts = [record.source.rawValue]
        if let bonus {
            let level = record.courseLevel == .ap ? "AP-level" : "Honors"
            parts.append("\(level) +\(GradeFormat.upToTwoDecimals(bonus)) weighted")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Shared pieces

/// Elevate's two generic scales over the same semesters: unweighted out of
/// 4.0 and weighted out of 5.0, each named in words. Side by side where
/// both fit; stacked from xxLarge text. The prominent form is a screen's
/// lead figure; the compact form sits inside a page.
struct GPAScalePair: View {
    var unweighted: Double
    var weighted: Double
    var isProminent: Bool
    var identifier: String
    var formatValue: (Double) -> String = GradeFormat.gpa

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 48

    var body: some View {
        Group {
            if dynamicTypeSize >= .xxLarge {
                VStack(alignment: .leading, spacing: 12) { columns }
            } else {
                HStack(alignment: .top, spacing: 24) { columns }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var columns: some View {
        column("Unweighted", value: unweighted, maximum: 4, suffix: "unweighted")
        column("Weighted", value: weighted, maximum: 5, suffix: "weighted")
    }

    private func column(_ title: String, value: Double, maximum: Double, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.ink)
            Text(formatValue(value))
                .font(isProminent ? Font.display(size: min(heroSize, 80)) : .figure(.title2))
                .tracking(isProminent ? -1 : 0)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .contentTransition(.numericText(value: value))
                .animation(Motion.value(reduceMotion), value: value)
            Text("out of \(maximum.formatted(.number.precision(.fractionLength(1))))")
                .font(.footnote)
                .foregroundStyle(Color.muted)
        }
        .frame(maxWidth: dynamicTypeSize >= .xxLarge ? nil : .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) GPA")
        .accessibilityValue("\(formatValue(value)) out of \(GradeFormat.gpa(maximum))")
        .accessibilityIdentifier("\(identifier).\(suffix)")
    }
}

/// A scale estimate as the screen's one large figure: what it is and which
/// years in a footnote, the value over its maximum, then one summary line.
struct GPAEstimateHero: View {
    var label: String
    var scope: String
    var value: Double
    /// Formatted by the caller, which owns any truncation rule.
    var displayValue: String
    var maximum: Double
    var summary: String
    var identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(label).foregroundStyle(Color.ink).font(.footnote)
                Text(scope).foregroundStyle(Color.muted).font(.footnote)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label).foregroundStyle(Color.ink)
                    Text(scope).foregroundStyle(Color.muted)
                }
                .font(.footnote)
            }
            if dynamicTypeSize.isAccessibilitySize {
                figure
                maximumText
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    figure
                    maximumText
                }
            }
            Text(summary)
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(scope)")
        .accessibilityValue("\(displayValue) of \(GradeFormat.gpa(maximum)). \(summary)")
        .accessibilityIdentifier(identifier)
    }

    private var figure: some View {
        Text(displayValue)
            .font(.display(size: min(heroSize, 88)))
            .tracking(-1)
            .foregroundStyle(Color.ink)
            .lineLimit(1)
            .contentTransition(.numericText(value: value))
            .animation(Motion.value(reduceMotion), value: value)
    }

    private var maximumText: some View {
        Text("of \(GradeFormat.gpa(maximum))")
            .font(.title3)
            .foregroundStyle(Color.muted)
    }
}

/// The estimate screens' first load: the hero's lines and a few open rows on
/// their real type styles. One loading announcement, no interaction.
struct GPAEstimatePlaceholder: View {
    var label: String
    var rows: Int
    var showsHero = true

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 56

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsHero {
                    VStack(alignment: .leading, spacing: 2) {
                        SkeletonText(.footnote, length: 16, tone: .secondary)
                        SkeletonText(.display(size: min(heroSize, 88)), length: 4)
                        SkeletonText(.footnote, length: 28, tone: .secondary)
                            .padding(.top, 4)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, Metrics.sectionGap)
                }
                ForEach(0..<rows, id: \.self) { index in
                    if index > 0 { InsetDivider() }
                    SkeletonRow(
                        lines: [SkeletonLine(.body, [8, 11, 7, 12, 9, 10][index % 6]), SkeletonLine(.footnote, 14)],
                        trailing: [SkeletonLine(.figure(.body), 4)]
                    )
                }
            }
            .padding(.horizontal, Metrics.page)
            .frame(maxWidth: .infinity, alignment: .leading)
            .loadingPlaceholder(label)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// An open row that reveals detail beneath it: title, optional note and
/// count, and a chevron that turns down when open. Collapsed by default;
/// Reduce Motion changes it at once.
struct GPADisclosure<Content: View>: View {
    var title: String
    var note: String?
    var count: Int?
    var identifier: String
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Motion.perform(Motion.replace(reduceMotion)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(Color.ink)
                        if let note {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(Color.muted)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let count {
                        Text("\(count)")
                            .font(.figure(.body, weight: .regular))
                            .foregroundStyle(Color.muted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.faint)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(note ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)

            if isExpanded {
                content()
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
    }
}

/// One converted semester grade: the course and a note, then the source
/// percentage turning into its points.
struct GPAConversionRecordRow: View {
    var record: GPAConversionRecord
    var note: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let name = GPAConversionInputs.courseName(record.courseName)
        let grade = GradeFormat.upToTwoDecimals(record.percentage)
        let points = GradeFormat.upToTwoDecimals(record.points)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.body)
                    if let note {
                        Text(note).font(.footnote).foregroundStyle(Color.muted)
                    }
                    Text("\(grade) converts to \(points)")
                        .font(.figure(.body))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.body)
                        if let note {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(Color.muted)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(grade)
                            .font(.figure(.subheadline, weight: .regular))
                            .foregroundStyle(Color.muted)
                        Image(systemName: "arrow.forward")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.faint)
                        Text(points)
                            .font(.figure(.body))
                            .foregroundStyle(Color.ink)
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue([note, "\(grade) converts to \(points) points"].compactMap { $0 }.joined(separator: ". "))
    }
}

/// Skipped records grouped by reason, in the calculator's reason order.
struct GPANotConvertedList: View {
    var skipped: [GPAConversionSkippedRecord]

    var body: some View {
        let reasons = GPAConversionSkipReason.allCases.filter { reason in skipped.contains { $0.reason == reason } }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(reasons.enumerated()), id: \.element) { index, reason in
                let records = skipped.filter { $0.reason == reason }
                GroupLabel("\(reason.rawValue) (\(records.count))")
                    .padding(.top, index == 0 ? 2 : 18)
                ForEach(Array(records.enumerated()), id: \.element.id) { row, record in
                    if row > 0 { InsetDivider() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GPAConversionInputs.courseName(record.courseName))
                            .font(.body)
                            .foregroundStyle(Color.ink)
                        Text(GPAConversionInputs.recordName(year: record.gradeYear, semester: record.semester))
                            .font(.footnote)
                            .foregroundStyle(Color.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}


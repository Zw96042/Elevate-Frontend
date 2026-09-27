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


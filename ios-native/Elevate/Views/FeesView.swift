import SwiftUI

/// Fees and payments as Skyward posts them. Read-only: every amount, date and
/// school year is the source text, never totalled or recomputed. The payment
/// link opens the district's public store without passing Skyward credentials.
struct FeesView: View {
    @Environment(AppStore.self) private var store
    @State private var scope: FeeScope = .fees
    @State private var showingConnect = false

    /// Eanes ISD publishes this destination on its Online Payments page.
    /// It is a public link, independent of student data and session tokens.
    private static let paymentURL = URL(string: "https://eanes.revtrak.net/")!

    var body: some View {
        Group {
            if store.canShowData {
                content
            } else {
                LoginPromptView(message: "Connect your Skyward account to see fees and payments from your school.") {
                    showingConnect = true
                }
                .softScrollEdges()
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Fees")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("fees.screen")
        .sheet(isPresented: $showingConnect) { SkywardConnectSheet() }
        .task(id: store.accountRevision) {
            guard store.canShowData else { return }
            await store.refreshFees()
        }
        .onChange(of: store.accountRevision) { _, _ in
            scope = .fees
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusLine
                    .padding(.horizontal, Metrics.page)

                // An open row, led by the same symbol as Fees on Records;
                // the trailing arrow marks a page outside the app.
                Link(destination: Self.paymentURL) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "creditcard")
                            .font(.body)
                            .foregroundStyle(Color.themeAccent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Make a payment")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.themeAccent)
                            Text("Opens Eanes ISD’s RevTrak payment site")
                                .font(.footnote)
                                .foregroundStyle(Color.muted)
                        }
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.faint)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, Metrics.page)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityHint("Opens the district’s payment website in your browser")
                .accessibilityIdentifier("fees.makePayment")
                .padding(.top, 4)
                Rule()
                    .padding(.horizontal, Metrics.page)
                    .padding(.bottom, 4)

                if let fees = store.fees {
                    if fees.availability == .unavailable {
                        EmptyStateView(
                            title: "Fees aren't available",
                            message: "Skyward hasn't made fees available for this account."
                        )
                        .padding(.horizontal, Metrics.page)
                        .accessibilityIdentifier("fees.unavailable")
                    } else {
                        recordRows(scope == .fees ? fees.fees : fees.payments)
                    }
                } else if let error = store.feesError {
                    InlineErrorState(title: "Couldn't load fees", message: error) {
                        await store.refreshFees(force: true)
                    }
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 12)
                    .accessibilityIdentifier("fees.error")
                } else {
                    // Nothing fetched or saved yet, including before the
                    // first request starts.
                    loadingRows
                }
            }
            .padding(.bottom, 24)
        }
        .softScrollEdges()
        .visibleRefreshable {
            await store.refreshFees(force: true)
        }
    }

    /// The Fees/Payments choice at the leading edge and when the records
    /// were fetched at the trailing edge. A failed refresh keeps the saved
    /// records and says when they are from.
    @ViewBuilder
    private var statusLine: some View {
        let hasData = store.fees != nil
        let isRefreshing = store.feesLoading && hasData
        let error = hasData ? store.feesError : nil
        if let fees = store.fees, fees.availability == .available {
            StatusStrip(
                lastUpdated: store.feesLastUpdated,
                isRefreshing: isRefreshing,
                error: error
            ) {
                await store.refreshFees(force: true)
            } control: {
                InlineChoice(
                    label: "Fees or payments",
                    options: FeeScope.allCases.map(\.option),
                    selection: $scope
                )
            }
        } else {
            StatusStrip(
                lastUpdated: store.feesLastUpdated,
                isRefreshing: isRefreshing,
                error: error
            ) {
                await store.refreshFees(force: true)
            }
        }
    }

    @ViewBuilder
    private func recordRows(_ records: [FeeRecord]) -> some View {
        if records.isEmpty {
            EmptyStateView(title: scope.emptyTitle, message: scope.emptyMessage)
                .padding(.horizontal, Metrics.page)
                .accessibilityIdentifier("\(scope.identifierPrefix).empty")
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                    NavigationLink {
                        FeeRecordDetailView(recordID: record.id, scope: scope)
                    } label: {
                        FeeRow(record: record, scope: scope)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("\(scope.identifierPrefix).record.\(index)")
                }
            }
            .padding(.top, 4)
        }
    }

    /// `FeeRow`'s shape: the description over its year and date, and the
    /// amount over its label at the trailing edge.
    private var loadingRows: some View {
        let descriptions = [15, 11, 18, 13, 9]
        return VStack(spacing: 0) {
            ForEach(descriptions.indices, id: \.self) { index in
                if index > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                SkeletonRow(
                    lines: [SkeletonLine(.body, descriptions[index]), SkeletonLine(.subheadline, 17)],
                    trailing: [SkeletonLine(.figure(.body), 5), SkeletonLine(.footnote, 9)]
                )
                .padding(.horizontal, Metrics.page)
            }
        }
        .padding(.top, 4)
        .loadingPlaceholder("Loading fees")
        .accessibilityIdentifier("fees.loading")
    }
}

/// Which of Skyward's two lists is shown, and how its rows are labelled.
private enum FeeScope: Hashable, CaseIterable {
    case fees, payments

    var option: ChoiceOption<FeeScope> {
        switch self {
        case .fees: ChoiceOption(value: self, title: "Fees", identifier: "fees.scope.fees")
        case .payments: ChoiceOption(value: self, title: "Payments", identifier: "fees.scope.payments")
        }
    }

    var identifierPrefix: String {
        switch self {
        case .fees: "fees"
        case .payments: "payments"
        }
    }

    /// The source column a row shows beside its description.
    var amountKey: String {
        switch self {
        case .fees: "remainingdue"
        case .payments: "paymentamount"
        }
    }

    /// Names the record's source date: a fee's due date or a payment's date.
    var datePrefix: String {
        switch self {
        case .fees: "Due"
        case .payments: "Paid"
        }
    }

    var untitled: String {
        switch self {
        case .fees: "Fee"
        case .payments: "Payment"
        }
    }

    var detailTitle: String { untitled }

    var emptyTitle: String {
        switch self {
        case .fees: "No fees"
        case .payments: "No payments"
        }
    }

    var emptyMessage: String {
        switch self {
        case .fees: "Skyward lists no fees for this account."
        case .payments: "Skyward lists no payments for this account."
        }
    }
}

/// One record as an open row: the description, its school year and date
/// beneath, and the remaining due or payment amount as posted, with its
/// label. At accessibility sizes the amount moves beneath the description.
private struct FeeRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var record: FeeRecord
    var scope: FeeScope

    private var descriptionText: String? { SourceFieldText.value(record.description) }
    private var year: String? { record.schoolYear.flatMap(SourceFieldText.value) }
    private var date: String? { record.date.flatMap(SourceFieldText.value) }
    private var amount: FeeField? {
        record.fields.first { SourceFieldText.key($0.label) == scope.amountKey }
    }

    private var spokenValue: String {
        var parts: [String] = []
        if let amount {
            parts.append("\(SourceFieldText.label(amount.label)) \(SourceFieldText.spoken(amount.value))")
        }
        if let year { parts.append("School year \(SourceFieldText.spokenSchoolYear(year))") }
        if let date { parts.append("\(scope.datePrefix) \(date)") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    details
                    if let amount {
                        LabeledValue(
                            label: SourceFieldText.label(amount.label),
                            value: SourceFieldText.shown(amount.value),
                            valueColor: SourceFieldText.value(amount.value) == nil ? Color.muted : nil
                        )
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let amount { amountColumn(amount) }
                }
            }
        }
        .padding(.horizontal, Metrics.page)
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(descriptionText ?? scope.untitled)
        .accessibilityValue(spokenValue)
        .accessibilityHint("Shows every detail")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(descriptionText ?? scope.untitled)
                .font(.body)
                .foregroundStyle(descriptionText == nil ? Color.muted : Color.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if year != nil || date != nil {
                metadata
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                if let year { metadataText(year) }
                if let date { metadataText("\(scope.datePrefix) \(date)") }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let year { metadataText(year) }
                if let date { metadataText("\(scope.datePrefix) \(date)") }
            }
        }
    }

    private func metadataText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.muted)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The posted amount over its source label, aligned to the trailing edge.
    private func amountColumn(_ field: FeeField) -> some View {
        let value = SourceFieldText.value(field.value)
        return VStack(alignment: .trailing, spacing: 3) {
            Text(value ?? "—")
                .font(.figure(.body))
                .foregroundStyle(value == nil ? Color.muted : Color.ink)
                .lineLimit(1)
            Text(SourceFieldText.label(field.label))
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .lineLimit(1)
        }
        .fixedSize()
    }
}

/// Every field of one fee or payment, in Skyward's order, read from the
/// store so a refresh is reflected and another account's record is never
/// left on screen.
private struct FeeRecordDetailView: View {
    var recordID: String
    var scope: FeeScope

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var record: FeeRecord? {
        guard let fees = store.fees else { return nil }
        return (scope == .fees ? fees.fees : fees.payments).first { $0.id == recordID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let record {
                    Text(SourceFieldText.value(record.description) ?? scope.untitled)
                        .font(.title2.bold())
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 12)

                    VStack(spacing: 0) {
                        ForEach(Array(record.fields.enumerated()), id: \.offset) { index, field in
                            if index > 0 { InsetDivider() }
                            SourceFieldLine(label: SourceFieldText.label(field.label), value: field.value)
                                .accessibilityIdentifier("\(scope.identifierPrefix).field.\(index)")
                        }
                    }
                    .padding(.top, 16)

                    Text("As posted in Skyward.")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                } else {
                    EmptyStateView(
                        title: "No longer listed",
                        message: "Skyward changed or removed this record. Go back to see the current list."
                    )
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, Metrics.page)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .softScrollEdges()
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(scope.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("\(scope.identifierPrefix).detail")
        .onChange(of: store.accountRevision) { _, _ in
            dismiss()
        }
    }
}


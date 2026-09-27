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


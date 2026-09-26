import QuickLook
import SwiftUI
import UIKit

/// Report cards and other documents Skyward keeps for the student. Rows are
/// read-only: tapping one asks the store for the file and previews it with
/// Quick Look. A document Skyward opens only on its own site says so rather
/// than offering an action.
struct DocumentsView: View {
    @Environment(AppStore.self) private var store
    @State private var showingConnect = false
    /// The document the latest open request was for, so a failure is shown
    /// on that row.
    @State private var requestedID: String?

    var body: some View {
        Group {
            if store.canShowData {
                content
            } else {
                LoginPromptView(message: "Connect your Skyward account to see report cards and documents from your school.") {
                    showingConnect = true
                }
                .softScrollEdges()
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("documents.screen")
        .sheet(isPresented: $showingConnect) { SkywardConnectSheet() }
        .sheet(item: previewBinding, onDismiss: { store.closeDocumentPreview() }) { preview in
            DocumentPreviewSheet(preview: preview)
        }
        .task(id: store.accountRevision) {
            guard store.canShowData else { return }
            await store.refreshDocuments()
        }
        .onChange(of: store.accountRevision) { _, _ in
            requestedID = nil
        }
        .onChange(of: store.documentOpenError) { _, error in
            guard let error, let reason = SourceFieldText.value(error) else { return }
            UIAccessibility.post(notification: .announcement, argument: "Couldn't open document. \(reason)")
        }
    }

    private var previewBinding: Binding<DocumentPreview?> {
        Binding(
            get: { store.documentPreview },
            set: { store.documentPreview = $0 }
        )
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip

                if let data = store.documents {
                    if data.availability == .unavailable {
                        EmptyStateView(
                            title: "Documents aren't available",
                            message: "Skyward hasn't made report cards or documents available for this account."
                        )
                        .padding(.horizontal, Metrics.page)
                        .accessibilityIdentifier("documents.unavailable")
                    } else if data.documents.isEmpty {
                        EmptyStateView(
                            title: "No documents",
                            message: "Skyward lists no report cards or documents for this account."
                        )
                        .padding(.horizontal, Metrics.page)
                        .accessibilityIdentifier("documents.empty")
                    } else {
                        documentRows(data.documents)
                    }
                } else if let error = store.documentsError {
                    InlineErrorState(title: "Couldn't load documents", message: error) {
                        await store.refreshDocuments(force: true)
                    }
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 12)
                    .accessibilityIdentifier("documents.error")
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
            await store.refreshDocuments(force: true)
        }
    }


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

    private var statusStrip: some View {
        let hasData = store.documents != nil
        return StatusStrip(
            lastUpdated: store.documentsLastUpdated,
            isRefreshing: store.documentsLoading && hasData,
            error: hasData ? store.documentsError : nil
        ) {
            await store.refreshDocuments(force: true)
        }
        .padding(.horizontal, Metrics.page)
    }

    /// The open failure, when no request is running and it hasn't been
    /// superseded by a preview.
    private var openFailure: String? {
        guard store.documentLoadingID == nil, store.documentPreview == nil,
              let error = store.documentOpenError else { return nil }
        return error
    }

    private func documentRows(_ documents: [SkywardDocument]) -> some View {
        let failure = openFailure
        let failureHasRow = documents.contains { $0.id == requestedID }
        return LazyVStack(alignment: .leading, spacing: 0) {
            if let failure, !failureHasRow {
                OpenFailureNote(error: failure)
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 4)
            }
            ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                if index > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                documentRow(document, index: index)
                if let failure, document.id == requestedID {
                    OpenFailureNote(error: failure)
                        .padding(.horizontal, Metrics.page)
                        .padding(.bottom, Metrics.rowPadding)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func documentRow(_ document: SkywardDocument, index: Int) -> some View {
        let isOpening = store.documentLoadingID == document.id
        let row = DocumentRow(document: document, isOpening: isOpening)
        if document.canOpen {
            Button {
                open(document)
            } label: {
                row
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(row.spokenTitle)
            .accessibilityValue(isOpening ? row.spokenDetails(appending: "Opening") : row.spokenDetails())
            .accessibilityHint("Opens a preview")
            .accessibilityIdentifier("documents.record.\(index)")
        } else {
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.spokenTitle)
                .accessibilityValue(row.spokenDetails(appending: "Requires Skyward"))
                .accessibilityIdentifier("documents.record.\(index)")
        }
    }

    /// One request at a time; the store owns fetching and the preview file.
    private func open(_ document: SkywardDocument) {
        guard document.canOpen, store.documentLoadingID == nil else { return }
        requestedID = document.id
        Task { await store.openDocument(document) }
    }

    /// `DocumentRow`'s shape: the title over its type and date.
    private var loadingRows: some View {
        let titles = [17, 13, 19, 11]
        return VStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { index in
                if index > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                SkeletonRow(lines: [SkeletonLine(.body, titles[index]), SkeletonLine(.subheadline, 16)])
                    .padding(.horizontal, Metrics.page)
            }
        }
        .padding(.top, 4)
        .loadingPlaceholder("Loading documents")
        .accessibilityIdentifier("documents.loading")
    }
}

/// One document as an open row: its title, then its type and date beneath.
/// The trailing edge shows progress while it opens, or that Skyward is
/// needed to view it.
private struct DocumentRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var document: SkywardDocument
    var isOpening: Bool

    private var title: String? { SourceFieldText.value(document.title) }
    private var kind: String? { document.kind.flatMap(SourceFieldText.value) }
    private var created: String? { document.created.flatMap(SourceFieldText.value) }

    var spokenTitle: String { title ?? "Untitled document" }

    func spokenDetails(appending status: String? = nil) -> String {
        var parts: [String] = []
        if let kind { parts.append(kind) }
        if let created { parts.append("Created \(created)") }
        if let status { parts.append(status) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    details
                    trailing
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    details
                        .frame(maxWidth: .infinity, alignment: .leading)
                    trailing
                }
            }
        }
        .padding(.horizontal, Metrics.page)
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(spokenTitle)
                .font(.body)
                .foregroundStyle(title == nil ? Color.muted : Color.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if kind != nil || created != nil {
                metadata
            }
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                if let kind { metadataText(kind) }
                if let created { metadataText(created) }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let kind { metadataText(kind) }
                if let created { metadataText(created) }
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

    @ViewBuilder
    private var trailing: some View {
        if isOpening {
            ProgressView()
                .accessibilityHidden(true)
        } else if !document.canOpen {
            Text("Requires Skyward")
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A failed open, stated in place. Tapping the row again retries.
private struct OpenFailureNote: View {
    var error: String

    private var message: String {
        let reason = error
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let lead = "Couldn't open this document."
        return reason.isEmpty ? "\(lead) Tap it to try again." : "\(lead) \(reason). Tap it to try again."
    }


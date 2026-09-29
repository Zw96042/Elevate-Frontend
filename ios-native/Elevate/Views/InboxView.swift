import SwiftUI

struct InboxView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var showingConnect = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.canShowData {
                    LoginPromptView(message: "Connect your Skyward account to read messages from teachers and your school.") {
                        showingConnect = true
                    }
                } else if let error = store.messagesError, store.messages.isEmpty {
                    ErrorStateView(title: "Couldn't load messages", message: error) {
                        await store.refreshMessages(force: true)
                    }
                } else {
                    messageList
                }
            }
            .screenTitle("Inbox") { router.isShowingSettings = true }
            .background(Color.appBackground.ignoresSafeArea())
            .accessibilityIdentifier("inbox.screen")
            .sheet(isPresented: $showingConnect) { SkywardConnectSheet() }
            .task {
                if store.messages.isEmpty {
                    await store.refreshMessages()
                }
            }
        }
    }

    private var statusStrip: some View {
        StatusStrip(
            lastUpdated: store.messagesLastUpdated,
            isRefreshing: store.messagesRefreshing,
            error: store.messages.isEmpty ? nil : store.messagesError
        ) {
            await store.refreshMessages(force: true)
        }
        .padding(.horizontal, Metrics.page)
    }

    /// There are no messages and this isn't the first load. A later refresh
    /// of a verified empty inbox keeps the empty state on screen.
    private var isValidEmpty: Bool {
        store.messages.isEmpty && !(store.messagesLoading && store.messagesLastUpdated == nil)
    }

    private var messageList: some View {
        GeometryReader { viewport in
            ScrollView {
                if isValidEmpty {
                    // The empty state takes the rest of the visible screen
                    // and centers in it.
                    ViewportFillStack(minHeight: max(0, viewport.size.height - 16), maxGrowth: .infinity) {
                        statusStrip
                        InboxEmptyState()
                            .frame(maxHeight: .infinity)
                            .fillsViewport()
                    }
                    .padding(.bottom, 16)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        statusStrip

                        messageRows

                        if store.messagesLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.vertical, 8)
                                .accessibilityLabel("Loading older messages")
                        } else if let error = store.messagesPaginationError {
                            InsetDivider(leading: Metrics.page)
                            paginationError(error)
                                .padding(.horizontal, Metrics.page)
                        }
                    }
                    if store.messagesLoadingMore {
                        ProgressView().padding()
                    } else if let error = store.messagesPaginationError {
                        VStack(spacing: 8) {
                            Text("Couldn't load older messages")
                                .font(.subheadline.weight(.semibold))
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Try again") {
                                Task { await store.loadMoreMessages() }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .refreshable {
            await store.refreshMessages(force: true)
        }
        .background(Color.appBackground)
    }
}

struct MessageCardView: View {
    var message: SkywardMessage

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.subject)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                metadata
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if !message.isAdministrator {
                    Text(message.from)
                        .fixedSize(horizontal: true, vertical: false)
                    if !message.className.isEmpty {
                        Text(message.className)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Text(message.date)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 2) {
                if !message.isAdministrator {
                    Text(message.from)
                    if !message.className.isEmpty {
                        Text(message.className)
                    }
                }
                Text(message.date)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MessageDetailView: View {
    var message: SkywardMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.subject)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message.from)
                        .font(.body.weight(.medium))
                    if !message.className.isEmpty {
                        Text(message.className)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(message.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                    .padding(.vertical, 14)
                Text(renderedContent)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .background(Color.appBackground)
    }

    /// The scraper produces lightweight markdown (links + bold); render it natively.
    private var renderedContent: AttributedString {
        let raw = message.content.replacingOccurrences(of: "\\n", with: "\n")
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(raw)
    }

}

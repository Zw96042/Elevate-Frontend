import SwiftUI

struct RowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Login prompt / error states

struct LoginPromptView: View {
    var message: String
    var onLogin: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 34, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.highlightText)
                        .frame(width: 68, height: 68)
                        .background(Color.ringHighlight, in: Circle())
                    VStack(spacing: 8) {
                        Text("Connect Skyward")
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(message)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: onLogin) {
                        Label("Open settings", systemImage: "gearshape")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(Color.prominentFill, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(RowPressStyle())
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct ErrorStateView: View {
    var title: String
    var message: String
    var onRetry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 38, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                        .frame(width: 80, height: 80)
                        .background(.red.opacity(0.1), in: Circle())
                    Text(title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task {
                            guard !isRetrying else { return }
                            isRetrying = true
                            await onRetry()
                            isRetrying = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isRetrying {
                                ProgressView()
                                    .accessibilityHidden(true)
                            }
                            Text(isRetrying ? "Trying again…" : "Try again")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(Color.prominentFill)
                    .disabled(isRetrying)
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct StaleDataBanner: View {
    var lastUpdated: Date?
    var onRetry: () async -> Void

    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Showing saved data", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(updateDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(isRetrying ? "Trying again…" : "Try again") {
                Task {
                    guard !isRetrying else { return }
                    isRetrying = true
                    await onRetry()
                    isRetrying = false
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .disabled(isRetrying)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var updateDescription: String {
        guard let lastUpdated else {
            return "Skyward couldn't refresh. The last successful update time isn't available."
        }
        return "Skyward couldn't refresh. Last updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))."
    }
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.highlightText)
                .frame(width: 64, height: 64)
                .background(Color.ringHighlight, in: Circle())
            Text(title)
                .font(.headline)
                .padding(.top, 6)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
    }
}

// MARK: - Skeleton shimmer

struct SkeletonRow: View {
    var height: CGFloat = 76

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Color.skeletonFill).frame(width: 152, height: 14)
                Capsule().fill(Color.skeletonFill.opacity(0.65)).frame(width: 104, height: 10)
            }
            Spacer()
            Capsule().fill(Color.skeletonFill.opacity(0.75)).frame(width: 42, height: 18)
        }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Term picker pill

struct TermPickerPill: View {
    @Binding var selectedTerm: TermLabel
    var label = "Grading term"
    var compact = false
    var showsDescriptor = true

    @State private var showingTerms = false
    @State private var triggerWidth: CGFloat = 320

    var body: some View {
        Button {
            showingTerms = true
        } label: {
            labelContent
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { triggerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        triggerWidth = width
                    }
            }
        }
        .popover(
            isPresented: $showingTerms,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            termChoices
                .frame(width: max(triggerWidth, 280))
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Grading term, \(selectedTerm.rawValue)")
        .accessibilityHint("Shows available grading terms")
    }

    private var termChoices: some View {
        VStack(spacing: 0) {
            termSection("Fall", terms: [.q1, .q2, .sm1])
            Divider()
                .padding(.horizontal, 16)
            termSection("Spring", terms: [.q3, .q4, .sm2])
        }
        .padding(.vertical, 8)
    }

    private func termSection(_ title: String, terms: [TermLabel]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(height: 30)

            ForEach(terms) { term in
                Button {
                    selectedTerm = term
                    showingTerms = false
                } label: {
                    HStack(spacing: 12) {
                        Text(term.rawValue)
                            .foregroundStyle(.primary)
                        Spacer()
                        if term == selectedTerm {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.themeAccent)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityAddTraits(term == selectedTerm ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var labelContent: some View {
        if !showsDescriptor {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.themeAccent)
                Text(selectedTerm.rawValue)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        } else if compact {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.themeAccent)
                Text(selectedTerm.shortName)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.themeAccent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selectedTerm.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
    }

}

// MARK: - Grade progress

struct GradeProgressRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var score: Double?
    var size: CGFloat = 44

    private var progress: Double {
        min(max((score ?? 0) / 100, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ringHighlight, lineWidth: 4)

            if score != nil {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.themeAccent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: progress)
            }

            Text(score.map { String(format: "%.0f", $0) } ?? "--")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(score == nil ? Color.secondary : Color.highlightText)
                .contentTransition(.numericText(value: score ?? 0))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

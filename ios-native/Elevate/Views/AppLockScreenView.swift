import SwiftUI

/// What stands in for Elevate while it's locked, or while its content is
/// covered in the app switcher: Elevate's mark on a frosted veil and, when
/// locked, a short label and one Unlock button. iOS presents Face ID, Touch ID,
/// or the passcode; nothing here takes a code or shows school data. The window
/// holding this cover, anything drawn behind it, and when it appears belong to
/// `AppLockStore`'s owner.
struct AppLockScreenView: View {
    var store: AppLockStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var theme = ThemeManager.shared
    /// Covers the moment between the tap and the store's own busy state.
    @State private var isStarting = false
    @AccessibilityFocusState private var errorFocused: Bool

    private var isBusy: Bool { store.isAuthenticating || isStarting }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    mark
                    if store.isLocked {
                        lockedContent
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 32)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { backdrop.ignoresSafeArea() }
        .foregroundStyle(Color.ink)
        .tint(Color.themeAccent)
        .preferredColorScheme(theme.appearance.colorScheme)
        .animation(Motion.replace(reduceMotion), value: store.isLocked)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appLock.screen")
        .onChange(of: store.error) { _, error in
            if error != nil { errorFocused = true }
        }
    }

    /// Frosts the coarse, already-blurred colors the cover's window draws
    /// behind this view under the thinnest glass, so those colors show
    /// through. A trace of the theme's page and one faint wash of the action
    /// color from the top keep it the app's own without covering what's
    /// behind. Increased Contrast gets a denser page under thick glass and no
    /// wash; Reduce Transparency gets the solid page.
    @ViewBuilder private var backdrop: some View {
        if reduceTransparency {
            Color.appBackground
        } else if contrast == .increased {
            ZStack {
                Color.appBackground.opacity(0.6)
                Rectangle().fill(Material.thickMaterial)
            }
        } else {
            let light = colorScheme == .dark ? 0.12 : 0.1
            ZStack {
                Color.appBackground.opacity(0.1)
                EllipticalGradient(
                    stops: [
                        .init(color: Color.themeAccent.opacity(light), location: 0),
                        .init(color: Color.themeAccent.opacity(0), location: 1),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.1),
                    endRadiusFraction: 0.8
                )
                Rectangle().fill(Material.ultraThinMaterial)
            }
        }
    }

    /// Elevate's E on its own, in the theme's action color. Decorative beside
    /// the title, which names the app; on a bare cover it names the app itself.
    private var mark: some View {
        Image("ElevateMark")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 60 : 72)
            .foregroundStyle(Color.themeAccent)
            .accessibilityLabel("Elevate")
            .accessibilityHidden(store.isLocked)
    }

    private var lockedContent: some View {
        VStack(spacing: 32) {
            VStack(spacing: 6) {
                Text("Elevate is locked")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("appLock.title")
                Text("Use \(AppLockCopy.method(for: store)) to open it.")
                    .font(.body)
                    .foregroundStyle(Color.muted)
                if let error = store.error {
                    errorMessage(error)
                        .padding(.top, 10)
                        .transition(.opacity)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            unlockButton
        }
        .animation(Motion.replace(reduceMotion), value: store.error)
    }

    /// The store's message, centered under the instruction with its symbol
    /// inline so a wrapped line stays balanced.
    private func errorMessage(_ error: String) -> some View {
        let symbol = Text(Image(systemName: "exclamationmark.circle"))
            .foregroundStyle(Color.gradeAttention)
        return Text("\(symbol) \(error)")
            .font(.subheadline)
            .foregroundStyle(Color.ink)
            .accessibilityLabel(error)
            .accessibilityFocused($errorFocused)
            .accessibilityIdentifier("appLock.error")
    }

    /// Unlock, or Try again after a failure; the same request either way.
    /// Sized for its label rather than the page, until text is large enough
    /// to need the full width.
    private var unlockButton: some View {
        let title = store.error == nil ? "Unlock" : "Try again"
        return Button(action: unlock) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: store.authenticationSymbol)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 220)
        .disabled(isBusy)
        .accessibilityLabel("\(title) with \(store.authenticationName)")
        .accessibilityValue(isBusy ? "Waiting for \(store.authenticationName)" : "")
        .accessibilityIdentifier("appLock.unlock")
    }

    private func unlock() {
        guard !isBusy else { return }
        isStarting = true
        store.clearError()
        Task {
            _ = await store.unlock()
            isStarting = false
        }
    }
}

/// How the app lock's check reads in a sentence: "Face ID or your passcode",
/// or "your passcode" alone on an iPhone without Face ID or Touch ID.
enum AppLockCopy {
    @MainActor static func method(for store: AppLockStore) -> String {
        let name = store.authenticationName
        if name.isEmpty || name.localizedCaseInsensitiveContains("passcode") {
            return "your passcode"
        }
        return "\(name) or your passcode"
    }
}

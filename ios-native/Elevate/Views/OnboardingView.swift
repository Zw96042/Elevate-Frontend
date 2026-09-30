import SwiftUI
import UIKit

/// Versioned tour completion, independent of account data. Existing students
/// see the expanded tour once even if they completed an earlier introduction;
/// v3 adds widgets, notifications, and Elevate's own app lock. Connected
/// students finish with Skip or Continue; other students finish with Not now
/// or a verified sign-in.
enum OnboardingState {
    static let completedKey = "elevate.onboarding.completed.v3"
}

/// A short introduction (grades and what-if, GPA, credits, the week,
/// widgets, notifications, the private direct connection, a theme, and an
/// optional app lock) followed by Skyward sign-in, pushed in the same flow
/// with the shared `SkywardAccountView`. The presenter decides whether
/// finishing persists anything; a theme chosen here is saved by
/// `ThemeManager` exactly as in Settings. Notification permission and the
/// app lock change only on an explicit tap, never on a page appearing.
struct OnboardingView: View {
    enum Mode {
        /// Shown once per tour version, including people already signed in.
        case firstRun
        /// DEBUG `-ShowOnboarding`: preview that does not record completion.
        case preview
    }

    private enum Stage: Hashable {
        case signIn
    }

    /// The pages in order. Each raw value names the page's accessibility
    /// identifier, `onboarding.page.<rawValue>`.
    private enum Page: String, CaseIterable {
        case grades, whatIf, gpa, plan, week, widgets, notifications, connection, theme, appLock
    }

    var mode: Mode
    var onFinish: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var themeManager = ThemeManager.shared
    @State private var page = 0
    @State private var path: [Stage] = []

    /// Every page on every supported iOS; the app lock is Elevate's own.
    private static let pages: [Page] = Page.allCases

    /// Adding a widget starts from Edit in iOS 18 and later, from + in iOS 17.
    private static let widgetSteps: [LocalizedStringKey] = {
        let open: LocalizedStringKey
        if #available(iOS 18, *) {
            open = "Touch and hold an empty area of your Home Screen, then tap **Edit** and **Add Widget**."
        } else {
            open = "Touch and hold an empty area of your Home Screen, then tap **+** in the top corner."
        }
        return [open, "Search for **Elevate** and choose a widget."]
    }()

    private var pageCount: Int { Self.pages.count }
    private var isLastPage: Bool { page == pageCount - 1 }

    var body: some View {
        NavigationStack(path: $path) {
            introduction
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Stage.self) { stage in
                    switch stage {
                    case .signIn:
                        // Finishes only after a verified save; a failed or
                        // cancelled attempt stays here with its error.
                        SkywardAccountView(onConnected: onFinish, onSkip: onFinish)
                            .toolbar(.visible, for: .navigationBar)
                    }
                }
        }
    }

    private var introduction: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $page) {
                ForEach(Array(Self.pages.enumerated()), id: \.element) { index, item in
                    pageView(item, isActive: page == index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sensoryFeedback(.selection, trigger: page)


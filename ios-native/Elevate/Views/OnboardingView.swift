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

            bottomControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .foregroundStyle(Color.ink)
    }

    // MARK: - Pages

    @ViewBuilder
    private func pageView(_ item: Page, isActive: Bool) -> some View {
        switch item {
        case .grades:
            OnboardingPage(
                id: item.rawValue,
                title: "Your grades, first.",
                message: "Elevate opens on your classes and this term's grades, with your GPA one line above them. Each class holds its assignments and category weights, and Inbox holds messages from your teachers and school."
            ) {
                GradesArt(isActive: isActive)
            }

        case .whatIf:
            OnboardingPage(
                id: item.rawValue,
                title: "Try a score.",
                message: "Change any score or add an assignment to preview your grade, and save what you try as a scenario. A grade goal shows the score a new assignment or the exam would need.",
                note: "What-if work stays on this iPhone and never changes Skyward."
            ) {
                WhatIfArt(isActive: isActive)
            }

        case .gpa:
            OnboardingPage(
                id: item.rawValue,
                title: "GPA, over time.",
                message: "Follow your weighted and unweighted GPA term by term, with its trend. The GPA converter puts completed semesters on 4.0 and 5.0 scales.",
                note: "Converter results are estimates, not any college's official GPA."
            ) {
                GPAArt(isActive: isActive)
            }

        case .plan:
            OnboardingPage(
                id: item.rawValue,
                title: "Credits and plans.",
                message: "Course plan estimates earned credits from completed semester grades. Current classes appear separately as expected credits if passed. Find earlier grades in Past courses and school files in Documents, both in Settings.",
                note: "Plans stay on this iPhone. They aren't an official transcript or graduation check."
            ) {
                PlanArt(isActive: isActive)
            }

        case .week:
            OnboardingPage(
                id: item.rawValue,
                title: "Your week.",
                message: "Calendar shows the school calendar, attendance, and assignments by due date. This week lists today and the next six days, so you can check off work as you finish it.",
                note: "Done marks stay on this iPhone and can be undone. They don't change Skyward, and Missing stays until your teacher clears it."
            ) {
                WeekArt(isActive: isActive)
            }

        case .widgets:
            OnboardingPage(
                id: item.rawValue,
                title: "On your Home Screen.",
                message: "Widgets keep missing work and new messages in view. Missing Work and Inbox show no grades; GPA and grade widgets are there if you want them.",
                steps: Self.widgetSteps
            ) {
                WidgetsArt(isActive: isActive)
            }

        case .notifications:
            NotificationsPage(isActive: isActive)

        case .connection:
            OnboardingPage(
                id: item.rawValue,
                title: "Straight to Skyward.",
                message: "Elevate signs in to \(CredentialStore.districtName) Skyward directly from this iPhone. Your login is stored in the iOS Keychain and used only to connect to Skyward."
            ) {
                ConnectionArt(isActive: isActive)
            }

        case .theme:
            ThemePage(palette: paletteChoice, appearance: appearanceChoice)

        case .appLock:
            // Optional: Continue works the same whether or not it's turned on.
            AppLockPage(isActive: isActive)
        }
    }

    /// The shared theme, changed the way Settings changes it. Nothing is
    /// chosen for the person: the page opens on the current theme, and
    /// leaving it untouched keeps that theme.
    private var paletteChoice: Binding<ColorPalette> {
        Binding(
            get: { themeManager.palette },
            set: { palette in updateTheme { themeManager.palette = palette } }
        )
    }

    private var appearanceChoice: Binding<AppearanceMode> {
        Binding(
            get: { themeManager.appearance },
            set: { appearance in updateTheme { themeManager.appearance = appearance } }
        )
    }

    private func updateTheme(_ change: () -> Void) {
        Motion.perform(reduceMotion ? nil : .easeInOut(duration: 0.25), change)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Text("Elevate")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // Connected students can finish without signing in again. Other
            // students skip to sign-in; the preview can always close.
            if mode == .preview || !isLastPage {
                Button {
                    if mode == .firstRun && !store.hasCredentials {
                        showSignIn()
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(mode == .firstRun ? "Skip" : "Close")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.body.weight(.medium))
                .foregroundStyle(Color.muted)
                .accessibilityHint(mode == .firstRun
                    ? (store.hasCredentials ? "Finishes the introduction and opens Elevate." : "Skips the introduction and goes to Skyward sign-in.")
                    : "")
                .accessibilityIdentifier("onboarding.skip")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .frame(minHeight: 52)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isLastPage)
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            StepIndicator(count: pageCount, current: page)
                .padding(.bottom, 10)

            primaryButton

            Group {
                if isLastPage && store.hasCredentials {
                    Label("Connected to \(CredentialStore.districtName)", systemImage: "checkmark")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.muted)
                } else {
                    // Holds the secondary row's height so Continue stays put
                    // between pages. Must not be greedy (a bare Color.clear
                    // would take free height away from the pager). Not now
                    // lives on the sign-in stage.
                    Text("Not now")
                        .font(.body.weight(.semibold))
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if !isLastPage {
            Button {
                advance()
            } label: {
                Text("Continue")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("onboarding.next")
        } else if store.hasCredentials {
            Button {
                onFinish()
            } label: {
                Text("Continue")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("onboarding.done")
        } else {
            Button {
                showSignIn()
            } label: {
                Text("Continue")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint("Sign in to \(CredentialStore.districtName) Skyward.")
            .accessibilityIdentifier("onboarding.connect")
        }
    }

    private func showSignIn() {
        guard path.isEmpty else { return }
        path = [.signIn]
    }

    private func advance() {
        guard page < pageCount - 1 else { return }
        if reduceMotion {
            page += 1
        } else {
            withAnimation(.smooth(duration: 0.4)) { page += 1 }
        }
    }
}

// MARK: - Page layout

/// A page's title and message, read as one element.
private struct PageHeading: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingPage<Art: View, Action: View>: View {
    var id: String
    var title: String
    var message: String
    /// Numbered instructions under the message, set in ink so they read as
    /// the thing to do.
    var steps: [LocalizedStringKey]
    /// A quiet footnote after the message, steps, and any action.
    var note: String?
    /// An optional choice made on the page itself, after the steps. Its
    /// state belongs to the caller, since the page may lay out twice.
    var action: Action
    var art: Art

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        id: String,
        title: String,
        message: String,
        steps: [LocalizedStringKey] = [],
        note: String? = nil,
        @ViewBuilder action: () -> Action,
        @ViewBuilder art: () -> Art
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.steps = steps
        self.note = note
        self.action = action()
        self.art = art()
    }

    var body: some View {
        // The copy always wins: art is shown only when art and copy fit the
        // page together. Otherwise the copy stands alone, scrolling only if
        // even that overflows.
        ViewThatFits(in: .vertical) {
            if !dynamicTypeSize.isAccessibilitySize {
                content(showsArt: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            GeometryReader { proxy in
                ScrollView {
                    content(showsArt: false)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .softScrollEdges()
            }
        }
        // A container, so the page's identifier doesn't replace the
        // identifiers of the steps inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.page.\(id)")
    }

    private func content(showsArt: Bool) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            if showsArt {
                // Decorative; the text below carries the meaning.
                art
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: title, message: message)

                if !steps.isEmpty {
                    stepList
                }

                action

                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    /// One element per step, read with its number.
    private var stepList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { offset, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(offset + 1)")
                        .font(.figure(.body, weight: .semibold))
                        .foregroundStyle(Color.themeAccent)
                    Text(step)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onboarding.page.\(id).step.\(offset + 1)")
            }
        }
    }
}

extension OnboardingPage where Action == EmptyView {
    init(
        id: String,
        title: String,
        message: String,
        steps: [LocalizedStringKey] = [],
        note: String? = nil,
        @ViewBuilder art: () -> Art
    ) {
        self.init(id: id, title: title, message: message, steps: steps, note: note,
                  action: { EmptyView() }, art: art)
    }
}

/// The theme page: the same built-in themes and display choices as
/// Settings > Theme, opening on the current ones. The whole introduction
/// redraws in a theme as it is chosen, which is the preview. A color of the
/// person's own stays in Settings.
private struct ThemePage: View {
    @Binding var palette: ColorPalette
    @Binding var appearance: AppearanceMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeading(
                    title: "Choose a look.",
                    message: "Elevate changes as you tap, and your choice is saved. To keep the current look, just continue. Theme in Settings has these choices too, and your own color."
                )
                ThemeChoices(palette: $palette, appearance: $appearance, offersCustomColor: false)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.page.theme")
        }
        .scrollBounceBehavior(.basedOnSize)
        .softScrollEdges()
    }
}

/// Connected segments, one per page; steps up to the current one are filled.
/// Short segments keep ten pages narrower than the smallest phone's margins.
private struct StepIndicator: View {
    var count: Int
    var current: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                Rectangle()
                    .fill(index <= current ? Color.ink : Color.rule)
                    .frame(width: 18, height: 4)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// Frame for illustrative art: the same open composition and type as the
/// app, with an "Example data" caption beneath it so the figures are never
/// mistaken for real grades.
private struct ArtFrame<Content: View>: View {
    var showsExampleLabel = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
            if showsExampleLabel {
                Text("Example data")
                    .font(.caption)
                    .foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plays a one-time entrance when its page first becomes active. With
/// Reduce Motion the content is simply there.
private struct ArtEntrance: ViewModifier {
    var isVisible: Bool
    var order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shown = isVisible || reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.45).delay(Double(order) * 0.06),
                value: isVisible
            )
    }
}

/// Marks an art's page as seen so its entrance plays once.
private struct PlaysOnce: ViewModifier {
    var isActive: Bool
    @Binding var hasPlayed: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { if isActive { hasPlayed = true } }
            .onChange(of: isActive) { _, active in if active { hasPlayed = true } }
    }
}

// MARK: - Art: grades

private struct GradesArt: View {
    var isActive: Bool
    @State private var hasPlayed = false

    private let rows: [(period: Int, name: String, teacher: String, grade: Double)] = [
        (1, "Biology H", "Rivera", 94),
        (2, "English 2", "Okafor", 88),
        (3, "Algebra II", "Lin", 91),
    ]

    /// Averages of the three rows above, the way the GPA screen computes
    /// them: Biology H earns the Honors 5 in the weighted figure.
    private let weightedGPA = "92.67"
    private let unweightedGPA = "91.00"

    var body: some View {
        ArtFrame {
            VStack(alignment: .leading, spacing: 0) {
                // The control line.
                HStack(alignment: .center, spacing: 6) {
                    // The closed scope button, as `ScopeButtonLabel` on the
                    // quiet well.
                    ScopeButtonLabel(value: "Quarter 1")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.well, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
                    Spacer(minLength: 8)
                    Text("Updated 8:02 AM")
                        .font(.caption)
                        .foregroundStyle(Color.muted)
                }
                .padding(.bottom, 10)
                .modifier(ArtEntrance(isVisible: hasPlayed, order: 0))


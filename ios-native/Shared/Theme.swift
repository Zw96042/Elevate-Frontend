import SwiftUI
import WidgetKit

// MARK: - App group (shared between the app and the widget extension)

enum AppGroup {
    static let identifier = "group.com.zacharywilson.elevate"
    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: identifier) else {
            preconditionFailure("Elevate app-group storage is unavailable")
        }
        return defaults
    }()
}

// MARK: - Appearance override

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Themes
//
// A theme is a composed set rather than an accent swap. Each one names every
// role separately for light and for dark: the page, text, secondary text,
// hairlines, the action color for links and toggles, the fill behind primary
// buttons, selected and pressed fills, the GPA line and the strength of the
// wash below it, and the attention and warning colors tuned to that page.
//
// The themes differ in structure as well as hue. Some fill buttons with the
// action color and some with ink; the dark pages are each their own night
// (navy, graphite, indigo, warm graphite, spruce, wine) rather than one
// black. Tinted pages and ink carry each theme through the content. Attention is
// always a red set apart from the theme's action color, and warning is an
// amber, ochre, or olive set apart from both, so neither the accent nor the
// chart ever reads as a grade signal.
//
// Every theme keeps the same layout, type, and navigation; only color moves.
// Targets, on the page and on the well and selection fills: text at least
// 12:1 on the page, secondary, action, attention, and warning text at least
// 4.5:1, the GPA line at least 3:1 on the page, hairlines about 1.25:1, and
// button labels at least 4.5:1 on the fill, including the pressed fill at
// 78% opacity.
//
// Theme IDs are persisted and shared with the widget, so they must never
// change.

struct ColorPalette: Identifiable, Hashable {
    /// The colors of one theme in one appearance.
    struct Tones: Hashable {
        /// The page every screen is set on.
        var background: UInt32
        var ink: UInt32
        /// Secondary text and metadata.
        var muted: UInt32
        /// Separators and the lines of the few relation tables.
        var hairline: UInt32
        /// Links, toggles, checkmarks, and what-if markers.
        var action: UInt32
        /// Fill behind the one primary button on a screen.
        var buttonFill: UInt32
        var onButton: UInt32
        /// Fill behind a chosen option.
        var selection: UInt32
        /// Fill behind a row while it is pressed, and behind input wells.
        var pressed: UInt32
        var chartLine: UInt32
        /// Opacity of the chart color at the top of the wash below the line.
        var chartFill: Double
        /// Below-passing grades and failures.
        var attention: UInt32
        /// Absences and soft warnings.
        var warning: UInt32
    }

    let id: String
    let name: String
    /// One sentence describing how the theme is composed.
    let summary: String
    let light: Tones
    let dark: Tones
    var rawAccent: UInt32? = nil

    /// The light-mode action color. Persisted for custom themes.
    var accent: UInt32 { light.action }

    /// Cool white and navy ink, with cobalt actions and a brighter GPA line.
    /// At night the page becomes navy, with deep blue buttons and white labels.
    static let classicBlue = ColorPalette(
        id: "classicBlue", name: "Classic",
        summary: "Navy ink and cobalt on cool white, like a printed report card.",
        light: Tones(
            background: 0xF2F6FD, ink: 0x0E1A30, muted: 0x4C5B75, hairline: 0xD6DEEB,
            action: 0x1F57D1, buttonFill: 0x163A8C, onButton: 0xFFFFFF,
            selection: 0xD9E5FA, pressed: 0xE5ECF8,
            chartLine: 0x2A62E0, chartFill: 0.14,
            attention: 0xB42318, warning: 0x8F5200
        ),
        dark: Tones(
            background: 0x0E1A33, ink: 0xEAF0FA, muted: 0x9DADC9, hairline: 0x213052,
            action: 0x6AA2FF, buttonFill: 0x2654C8, onButton: 0xFFFFFF,
            selection: 0x1C2F55, pressed: 0x172644,
            chartLine: 0x74AAFF, chartFill: 0.24,
            attention: 0xFF8A80, warning: 0xF2B65C
        )
    )

    /// Pure white and black ink by day; graphite and soft white at night.
    /// The monochrome roles leave color to attention and warning signals.
    static let graphite = ColorPalette(
        id: "graphite", name: "Lab",
        summary: "Black on white, with color saved for grades that need it.",
        light: Tones(
            background: 0xFFFFFF, ink: 0x0A0A0B, muted: 0x5B5B60, hairline: 0xE2E2E5,
            action: 0x0A0A0B, buttonFill: 0x0A0A0B, onButton: 0xFFFFFF,
            selection: 0xEAEAED, pressed: 0xF1F1F3,
            chartLine: 0x0A0A0B, chartFill: 0.06,
            attention: 0xC8102E, warning: 0x8A5A00
        ),
        dark: Tones(
            background: 0x1C1C1E, ink: 0xF2F2F4, muted: 0x9C9CA2, hairline: 0x313135,
            action: 0xBDBDC3, buttonFill: 0xF2F2F4, onButton: 0x1C1C1E,
            selection: 0x2E2E32, pressed: 0x262629,
            chartLine: 0xF2F2F4, chartFill: 0.10,
            attention: 0xFF7272, warning: 0xE3AB40
        )
    )

    /// Lilac with aubergine ink by day, deep indigo with orchid marks
    /// at night. Indigo buttons stay saturated in both appearances.
    static let violet = ColorPalette(
        id: "violet", name: "Dusk",
        summary: "Lilac by day, deep indigo with an orchid glow by night.",
        light: Tones(
            background: 0xF0ECFB, ink: 0x1F1838, muted: 0x5A5380, hairline: 0xD9D1EC,
            action: 0x5536CC, buttonFill: 0x3B2799, onButton: 0xFFFFFF,
            selection: 0xDCD2F6, pressed: 0xE5DFF5,
            chartLine: 0x8A3FD1, chartFill: 0.20,
            attention: 0xA8221B, warning: 0x7D4B00
        ),
        dark: Tones(
            background: 0x1A1433, ink: 0xEEEAFB, muted: 0xA9A1D0, hairline: 0x2C2550,
            action: 0xA88EFF, buttonFill: 0x5B3BD6, onButton: 0xFFFFFF,
            selection: 0x2F2560, pressed: 0x241D45,
            chartLine: 0xC9A0FF, chartFill: 0.32,
            attention: 0xFF8E7E, warning: 0xF4C066
        )
    )

    /// Ivory stationery with sepia ink and a claret pen. At night a warm
    /// graphite page holds parchment buttons and plum marks.
    static let rose = ColorPalette(
        id: "rose", name: "Paper",
        summary: "Ivory stationery, sepia ink, and a claret pen.",
        light: Tones(
            background: 0xFAF5E8, ink: 0x2A1E18, muted: 0x6B5A4E, hairline: 0xE5DAC6,
            action: 0x861E4E, buttonFill: 0x2A1E18, onButton: 0xFAF5E8,
            selection: 0xF1DCE2, pressed: 0xEFE7D6,
            chartLine: 0x9C2A5C, chartFill: 0.12,
            attention: 0xAC3508, warning: 0x735C00
        ),
        dark: Tones(
            background: 0x22201D, ink: 0xF4ECDF, muted: 0xB5A794, hairline: 0x34302B,
            action: 0xE68AAE, buttonFill: 0xF4ECDF, onButton: 0x22201D,
            selection: 0x3A2A2E, pressed: 0x2C2925,
            chartLine: 0xEA92B4, chartFill: 0.18,
            attention: 0xFF9466, warning: 0xD9C46A
        )
    )

    /// Sage-mint with spruce ink and teal actions. At night a deep spruce
    /// page keeps the same calm hue, with saturated teal buttons.
    static let forest = ColorPalette(
        id: "forest", name: "Field",
        summary: "Sage and spruce, calm for long reads.",
        light: Tones(
            background: 0xE9F3EE, ink: 0x11221D, muted: 0x4C6059, hairline: 0xCEDDD5,
            action: 0x106456, buttonFill: 0x0C4A3F, onButton: 0xFFFFFF,
            selection: 0xCFE5DB, pressed: 0xDDEAE4,
            chartLine: 0x18806B, chartFill: 0.14,
            attention: 0xB3261E, warning: 0x8A4B00
        ),
        dark: Tones(
            background: 0x0F211D, ink: 0xE5F0EB, muted: 0x9DB5AC, hairline: 0x1F332D,
            action: 0x4DBFAE, buttonFill: 0x12665A, onButton: 0xFFFFFF,
            selection: 0x1A352E, pressed: 0x172C27,
            chartLine: 0x5CCFB8, chartFill: 0.22,
            attention: 0xFF8A7A, warning: 0xEDB466
        )
    )

    /// Apricot clay with red-brown ink by day. Ember orange sits on a
    /// wine-dark page at night; crimson attention remains distinct.
    static let sunset = ColorPalette(
        id: "sunset", name: "Ember",
        summary: "Apricot clay by day, ember orange on a wine-dark night.",
        light: Tones(
            background: 0xFCEEE4, ink: 0x2B1710, muted: 0x6B5142, hairline: 0xEBD5C6,
            action: 0x9E390C, buttonFill: 0x7A2A08, onButton: 0xFFFFFF,
            selection: 0xF5D5C2, pressed: 0xF3DFD2,
            chartLine: 0xC2531A, chartFill: 0.18,
            attention: 0xA8123C, warning: 0x5E5A00
        ),
        dark: Tones(
            background: 0x22131A, ink: 0xF9ECE6, muted: 0xC2A39C, hairline: 0x3A2229,
            action: 0xFF8F4F, buttonFill: 0xA33C0C, onButton: 0xFFFFFF,
            selection: 0x3E2420, pressed: 0x2E1C24,
            chartLine: 0xFF9A55, chartFill: 0.28,
            attention: 0xFF7D95, warning: 0xD4CB6A
        )
    )

    static let all: [ColorPalette] = [.classicBlue, .graphite, .violet, .rose, .forest, .sunset]

    /// A neutral stone base, neither warm nor cool, so any color sits on it.
    /// The person's color is used for links and the GPA line, deepened when
    /// needed so it stays readable on the page, the well, and the selection,
    /// and a step deeper again for button fills. At night a soft charcoal
    /// with the color lifted.
    static func custom(_ accent: UInt32) -> ColorPalette {
        let lightAction = accessibleLightAccent(accent)
        let darkAction = accessibleDarkAccent(accent)
        let lightButton = darkened(lightAction, toLuminance: 0.075)
        return ColorPalette(
            id: "custom", name: "Custom",
            summary: "A neutral base around your color.",
            light: Tones(
                background: 0xF6F6F4, ink: 0x161618, muted: 0x5E5E62, hairline: 0xDCDCD8,
                action: lightAction, buttonFill: lightButton, onButton: 0xFFFFFF,
                selection: blend(0xF6F6F4, with: lightAction, amount: 0.12), pressed: 0xEBEBE8,
                chartLine: lightAction, chartFill: 0.16,
                attention: 0xB3261E, warning: 0x855000
            ),
            dark: Tones(
                background: 0x19191C, ink: 0xF1F1EF, muted: 0xA3A3A8, hairline: 0x2E2E32,
                action: darkAction, buttonFill: darkAction, onButton: 0x19191C,
                selection: blend(0x19191C, with: darkAction, amount: 0.14), pressed: 0x232327,
                chartLine: darkAction, chartFill: 0.26,
                attention: 0xFF8C80, warning: 0xF0B860
            ),
            rawAccent: accent
        )
    }

    static func named(_ id: String?) -> ColorPalette {
        all.first { $0.id == id } ?? .classicBlue
    }

    // MARK: Derived tones

    /// Non-text glyphs such as disclosure chevrons.
    var faintLight: UInt32 { Self.blend(light.ink, with: light.background, amount: 0.55) }
    var faintDark: UInt32 { Self.blend(dark.ink, with: dark.background, amount: 0.55) }

    // MARK: Color math

    /// Deepened until it reads at 4.5:1 on the light well and selection,
    /// not only on the page.
    private static func accessibleLightAccent(_ color: UInt32) -> UInt32 {
        var amount = 0.0
        var candidate = color
        while relativeLuminance(candidate) > 0.18 && amount < 0.85 {
            amount += 0.05
            candidate = blend(color, with: 0x000000, amount: amount)
        }
        return candidate
    }

    private static func relativeLuminance(_ color: UInt32) -> Double {
        func linear(_ component: UInt32) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((color >> 16) & 0xFF)
            + 0.7152 * linear((color >> 8) & 0xFF)
            + 0.0722 * linear(color & 0xFF)
    }

    private static func blend(_ color: UInt32, with target: UInt32, amount: Double) -> UInt32 {
        func component(_ shift: UInt32) -> UInt32 {
            let start = Double((color >> shift) & 0xFF)
            let end = Double((target >> shift) & 0xFF)
            return UInt32((start + (end - start) * amount).rounded())
        }
        return (component(16) << 16) | (component(8) << 8) | component(0)
    }
}

// MARK: - Theme manager

@Observable
@MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    private static let paletteKey = "theme.palette"
    private static let customAccentKey = "theme.customAccent"
    private static let appearanceKey = "theme.appearance"
    @ObservationIgnored private var widgetReloadTask: Task<Void, Never>?

    var palette: ColorPalette {
        didSet {
            AppGroup.defaults.set(palette.id, forKey: Self.paletteKey)
            if palette.id == "custom" {
                AppGroup.defaults.set(Int(palette.rawAccent ?? palette.accent), forKey: Self.customAccentKey)
            }
            widgetReloadTask?.cancel()
            widgetReloadTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    var appearance: AppearanceMode {
        didSet { AppGroup.defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    private init() {
        if AppGroup.defaults.string(forKey: Self.paletteKey) == "custom" {
            if let savedAccent = AppGroup.defaults.object(forKey: Self.customAccentKey) as? NSNumber {
                palette = .custom(savedAccent.uint32Value)
            } else {
                palette = .custom(ColorPalette.classicBlue.accent)
            }
        } else {
            palette = ColorPalette.named(AppGroup.defaults.string(forKey: Self.paletteKey))
        }
        appearance = AppearanceMode(rawValue: AppGroup.defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
    }
}

// MARK: - Theme-driven colors

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    @MainActor static var themeAccent: Color {
        let p = ThemeManager.shared.palette
        return dynamic(light: p.accent, dark: p.accentDark)
    }

    /// Dark fill used behind white text. Kept separate from the adaptive tint:
    /// a bright dark-mode link color cannot also be a legible button fill.
    @MainActor static var prominentFill: Color {
        Color(hex: ThemeManager.shared.palette.accent)
    }

    static var onProminentFill: Color {
        .white
    }

    /// Neutral page canvas; palette color is reserved for controls and status.
    static var appBackground: Color {
        Color(uiColor: .systemBackground)
    }

    @MainActor static var ringHighlight: Color {
        let p = ThemeManager.shared.palette
        return dynamic(light: p.ringLight, dark: p.ringDark)
    }

    @MainActor static var highlightText: Color {
        let p = ThemeManager.shared.palette
        return dynamic(light: p.textLight, dark: p.textDark)
    }

    static var subtleBorder: Color {
        Color(uiColor: .separator).opacity(0.22)
    }

    static var skeletonFill: Color {
        dynamic(light: 0xE3E9F1, dark: 0x263142)
    }
}

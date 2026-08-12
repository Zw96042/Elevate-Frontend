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

// MARK: - Color palettes

struct ColorPalette: Identifiable, Hashable {
    let id: String
    let name: String
    let accent: UInt32
    let accentDark: UInt32
    let ringLight: UInt32, ringDark: UInt32
    let textLight: UInt32, textDark: UInt32
    let cardLight: UInt32, cardDark: UInt32
    let rawAccent: UInt32?

    init(
        id: String, name: String, accent: UInt32, accentDark: UInt32,
        ringLight: UInt32, ringDark: UInt32,
        textLight: UInt32, textDark: UInt32,
        cardLight: UInt32, cardDark: UInt32,
        rawAccent: UInt32? = nil
    ) {
        self.id = id
        self.name = name
        self.accent = accent
        self.accentDark = accentDark
        self.ringLight = ringLight
        self.ringDark = ringDark
        self.textLight = textLight
        self.textDark = textDark
        self.cardLight = cardLight
        self.cardDark = cardDark
        self.rawAccent = rawAccent
    }

    static let classicBlue = ColorPalette(
        id: "classicBlue", name: "Blue", accent: 0x1769D2, accentDark: 0x67A9FF,
        ringLight: 0xDDEBFF, ringDark: 0x203D63,
        textLight: 0x185DAF, textDark: 0xA8CEFF,
        cardLight: 0xF7FAFF, cardDark: 0x141D29
    )

    static let violet = ColorPalette(
        id: "violet", name: "Indigo", accent: 0x5856B9, accentDark: 0x9B98FF,
        ringLight: 0xE6E5F7, ringDark: 0x38375E,
        textLight: 0x504E9F, textDark: 0xC2C0FF,
        cardLight: 0xF9F9FD, cardDark: 0x1C1B29
    )

    static let rose = ColorPalette(
        id: "rose", name: "Pink", accent: 0xC12A67, accentDark: 0xFF82AE,
        ringLight: 0xF6E1EA, ringDark: 0x5B3042,
        textLight: 0xA72D5D, textDark: 0xFFB1CB,
        cardLight: 0xFDF9FA, cardDark: 0x26191F
    )

    static let forest = ColorPalette(
        id: "forest", name: "Teal", accent: 0x087B75, accentDark: 0x63D4CE,
        ringLight: 0xDCEFED, ringDark: 0x254B49,
        textLight: 0x216B67, textDark: 0xA0E5E1,
        cardLight: 0xF7FBFA, cardDark: 0x142220
    )

    static let sunset = ColorPalette(
        id: "sunset", name: "Orange", accent: 0xC45113, accentDark: 0xFF9F52,
        ringLight: 0xF6E5DA, ringDark: 0x5B3C2A,
        textLight: 0xA44B1B, textDark: 0xFFC29E,
        cardLight: 0xFDF9F7, cardDark: 0x261C17
    )

    static let graphite = ColorPalette(
        id: "graphite", name: "Slate", accent: 0x526276, accentDark: 0xAAB8C9,
        ringLight: 0xE3E8EE, ringDark: 0x37424F,
        textLight: 0x526276, textDark: 0xCAD3DE,
        cardLight: 0xF8F9FA, cardDark: 0x1B1E23
    )

    static let all: [ColorPalette] = [.classicBlue, .violet, .rose, .forest, .sunset, .graphite]

    static func custom(_ accent: UInt32) -> ColorPalette {
        let accessibleAccent = accessibleLightAccent(accent)
        return ColorPalette(
            id: "custom", name: "Custom", accent: accessibleAccent,
            accentDark: blend(accent, with: 0xFFFFFF, amount: 0.60),
            ringLight: blend(accent, with: 0xFFFFFF, amount: 0.84),
            ringDark: blend(accent, with: 0x000000, amount: 0.48),
            textLight: accessibleLightAccent(accent),
            textDark: blend(accent, with: 0xFFFFFF, amount: 0.58),
            cardLight: blend(accent, with: 0xFFFFFF, amount: 0.96),
            cardDark: blend(accent, with: 0x000000, amount: 0.78),
            rawAccent: accent
        )
    }

    static func named(_ id: String?) -> ColorPalette {
        all.first { $0.id == id } ?? .classicBlue
    }

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

import SwiftUI
import UIKit

// MARK: - Theme choices

/// The Theme and Display groups from Settings > Theme, shared with the
/// introduction so both offer the same built-in themes, names, specimens,
/// and identifiers. Choosing writes through the bindings at once; the
/// presenter decides how the change is applied.
struct ThemeChoices: View {
    @Binding var palette: ColorPalette
    @Binding var appearance: AppearanceMode
    /// Settings offers a color of the person's own; the introduction keeps
    /// to the built-in themes and leaves that to Settings.
    var offersCustomColor = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) {
            SettingsGroup(title: "Theme") {
                ForEach(Array(ColorPalette.all.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { InsetDivider() }
                    themeRow(option)
                }
                if offersCustomColor {
                    InsetDivider()
                    customColorRow
                }
            } footer: {
                Text(themeFootnote)
                    .foregroundStyle(Color.muted)
                    .contentTransition(.opacity)
            }

            SettingsGroup(title: "Display") {
                ChoiceList(
                    groups: [ChoiceGroup(title: nil, options: AppearanceMode.allCases.map { mode in
                        ChoiceOption(
                            value: mode,
                            title: mode.rawValue,
                            note: mode == .system ? "Matches your iPhone" : nil,
                            identifier: "appearance.display.\(mode.rawValue.lowercased())"
                        )
                    })],
                    isSelected: { $0 == appearance },
                    choose: { appearance = $0 }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("appearance.display")
            } footer: {
                EmptyView()
            }
        }
        .sensoryFeedback(.selection, trigger: palette)
        .sensoryFeedback(.selection, trigger: appearance)
    }

    private var themeFootnote: String {
        guard palette.id == "custom" else {
            return "Each theme is drawn for both light and dark. Samples show light on the left and dark on the right."
        }
        return offersCustomColor
            ? "Your color is deepened or lifted where needed so links, buttons, and text stay readable."
            : "You're using your own color. Choosing a theme here replaces it."
    }

    /// Specimens, name, and summary; side by side, or stacked at
    /// accessibility sizes.
    @ViewBuilder
    private func themeRowContent(
        specimen: some View,
        name: String,
        summary: String,
        isSelected: Bool
    ) -> some View {
        let text = VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.body)
                .foregroundStyle(Color.ink)
            Text(summary)
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        let check = Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.themeAccent)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                specimen
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    text.frame(maxWidth: .infinity, alignment: .leading)
                    check
                }
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                specimen
                text.frame(maxWidth: .infinity, alignment: .leading)
                check
            }
        }
    }

    private func themeRow(_ option: ColorPalette) -> some View {
        let isSelected = option.id == palette.id
        return Button {
            palette = option
        } label: {
            themeRowContent(
                specimen: ThemeSpecimenPair(palette: option),
                name: option.name,
                summary: option.summary,
                isSelected: isSelected
            )
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.name)
        .accessibilityHint(option.summary)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("appearance.palette.\(option.id)")
    }

    private var customColorRow: some View {
        let isSelected = palette.id == "custom"
        let preview = isSelected ? palette : .custom(palette.accent)
        return ColorPicker(
            selection: Binding(
                get: { Color(hex: palette.rawAccent ?? palette.accent) },
                set: { color in
                    guard let accent = color.rgbHex else { return }
                    palette = .custom(accent)
                }
            ),
            supportsOpacity: false
        ) {
            themeRowContent(
                specimen: ThemeSpecimenPair(palette: preview),
                name: "Custom",
                summary: preview.summary,
                isSelected: isSelected
            )
        }
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .accessibilityLabel("Custom color")
        .accessibilityHint(preview.summary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("appearance.customColor")
    }
}

// MARK: - Specimens

/// A small screen drawn entirely in one theme's roles for one appearance:
/// a grade in its ink beside a muted term, a check in its action color, a
/// hairline, the GPA line over its wash, and a primary button with its
/// label. It shows how the roles sit together, not a preview of a screen.
private struct ThemeSpecimen: View {
    var tones: ColorPalette.Tones
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = 44

    /// Grows with text, but stays a specimen beside the theme's name.
    private var height: CGFloat { min(scaledHeight, 72) }
    private var width: CGFloat { (height * 1.5).rounded() }
    private var inset: CGFloat { (height * 0.13).rounded() }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        VStack(spacing: 0) {
            header
                .padding(.horizontal, inset)
                .frame(height: height * 0.4)
            Rectangle()
                .fill(Color(hex: tones.hairline))
                .frame(height: Metrics.line)
            HStack(alignment: .bottom, spacing: inset * 0.6) {
                chart
                    .padding(.top, inset * 0.5)
                button
                    .padding(.bottom, inset)
            }
            .padding(.trailing, inset)
            .frame(maxHeight: .infinity)
        }
        .frame(width: width, height: height)
        .background(Color(hex: tones.background))
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.rule, lineWidth: Metrics.line) }
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: height * 0.06) {
            Text(verbatim: "96")
                .font(.system(size: height * 0.3, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(hex: tones.ink))
            Text(verbatim: "Q1")
                .font(.system(size: height * 0.19))
                .foregroundStyle(Color(hex: tones.muted))
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.system(size: height * 0.19, weight: .bold))
                .foregroundStyle(Color(hex: tones.action))
        }
        .lineLimit(1)
    }

    private var chart: some View {
        let line = Color(hex: tones.chartLine)
        return ZStack {
            SpecimenCurve(closesArea: true)
                .fill(LinearGradient(
                    colors: [line.opacity(tones.chartFill), line.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            SpecimenCurve()
                .stroke(line, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    private var button: some View {
        RoundedRectangle(cornerRadius: height * 0.06, style: .continuous)
            .fill(Color(hex: tones.buttonFill))
            .frame(width: width * 0.3, height: height * 0.2)
            .overlay {
                Capsule()
                    .fill(Color(hex: tones.onButton))
                    .frame(width: width * 0.13, height: max(1.5, height * 0.035))
            }
    }
}

/// The same curve shape as the GPA chart, at specimen size, or the area
/// beneath it for the wash.
private struct SpecimenCurve: Shape {
    var closesArea = false

    func path(in rect: CGRect) -> Path {
        let curve = GPACurve(values: [90.5, 93.8, 92.6, 96.4], size: rect.size, inset: 0)
        return (closesArea ? curve.area : curve.line)
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Light and dark specimens side by side, light first.
private struct ThemeSpecimenPair: View {
    var palette: ColorPalette

    var body: some View {
        HStack(spacing: 6) {
            ThemeSpecimen(tones: palette.light)
            ThemeSpecimen(tones: palette.dark)
        }
    }
}

private extension Color {
    var rgbHex: UInt32? {
        let resolved = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: nil) else { return nil }
        return (UInt32((red * 255).rounded()) << 16)
            | (UInt32((green * 255).rounded()) << 8)
            | UInt32((blue * 255).rounded())
    }
}

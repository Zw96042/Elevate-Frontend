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


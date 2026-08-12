import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var themeManager = ThemeManager.shared
    @State private var showingDisconnectConfirmation = false
    @State private var isReloading = false
    @State private var isDisconnecting = false
    @State private var cacheStatus: String?
    @State private var dataError: String?
    @AccessibilityFocusState private var dataStatusFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                schoolSection
                dataSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Disconnect Skyward?", isPresented: $showingDisconnectConfirmation) {
                Button("Disconnect", role: .destructive) {
                    Task {
                        isDisconnecting = true
                        dataError = nil
                        do {
                            try await store.disconnect()
                            setCacheStatus("Skyward disconnected")
                        } catch {
                            dataError = error.localizedDescription
                            focusDataStatus()
                        }
                        isDisconnecting = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your saved login, session, cached school data, what-if work, manual GPA classes, and widget data from this iPhone.")
            }
            .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(themeManager.appearance.colorScheme)
        .tint(Color.themeAccent)
    }

    private var appearanceSection: some View {
        @Bindable var theme = themeManager
        return Section {
            NavigationLink {
                AppearanceSettingsView(
                    palette: Binding(
                        get: { theme.palette },
                        set: { palette in updateTheme { theme.palette = palette } }
                    ),
                    appearance: Binding(
                        get: { theme.appearance },
                        set: { appearance in updateTheme { theme.appearance = appearance } }
                    )
                )
            } label: {
                Group {
                    if dynamicTypeSize >= .xxxLarge {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Appearance")
                                .foregroundStyle(.primary)
                                .lineLimit(nil)
                            Text("\(theme.palette.name) · \(theme.appearance.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                        }
                    } else {
                        HStack(spacing: 12) {
                            settingsSymbol("circle.lefthalf.filled")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Appearance")
                                    .foregroundStyle(.primary)
                                Text("\(theme.palette.name) · \(theme.appearance.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            PaletteSwatch(palette: theme.palette, size: 20)
                        }
                    }
                }
            }
        }
    }

    private var schoolSection: some View {
        Section {
            NavigationLink {
                SkywardAccountView()
            } label: {
                Group {
                    if dynamicTypeSize >= .xxxLarge {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(CredentialStore.districtName)
                                .foregroundStyle(.primary)
                                .lineLimit(nil)
                            Text(store.hasCredentials ? "Skyward connected" : "Skyward login required")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                        }
                    } else {
                        HStack(spacing: 12) {
                            settingsSymbol("graduationcap")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CredentialStore.districtName)
                                    .foregroundStyle(.primary)
                                Text(store.hasCredentials ? "Skyward connected" : "Skyward login required")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            accountStatusSymbol
                        }
                    }
                }
            }

            Link(
                destination: URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSdqtqDEwLQY03KHS_LZDpjOjTcP_j8MCIizaMRMHTS6T5tOzQ/viewform?usp=dialog")!
            ) {
                if dynamicTypeSize >= .xxxLarge {
                    Text("Request another district")
                        .lineLimit(nil)
                } else {
                    HStack(spacing: 12) {
                        settingsSymbol("building.2")
                        Text("Request another district")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("School")
        } footer: {
            Text("Credentials are verified before they are stored on this iPhone.")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                Task {
                    isReloading = true
                    dataError = nil
                    cacheStatus = nil
                    await store.clearAllCaches()
                    if store.coursesError != nil || store.messagesError != nil {
                        dataError = "Some data couldn't be refreshed. Saved data remains visible where available."
                        focusDataStatus()
                    } else {
                        setCacheStatus("Data reloaded")
                    }
                    isReloading = false
                }
            } label: {
                if dynamicTypeSize >= .xxxLarge {
                    Text(isReloading ? "Reloading data…" : "Reload all data")
                        .lineLimit(nil)
                } else {
                    HStack(spacing: 12) {
                        if isReloading {
                            ProgressView()
                                .frame(width: 24)
                                .accessibilityHidden(true)
                        } else {
                            settingsSymbol("arrow.trianglehead.2.counterclockwise")
                        }
                        Text(isReloading ? "Reloading data…" : "Reload all data")
                        Spacer()
                    }
                }
            }
            .disabled(isReloading || isDisconnecting || !store.canShowData)

            if store.hasCredentials {
                Button(role: .destructive) {
                    showingDisconnectConfirmation = true
                } label: {
                    if dynamicTypeSize >= .xxxLarge {
                        Text(isDisconnecting ? "Disconnecting…" : "Disconnect Skyward")
                            .lineLimit(nil)
                    } else {
                        HStack(spacing: 12) {
                            if isDisconnecting {
                                ProgressView()
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                            } else {
                                settingsSymbol("rectangle.portrait.and.arrow.right", color: .red)
                            }
                            Text(isDisconnecting ? "Disconnecting…" : "Disconnect Skyward")
                            Spacer()
                        }
                    }
                }
                .disabled(isReloading || isDisconnecting)
            }
        } header: {
            Text("Data")
        } footer: {
            if let dataError {
                Label(dataError, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityFocused($dataStatusFocused)
            } else if let cacheStatus {
                Label(cacheStatus, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.opacity)
                    .accessibilityFocused($dataStatusFocused)
            } else {
                Text("Reloading keeps your login and local what-if work. Disconnecting removes all account data from this iPhone.")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            Link(destination: URL(string: "https://elevate.wilsonzach.com/privacy")!) {
                externalLinkLabel("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "mailto:zach.wilson.atx@gmail.com")!) {
                externalLinkLabel("Contact Support", systemImage: "envelope")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Elevate is independent and is not affiliated with Skyward, Inc. or Eanes ISD.")
        }
    }

    @ViewBuilder
    private func externalLinkLabel(_ title: String, systemImage: String) -> some View {
        if dynamicTypeSize >= .xxxLarge {
            Text(title)
                .lineLimit(nil)
        } else {
            HStack(spacing: 12) {
                settingsSymbol(systemImage)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func settingsSymbol(_ name: String, color: Color = .themeAccent) -> some View {
        Image(systemName: name)
            .font(.body.weight(.medium))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: 24)
            .accessibilityHidden(true)
    }

    private var accountStatusSymbol: some View {
        Image(systemName: store.hasCredentials ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(store.hasCredentials ? .green : Color.secondary)
            .accessibilityHidden(true)
    }

    private func updateTheme(_ change: () -> Void) {
        change()
    }

    private func setCacheStatus(_ status: String) {
        if reduceMotion {
            cacheStatus = status
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                cacheStatus = status
            }
        }
        focusDataStatus()
    }

    private func focusDataStatus() {
        dataStatusFocused = false
        Task { @MainActor in
            await Task.yield()
            dataStatusFocused = true
        }
    }

    private struct PaletteSwatch: View {
        var palette: ColorPalette
        var size: CGFloat

        var body: some View {
            Circle()
                .fill(Color(hex: palette.rawAccent ?? palette.accent))
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .separator).opacity(0.32), lineWidth: 0.5)
                }
                .accessibilityHidden(true)
        }
    }

    private struct AppearanceSettingsView: View {
        @Binding var palette: ColorPalette
        @Binding var appearance: AppearanceMode
        @State private var showingPresets = false
        @State private var presetTriggerWidth: CGFloat = 320

        var body: some View {
            List {
                Section("Accent") {
                    Button {
                        showingPresets = true
                    } label: {
                        HStack {
                            Text("Preset")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(palette.id == "custom" ? "Custom" : palette.name)
                                .foregroundStyle(.secondary)
                            PaletteSwatch(palette: palette, size: 20)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { presetTriggerWidth = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, width in
                                    presetTriggerWidth = width
                                }
                        }
                    }
                    .popover(
                        isPresented: $showingPresets,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
                        presetChoices
                            .frame(width: max(presetTriggerWidth, 280))
                            .presentationCompactAdaptation(.popover)
                    }

                    ColorPicker(
                        "Custom color",
                        selection: Binding(
                            get: { Color(hex: palette.rawAccent ?? palette.accent) },
                            set: { color in
                                guard let accent = color.rgbHex else { return }
                                update { palette = .custom(accent) }
                            }
                        ),
                        supportsOpacity: false
                    )
                }

                Section {
                    Picker("Display", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Display")
                } footer: {
                    Text(appearance == .system
                        ? "Matches your iPhone automatically."
                        : "Keeps Elevate in \(appearance.rawValue.lowercased()) appearance.")
                        .contentTransition(.opacity)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: palette)
            .sensoryFeedback(.selection, trigger: appearance)
        }

        private var presetChoices: some View {
            VStack(spacing: 0) {
                Text("Presets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(height: 32)

                ForEach(ColorPalette.all) { option in
                    Button {
                        update { palette = option }
                        showingPresets = false
                    } label: {
                        HStack(spacing: 12) {
                            PaletteSwatch(palette: option, size: 20)
                            Text(option.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if option.id == palette.id {
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
                    .accessibilityAddTraits(option.id == palette.id ? .isSelected : [])
                }
            }
            .padding(.vertical, 8)
        }

        private func update(_ change: () -> Void) {
            change()
        }
    }

    private struct SkywardAccountView: View {
        @Environment(AppStore.self) private var store
        @Environment(\.dismiss) private var dismiss
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var username = ""
        @State private var password = ""
        @State private var showPassword = false
        @State private var verifying = false
        @State private var errorMessage: String?
        @State private var didLoad = false
        @FocusState private var focusedField: Field?
        @AccessibilityFocusState private var errorFocused: Bool

        private enum Field {
            case username, password
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    credentialGroup

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .accessibilityFocused($errorFocused)
                    }

                    Label("Your login is stored in iOS Keychain and is only used to connect to Skyward.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    connectButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Skyward Account")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(verifying)
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if let credentials = CredentialStore.load() {
                    username = credentials.username
                    password = credentials.password
                }
            }
        }

        private var introduction: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(CredentialStore.districtName)
                        .font(.title2.weight(.semibold))
                    if store.hasCredentials {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                Text(store.hasCredentials
                    ? "Update the student account used to refresh grades and messages."
                    : "Enter the same student login you use on the Skyward website.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private var credentialGroup: some View {
            VStack(spacing: 0) {
                credentialRow(
                    systemImage: "person",
                    field: .username
                ) {
                    TextField("Student ID or username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .accessibilityLabel("Skyward username")
                }

                Divider()
                    .padding(.leading, 54)

                credentialRow(
                    systemImage: "lock",
                    field: .password
                ) {
                    HStack(spacing: 4) {
                        Group {
                            if showPassword {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit {
                            if canSubmit {
                                Task { await save() }
                            }
                        }
                        .accessibilityLabel("Skyward password")

                        Button {
                            showPassword.toggle()
                            focusedField = .password
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 0.5)
            }
        }

        private func credentialRow<Content: View>(
            systemImage: String,
            field: Field,
            @ViewBuilder content: () -> Content
        ) -> some View {
            let isFocused = focusedField == field
            return HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isFocused ? Color.themeAccent : Color.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                content()
                    .font(.body)
                    .textFieldStyle(.plain)
                    .tint(Color.themeAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 56)
            .background(isFocused ? Color.themeAccent.opacity(0.055) : .clear)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = field
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
        }

        private var connectButton: some View {
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 8) {
                    if verifying {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(verifying
                        ? "Verifying…"
                        : (store.hasCredentials ? "Update connection" : "Connect to Skyward"))
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .tint(Color.prominentFill)
            .disabled(!canSubmit)
            .accessibilityLabel(verifying ? "Verifying" : "Verify and save Skyward login")
        }

        private var canSubmit: Bool {
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.isEmpty
                && !verifying
        }

        private func save() async {
            guard canSubmit else { return }
            focusedField = nil
            verifying = true
            errorMessage = nil
            errorFocused = false
            let successAnnouncement = store.hasCredentials
                ? "Skyward connection updated"
                : "Skyward connected"

            let success = await store.saveCredentials(username: username, password: password)
            verifying = false

            if success {
                UIAccessibility.post(notification: .announcement, argument: successAnnouncement)
                dismiss()
            } else {
                let message = store.authError ?? "Couldn't verify this login."
                if reduceMotion {
                    errorMessage = message
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        errorMessage = message
                    }
                }
                Task { @MainActor in
                    await Task.yield()
                    errorFocused = true
                }
            }
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

import SwiftUI
import UIKit

/// The Skyward login form. Shared by Settings (pushed), the tab login prompts
/// (presented in `SkywardConnectSheet`), and onboarding (pushed as its final
/// stage). Verification and storage are entirely owned by
/// `AppStore.saveCredentials`.
struct SkywardAccountView: View {
    var showsCancel = false
    /// Called instead of dismissing, only after a verified save.
    var onConnected: (() -> Void)? = nil
    /// Onboarding's Not now: shown in the bar and locked while verifying.
    var onSkip: (() -> Void)? = nil
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
            VStack(alignment: .leading, spacing: 28) {
                introduction

                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 14) {
                        field("Username", field: .username) {
                            TextField("Student ID or username", text: $username)
                                .textContentType(.username)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .username)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                                .accessibilityLabel("Skyward username")
                                .accessibilityIdentifier("login.username")
                        }
                        field("Password", field: .password) {
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
                                .accessibilityIdentifier("login.password")

                                Button {
                                    showPassword.toggle()
                                    focusedField = .password
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundStyle(Color.muted)
                                        .frame(width: 44, height: 44)
                                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                                .accessibilityIdentifier("login.togglePassword")
                            }
                        }
                    }

                    if let errorMessage {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .accessibilityHidden(true)
                            Text(errorMessage)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.gradeAttention)
                        .transition(.opacity)
                        .accessibilityElement(children: .combine)
                        .accessibilityFocused($errorFocused)
                        .accessibilityIdentifier("login.error")
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    connectButton
                    Text("Your login is stored in the iOS Keychain and is only used to connect to Skyward.")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, Metrics.page)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground.ignoresSafeArea())
        .foregroundStyle(Color.ink)
        .navigationTitle("Skyward Account")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(verifying)
        .navigationBarBackButtonHidden(verifying)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(verifying)
                        .accessibilityIdentifier("login.cancel")
                }
            }
            if let onSkip {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not now") { onSkip() }
                        .disabled(verifying)
                        .accessibilityHint("Continue without an account. You can connect from any tab or Settings.")
                        .accessibilityIdentifier("onboarding.notNow")
                }
            }
        }
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
            Text(CredentialStore.districtName)
                .font(.title.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if store.hasCredentials {
                Label("Connected", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
            }

            Text(store.hasCredentials
                ? "Update the student account used to refresh grades and messages."
                : "Enter the same student login you use on the Skyward website.")
                .font(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A label above a plain input well. Tapping the well focuses its field;
    /// the focused well is outlined in the action color.
    private func field<Content: View>(
        _ label: String,
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isFocused = focusedField == field
        let shape = RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.muted)
                .accessibilityHidden(true)
            content()
                .font(.body)
                .textFieldStyle(.plain)
                .tint(Color.themeAccent)
                .padding(.leading, 12)
                .padding(.trailing, field == .password ? 0 : 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Color.well, in: shape)
                .overlay {
                    shape
                        .strokeBorder(Color.themeAccent, lineWidth: 1.5)
                        .opacity(isFocused ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .contentShape(shape)
                .onTapGesture {
                    focusedField = field
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


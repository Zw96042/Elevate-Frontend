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


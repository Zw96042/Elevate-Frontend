import SwiftUI

/// The installed build, read from the bundle. Only the receipt file's name is
/// read, to tell TestFlight and development installs apart; never its
/// contents or any credential.
enum InstalledAppInfo {
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }

    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
    }

    static var displayName: String { version.isEmpty ? "Elevate" : "Elevate \(version)" }

    static var operatingSystemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// TestFlight and Xcode installs carry a sandbox receipt name.
    static var isTestBuild: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
}

/// What the last App Store check says about this build, in words. A failed
/// check never restates a saved result as current.
@MainActor
struct AppUpdateStatus {
    enum Phase: Equatable {
        case notChecked, checking, failed
        case checked(AppStoreRelease.Availability)
    }

    var phase: Phase
    var release: AppStoreRelease?

    init(service: AppUpdateService) {
        release = service.release
        if service.isChecking {
            phase = .checking
        } else if service.error != nil {
            phase = .failed
        } else if let release = service.release {
            phase = .checked(release.availability(
                installedVersion: InstalledAppInfo.version,
                operatingSystemVersion: InstalledAppInfo.operatingSystemVersion
            ))
        } else {
            phase = .notChecked
        }
    }

    /// The Settings row's subtitle.
    var summary: String {
        switch phase {
        case .notChecked: return "Check the App Store for a newer version"
        case .checking: return "Checking the App Store…"
        case .failed: return "Couldn't check for updates"
        case .checked(let availability):
            guard let release else { return "Check the App Store for a newer version" }
            switch availability {
            case .newer: return "Version \(release.version) is on the App Store"
            case .same: return "No newer App Store version"
            case .installedAhead: return "This build is newer than the App Store"
            case .requiresNewerOS: return "Version \(release.version) needs iOS \(release.minimumOSVersion) or later"
            case .unavailable: return "Couldn't compare versions"
            }
        }
    }

    var title: String {
        switch phase {
        case .notChecked: return "Not checked yet"
        case .checking: return "Checking the App Store…"
        case .failed: return "Couldn't check for updates"
        case .checked(let availability):
            guard let release else { return "Not checked yet" }
            switch availability {
            case .newer: return "Version \(release.version) is available"
            case .same: return "No newer App Store version"
            case .installedAhead: return "This build is newer than the App Store"
            case .requiresNewerOS: return "Version \(release.version) needs iOS \(release.minimumOSVersion) or later"
            case .unavailable: return "Couldn't compare versions"
            }
        }
    }

    var detail: String {
        switch phase {
        case .notChecked:
            return "Elevate checks only when you ask."
        case .checking:
            return lastKnown.map { "Last check: \($0)" } ?? "Looking up Elevate's public App Store listing."
        case .failed:
            // The saved release stays history; it isn't restated as current.
            return lastKnown.map { "Nothing new was confirmed. Last successful check: \($0)" }
                ?? "No App Store information is saved yet. Check your connection and try again."
        case .checked(let availability):
            guard let release else { return "" }
            let checked = "Checked \(Self.checkedText(release.checkedAt))."
            switch availability {
            case .newer:
                return "On the App Store. \(checked)"
            case .same:
                let base = "App Store version \(release.version) matches this version. \(checked)"
                return InstalledAppInfo.isTestBuild ? base + " A newer TestFlight build may still exist." : base
            case .installedAhead:
                return "App Store version \(release.version). \(checked)"
            case .requiresNewerOS:
                return "This iPhone has iOS \(InstalledAppInfo.operatingSystemVersion). \(checked)"
            case .unavailable:
                return "App Store version \(release.version). \(checked)"
            }
        }
    }

    /// Only a current, successful check with a compatible system offers the
    /// App Store link.
    var offersStoreUpdate: Bool { phase == .checked(.newer) }

    /// "App Store version 2.0.3, Oct 3, 2026 at 4:12 PM."
    private var lastKnown: String? {
        release.map { "App Store version \($0.version), \(Self.checkedText($0.checkedAt))." }
    }

    static func checkedText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// App version and App Store status. Elevate looks up its public App Store
/// listing only when Check is tapped; updates themselves install through the
/// App Store or TestFlight. Pushed from Settings → Updates.
struct AppUpdatesView: View {
    var service: AppUpdateService

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let status = AppUpdateStatus(service: service)
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionGap) {
                installedSection
                storeSection(status)
            }
            .padding(.horizontal, Metrics.page)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .softScrollEdges()
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("updates.screen")
    }

    // MARK: - This iPhone

    private var installedSection: some View {
        let build = InstalledAppInfo.build
        let version = InstalledAppInfo.version.isEmpty ? "Unknown" : InstalledAppInfo.version
        return SettingsGroup(title: "This iPhone") {
            valueRow("Installed version", value: build.isEmpty ? version : "\(version) (\(build))",
                     spokenValue: build.isEmpty ? version : "\(version), build \(build)",
                     identifier: "updates.installed")
            InsetDivider()
            valueRow("iOS", value: InstalledAppInfo.operatingSystemVersion,
                     spokenValue: InstalledAppInfo.operatingSystemVersion,
                     identifier: "updates.os")
        } footer: {
            if InstalledAppInfo.isTestBuild {
                Text("This is a TestFlight or development build. TestFlight builds update in the TestFlight app; the check below compares public App Store versions only.")
                    .foregroundStyle(Color.muted)
                    .accessibilityIdentifier("updates.testBuild")
            }
        }
    }

    /// A label with its value trailing, or beneath it at accessibility sizes.
    private func valueRow(_ title: String, value: String, spokenValue: String, identifier: String) -> some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if dynamicTypeSize.isAccessibilitySize {
                    Text(value)
                        .font(.figure(.body, weight: .regular))
                        .foregroundStyle(Color.muted)
                }
            }
        } accessory: {
            if !dynamicTypeSize.isAccessibilitySize {
                Text(value)
                    .font(.figure(.body, weight: .regular))
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - App Store


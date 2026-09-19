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


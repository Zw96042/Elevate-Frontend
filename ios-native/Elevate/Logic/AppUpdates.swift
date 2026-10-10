import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Comparable numeric dotted versions without integer overflow or prerelease guesses.
struct AppVersion: Comparable, Equatable {
    private var components: [String]
    init?(_ value: String) {
        guard !value.isEmpty, value.utf8.count <= 128 else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...8).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        components = parts.map {
            let digits = $0.drop(while: { $0 == "0" })
            return digits.isEmpty ? "0" : String(digits)
        }
        while components.count > 1 && components.last == "0" { components.removeLast() }
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let a = index < lhs.components.count ? lhs.components[index] : "0"
            let b = index < rhs.components.count ? rhs.components[index] : "0"
            if a.count != b.count { return a.count < b.count }
            if a != b { return a < b }
        }
        return false
    }
}

struct AppStoreRelease: Codable, Equatable {
    var version: String
    var minimumOSVersion: String
    var releaseNotes: String
    var checkedAt: Date

    enum Availability: Equatable { case newer, same, installedAhead, requiresNewerOS, unavailable }
    func availability(installedVersion: String, operatingSystemVersion: String) -> Availability {
        guard let installed = AppVersion(installedVersion), let latest = AppVersion(version),
              let required = AppVersion(minimumOSVersion), let currentOS = AppVersion(operatingSystemVersion) else { return .unavailable }
        if latest > installed { return currentOS < required ? .requiresNewerOS : .newer }
        return latest == installed ? .same : .installedAhead
    }

    static func decodeLookup(_ data: Data, at date: Date = Date()) throws -> AppStoreRelease {
        struct Lookup: Decodable {
            var results: [Release]
            struct Release: Decodable {
                var trackId: Int64
                var bundleId: String
                var version: String
                var minimumOsVersion: String
                var releaseNotes: String?
            }
        }
        guard data.count <= 1_000_000, date.timeIntervalSince1970.isFinite,
              let lookup = try? JSONDecoder().decode(Lookup.self, from: data), lookup.results.count == 1,
              let release = lookup.results.first,
              release.trackId == AppUpdateClient.appID, release.bundleId == "com.zachwilson.elevate",
              AppVersion(release.version) != nil, AppVersion(release.minimumOsVersion) != nil else {
            throw AppUpdateError.invalidResponse
        }
        return AppStoreRelease(version: release.version, minimumOSVersion: release.minimumOsVersion,
            releaseNotes: String((release.releaseNotes ?? "").prefix(12_000)), checkedAt: date)
    }
}

enum AppUpdateError: Error, LocalizedError {
    case invalidResponse
    var errorDescription: String? { "Couldn't verify the App Store version. Try again later." }
}

/// This fetches public, non-executable release information. No Skyward session is sent.
enum AppUpdateClient {
    static let appID: Int64 = 6_752_371_076
    static let storeURL = URL(string: "https://apps.apple.com/us/app/elevate-gradebook/id6752371076")!
    static let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=6752371076&country=us")!

    static func fetch(session: URLSession? = nil) async throws -> AppStoreRelease {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let ownedSession = session ?? URLSession(configuration: configuration)
        defer { if session == nil { ownedSession.invalidateAndCancel() } }
        var request = URLRequest(url: lookupURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await ownedSession.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == "itunes.apple.com" else { throw AppUpdateError.invalidResponse }
        return try AppStoreRelease.decodeLookup(data)
    }
}

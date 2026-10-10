import Foundation
import Observation

@Observable @MainActor
final class AppUpdateService {
    private(set) var release: AppStoreRelease?
    private(set) var isChecking = false
    private(set) var error: String?
    private static let cacheKey = "appStoreRelease.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let saved = try? JSONDecoder().decode(AppStoreRelease.self, from: data),
           AppVersion(saved.version) != nil, AppVersion(saved.minimumOSVersion) != nil,
           saved.checkedAt <= Date().addingTimeInterval(60),
           saved.checkedAt.timeIntervalSince1970.isFinite {
            release = saved
        }
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        error = nil
        defer { isChecking = false }
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-SampleData"),
               let flag = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-PreviewAppUpdate=") }) {
                if flag == "-PreviewAppUpdate=loading" { try await Task.sleep(for: .seconds(60)) }
                if flag == "-PreviewAppUpdate=error" { throw AppUpdateError.invalidResponse }
                let version: String
                switch flag {
                case "-PreviewAppUpdate=same": version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.0"
                case "-PreviewAppUpdate=ahead": version = "2.0.3"
                default: version = "2.2.0"
                }
                release = AppStoreRelease(version: version, minimumOSVersion: flag == "-PreviewAppUpdate=os" ? "99.0" : "17.0",
                    releaseNotes: "Synthetic release notes for interface verification.", checkedAt: Date())
                return
            }
            #endif
            let result = try await AppUpdateClient.fetch()
            try Task.checkCancellation()
            release = result
            if let data = try? JSONEncoder().encode(result) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
        } catch is CancellationError { }
        catch { self.error = "Couldn't check for updates. Any saved version information is from the previous check." }
    }
}

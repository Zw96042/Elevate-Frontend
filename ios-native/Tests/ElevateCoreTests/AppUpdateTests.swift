import Foundation
import Testing
@testable import ElevateCore

@Suite struct AppUpdateTests {
    @Test func numericVersionOrdering() {
        #expect(AppVersion("2.10")! > AppVersion("2.9.9")!)
        #expect(AppVersion("2.1") == AppVersion("02.01.0"))
        #expect(AppVersion("99999999999999999999999")! > AppVersion("2")!)
        for input in ["", "2..1", "v2.1", "2.1-beta", "２.１", ".1", "1."] { #expect(AppVersion(input) == nil) }
    }
    @Test func validatesProductAndVersion() throws {
        let json = #"{"results":[{"trackId":6752371076,"bundleId":"com.zachwilson.elevate","version":"2.1.1","minimumOsVersion":"17.0","releaseNotes":"New features"}]}"#
        let release = try AppStoreRelease.decodeLookup(Data(json.utf8), at: Date(timeIntervalSince1970: 100))
        #expect(release.releaseNotes == "New features")
        #expect(release.availability(installedVersion: "2.1.0", operatingSystemVersion: "17.0") == .newer)
        #expect(release.availability(installedVersion: "2.1.1", operatingSystemVersion: "17.0") == .same)
        #expect(release.availability(installedVersion: "2.2", operatingSystemVersion: "17.0") == .installedAhead)
        #expect(release.availability(installedVersion: "2.0", operatingSystemVersion: "16.5") == .requiresNewerOS)
        #expect(throws: (any Error).self) { try AppStoreRelease.decodeLookup(Data(json.replacingOccurrences(of: "com.zachwilson.elevate", with: "other.app").utf8)) }
        #expect(throws: (any Error).self) { try AppStoreRelease.decodeLookup(Data("{\"results\":[]}".utf8)) }
        #expect(throws: (any Error).self) { try AppStoreRelease.decodeLookup(Data("<html>Unavailable</html>".utf8)) }
    }
}

import Foundation
import Security
import Testing
@testable import ElevateCore

/// Exercises the real Security request boundary with synthetic items. macOS's
/// legacy Keychain does not expose the iPhone accessibility class; physical
/// locked-device availability must still be verified separately.
@Suite("Background Skyward Keychain requests")
struct BackgroundKeychainTests {
    @Test("Both new and replacement sign-in secrets request device-only background access", arguments: [true, false])
    func savesBackgroundAccessibleSecrets(isNew: Bool) throws {
        var added = false
        try KeychainStore.save("synthetic-secret", service: "synthetic-service", account: "synthetic-account",
            update: { query, attributes in
                assertIdentity(query)
                let values = attributes as NSDictionary
                #expect(values[kSecAttrAccessible] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
                #expect(values[kSecValueData] is Data)
                return isNew ? errSecItemNotFound : errSecSuccess
            }, add: { item in
                added = true
                assertIdentity(item)
                #expect((item as NSDictionary)[kSecAttrAccessible] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
                return errSecSuccess
            })
        #expect(added == isNew)
    }

    @Test("Old records upgrade only protection; even an upgrade failure preserves the successful read", arguments: [errSecSuccess, errSecInteractionNotAllowed])
    func upgradesExistingRecord(status: OSStatus) throws {
        let data = try JSONEncoder().encode("synthetic-existing-secret")
        var updated = false
        let value = KeychainStore.load(String.self, service: "synthetic-service", account: "synthetic-account",
            copy: { query, result in
                assertIdentity(query)
                let options = query as NSDictionary
                #expect(options[kSecReturnData] as? Bool == true)
                #expect(options[kSecReturnAttributes] as? Bool == true)
                result = [kSecValueData as String: data,
                          kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as NSDictionary
                return errSecSuccess
            }, update: { query, attributes in
                updated = true
                assertIdentity(query)
                let values = attributes as NSDictionary
                #expect(values.count == 1)
                #expect(values[kSecValueData] == nil)
                #expect(values[kSecAttrAccessible] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
                return status
            })
        #expect(value == "synthetic-existing-secret")
        #expect(updated)
    }

    @Test("Unreadable or malformed records cannot cause a protection update", arguments: [true, false])
    func rejectsInvalidRecords(unreadable: Bool) {
        let value = KeychainStore.load(String.self, service: "synthetic-service", account: "synthetic-account",
            copy: { _, result in
                result = [kSecValueData as String: Data("malformed".utf8)] as NSDictionary
                return unreadable ? errSecInteractionNotAllowed : errSecSuccess
            }, update: { _, _ in Issue.record("Invalid records must not migrate"); return errSecSuccess })
        #expect(value == nil)
    }

    @Test("Already-upgraded records need no protection write")
    func leavesCurrentProtectionAlone() throws {
        let data = try JSONEncoder().encode("synthetic-secret")
        let value = KeychainStore.load(String.self, service: "synthetic-service", account: "synthetic-account",
            copy: { _, result in
                result = [kSecValueData as String: data,
                          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as NSDictionary
                return errSecSuccess
            }, update: { _, _ in Issue.record("Current records need no migration"); return errSecSuccess })
        #expect(value == "synthetic-secret")
    }

    @Test("Real Security roundtrip uses only an isolated synthetic record")
    func actualKeychainRoundtrip() throws {
        let service = "com.zacharywilson.elevate.tests.\(UUID().uuidString)"
        defer { try? KeychainStore.remove(service: service, account: "synthetic") }
        try KeychainStore.save("synthetic-secret", service: service, account: "synthetic")
        #expect(KeychainStore.load(String.self, service: service, account: "synthetic") == "synthetic-secret")
        #expect(KeychainStore.load(String.self, service: service, account: "other") == nil)
        try KeychainStore.remove(service: service, account: "synthetic")
        #expect(KeychainStore.load(String.self, service: service, account: "synthetic") == nil)
    }

    private func assertIdentity(_ query: CFDictionary) {
        let values = query as NSDictionary
        #expect(values[kSecClass] as? String == kSecClassGenericPassword as String)
        #expect(values[kSecAttrService] as? String == "synthetic-service")
        #expect(values[kSecAttrAccount] as? String == "synthetic-account")
    }
}

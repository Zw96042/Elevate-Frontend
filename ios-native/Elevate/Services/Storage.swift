import CryptoKit
import Foundation
import Security

private enum SecureStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Elevate couldn't update secure storage (code \(status))."
        }
    }
}

/// Small checked Keychain boundary shared by credentials and active sessions.
private enum KeychainStore {
    static func save<Value: Encodable>(
        _ value: Value,
        service: String,
        account: String
    ) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecureStoreError.keychain(updateStatus)
        }

        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureStoreError.keychain(addStatus)
        }
    }

    static func load<Value: Decodable>(
        _ type: Value.Type,
        service: String,
        account: String
    ) -> Value? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.keychain(status)
        }
    }
}

/// Skyward credentials are device-only and available only while the device is unlocked.
enum CredentialStore {
    private struct Payload: Codable {
        var username: String
        var password: String
    }

    private static let service = "com.zacharywilson.elevate.skyward"
    private static let account = "skyward"

    // The legacy app hardcoded Eanes ISD; keep that as the only district for now.
    static let districtName = "Eanes ISD"
    static let baseURL = "https://skyward-eisdprod.iscorp.com/p12edueanesisdtx/web/"

    static func save(username: String, password: String) throws {
        try KeychainStore.save(
            Payload(username: username, password: password),
            service: service,
            account: account
        )
    }

    static func load() -> SkywardCredentials? {
        guard let payload = KeychainStore.load(Payload.self, service: service, account: account),
              !payload.username.isEmpty,
              !payload.password.isEmpty else {
            return nil
        }
        return SkywardCredentials(
            username: payload.username,
            password: payload.password,
            baseURL: baseURL
        )
    }

    static func clear() throws {
        try KeychainStore.remove(service: service, account: account)
    }

    static var hasCredentials: Bool { load() != nil }

    static var currentAccountIdentifier: String? {
        load().map { accountIdentifier(for: $0.username) }
    }

    static func accountIdentifier(for username: String) -> String {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// Session codes are authentication secrets, so they use Keychain rather than preferences.
enum SessionStore {
    private static let service = "com.zacharywilson.elevate.skyward.session"
    private static let account = "current"
    private static let legacyDefaultsKey = "skywardSessionCodes"

    static func save(_ codes: SkywardSessionCodes) throws {
        try KeychainStore.save(codes, service: service, account: account)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    static func load() -> SkywardSessionCodes? {
        if let codes = KeychainStore.load(
            SkywardSessionCodes.self,
            service: service,
            account: account
        ) {
            return codes
        }

        // One-time migration from versions that stored session secrets in UserDefaults.
        guard let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
              let codes = try? JSONDecoder().decode(SkywardSessionCodes.self, from: data) else {
            return nil
        }
        if (try? save(codes)) != nil {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        }
        return codes
    }

    static func clear() throws {
        try KeychainStore.remove(service: service, account: account)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }
}

/// Small JSON cache with timestamps, mirroring the AsyncStorage caches in the legacy app.
enum JSONCache {
    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key + ".timestamp")
        }
    }

    static func load<T: Decodable>(_ type: T.Type, key: String, maxAge: TimeInterval) -> T? {
        let stamp = UserDefaults.standard.double(forKey: key + ".timestamp")
        guard stamp > 0, Date().timeIntervalSince1970 - stamp < maxAge,
              let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func clear(prefix: String) {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

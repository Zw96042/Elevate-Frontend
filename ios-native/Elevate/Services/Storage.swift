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

/// Skyward sign-in secrets stay device-only, but remain usable by background
/// requests after the first unlock following a restart, including re-authentication.
enum KeychainStore {
    static func save<Value: Encodable>(
        _ value: Value,
        service: String,
        account: String,
        update: (CFDictionary, CFDictionary) -> OSStatus = { SecItemUpdate($0, $1) },
        add: (CFDictionary) -> OSStatus = { SecItemAdd($0, nil) }
    ) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = update(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecureStoreError.keychain(updateStatus)
        }

        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = add(item as CFDictionary)
        guard addStatus == errSecSuccess else {
            throw SecureStoreError.keychain(addStatus)
        }
    }

    static func load<Value: Decodable>(
        _ type: Value.Type,
        service: String,
        account: String,
        copy: (CFDictionary, inout AnyObject?) -> OSStatus = { SecItemCopyMatching($0, &$1) },
        update: (CFDictionary, CFDictionary) -> OSStatus = { SecItemUpdate($0, $1) }
    ) -> Value? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard copy(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any],
              let data = attributes[kSecValueData as String] as? Data,
              let value = try? JSONDecoder().decode(type, from: data) else {
            return nil
        }
        if attributes[kSecAttrAccessible as String] as? String != kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String {
            // Upgrade old installs after a successful read. Change only the
            // protection attribute; never rewrite a possibly superseded payload.
            // A failed upgrade leaves the original item and successful read intact.
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: account,
            ]
            let protection: [String: Any] = [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            _ = update(item as CFDictionary, protection as CFDictionary)
        }
        return value
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

/// Expo SecureStore keys use binary account/generic attributes rather than the
/// string account attribute used by the native stores.
enum ExpoKeychainStore {
    static func load<Value: Decodable>(
        _ type: Value.Type,
        service: String,
        key: String
    ) throws -> Value? {
        var query = baseQuery(service: service, key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureStoreError.keychain(status)
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(service: String, key: String) throws {
        let status = SecItemDelete(baseQuery(service: service, key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.keychain(status)
        }
    }

    static func baseQuery(service: String, key: String) -> [String: Any] {
        let encodedKey = Data(key.utf8)
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrGeneric as String: encodedKey,
            kSecAttrAccount as String: encodedKey,
        ]
    }
}

/// Device-only Skyward credentials support background login after first unlock.
enum CredentialStore {
    private struct Payload: Codable {
        var username: String
        var password: String
    }

    private static let service = "com.zacharywilson.elevate.skyward"
    static let expoLegacyService = "com.zacharywilson.elevate.skyward:no-auth"
    static let account = "skyward"

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
        try ExpoKeychainStore.remove(service: expoLegacyService, key: account)
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

    /// Expo SecureStore 15 appends `:no-auth` to the configured service. Its
    /// UTF-8 JSON payload is Codable-compatible with the native payload.
    @discardableResult
    static func migrateExpoSecureStoreCredentials() throws -> Bool {
        let legacy = try ExpoKeychainStore.load(Payload.self, service: expoLegacyService, key: account)
        let migrated = try migrateCompleteLegacyCredentials(
            username: legacy?.username,
            password: legacy?.password,
            hasCurrentCredentials: hasCredentials,
            save: save,
            deleteLegacy: {
                try ExpoKeychainStore.remove(service: expoLegacyService, key: account)
            }
        )
        return migrated
    }

    @discardableResult
    static func migrateCompleteLegacyCredentials(
        username: String?,
        password: String?,
        hasCurrentCredentials: Bool,
        save: (String, String) throws -> Void,
        deleteLegacy: () throws -> Void
    ) throws -> Bool {
        let username = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isComplete = username?.isEmpty == false && password?.isEmpty == false
        if !hasCurrentCredentials, isComplete, let username, let password {
            try save(username, password)
        }
        // Delete only after a successful native save, or after deciding the
        // current native record supersedes/invalidates this legacy record.
        try deleteLegacy()
        return !hasCurrentCredentials && isComplete
    }

    static func deleteExpoLegacyCredentials() throws {
        try ExpoKeychainStore.remove(service: expoLegacyService, key: account)
    }
}

/// Session codes are authentication secrets, so they use Keychain rather than preferences.
enum SessionStore {
    private static let service = "com.zacharywilson.elevate.skyward.session"
    static let expoLegacyService = "com.zacharywilson.elevate.skyward.session:no-auth"
    private static let unscopedLegacyAccount = "current"
    private static let legacyDefaultsKey = "skywardSessionCodes"

    static func save(_ codes: SkywardSessionCodes, accountIdentifier: String) throws {
        try KeychainStore.save(codes, service: service, account: scopedAccount(accountIdentifier))
        try invalidateUnboundLegacySessionsChecked()
    }

    static func save(_ codes: SkywardSessionCodes) throws {
        guard let accountIdentifier = CredentialStore.currentAccountIdentifier else {
            throw SkywardError.missingSession
        }
        try save(codes, accountIdentifier: accountIdentifier)
    }

    static func load(accountIdentifier: String) -> SkywardSessionCodes? {
        invalidateUnboundLegacySessions()
        return KeychainStore.load(
            SkywardSessionCodes.self,
            service: service,
            account: scopedAccount(accountIdentifier)
        )
    }

    static func load() -> SkywardSessionCodes? {
        guard let accountIdentifier = CredentialStore.currentAccountIdentifier else { return nil }
        invalidateUnboundLegacySessions()
        return load(accountIdentifier: accountIdentifier)
    }

    static func clear(accountIdentifier: String) throws {
        try KeychainStore.remove(service: service, account: scopedAccount(accountIdentifier))
        try invalidateUnboundLegacySessionsChecked()
    }

    static func clear() throws {
        if let accountIdentifier = CredentialStore.currentAccountIdentifier {
            try clear(accountIdentifier: accountIdentifier)
        } else {
            invalidateUnboundLegacySessions()
        }
    }

    /// Old sessions carried no account identity and cannot be migrated safely.
    static func invalidateUnboundLegacySessions() {
        try? invalidateUnboundLegacySessionsChecked()
    }

    static func invalidateUnboundLegacySessionsChecked() throws {
        var firstError: Error?
        do { try KeychainStore.remove(service: service, account: unscopedLegacyAccount) }
        catch { firstError = error }
        do { try ExpoKeychainStore.remove(service: expoLegacyService, key: unscopedLegacyAccount) }
        catch { if firstError == nil { firstError = error } }
        guard firstError == nil else { throw firstError! }
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    private static func scopedAccount(_ accountIdentifier: String) -> String {
        "account.\(accountIdentifier)"
    }
}

enum SessionPersistencePolicy {
    static func permitsSave(
        requestedCredentials: SkywardCredentials,
        currentCredentials: SkywardCredentials?,
        isCancelled: Bool,
        requestGeneration: Int,
        currentGeneration: Int
    ) -> Bool {
        !isCancelled
            && requestGeneration == currentGeneration
            && currentCredentials == requestedCredentials
    }
}

enum AuthenticationRequestPolicy {
    static func permitsCompletion(
        isCancelled: Bool,
        requestGeneration: Int,
        currentGeneration: Int
    ) -> Bool {
        !isCancelled && requestGeneration == currentGeneration
    }
}

struct CredentialSaveOwnership {
    private(set) var activeID: UUID?

    mutating func begin() -> UUID {
        let id = UUID()
        activeID = id
        return id
    }

    func owns(_ id: UUID) -> Bool {
        activeID == id
    }

    mutating func finish(_ id: UUID) {
        if activeID == id { activeID = nil }
    }

    mutating func cancel() {
        activeID = nil
    }
}

/// Prevents a cache written for one student from ever being readable after an
/// interrupted account replacement makes another student's credentials active.
enum AccountCacheNamespace {
    static func key(base: String, accountIdentifier: String?) -> String? {
        guard let accountIdentifier, !accountIdentifier.isEmpty else { return nil }
        return "\(base).account.\(accountIdentifier)"
    }
}

/// Small JSON cache with timestamps, mirroring the AsyncStorage caches in the legacy app.
struct JSONCacheRecord<Value> {
    var value: Value
    var updatedAt: Date
    var isFresh: Bool
}

enum JSONCache {
    static func save<T: Encodable>(_ value: T, key: String, updatedAt: Date = Date()) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.set(updatedAt.timeIntervalSince1970, forKey: key + ".timestamp")
        }
    }

    /// Reads a cache entry even after expiry so callers can deliberately use
    /// last-known-good data after a failed network refresh. Freshness remains
    /// explicit; an expired entry must never masquerade as a normal success.
    static func record<T: Decodable>(
        _ type: T.Type,
        key: String,
        maxAge: TimeInterval,
        now: Date = Date()
    ) -> JSONCacheRecord<T>? {
        let stamp = UserDefaults.standard.double(forKey: key + ".timestamp")
        guard stamp > 0,
              let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data) else {
            return nil
        }
        let updatedAt = Date(timeIntervalSince1970: stamp)
        return JSONCacheRecord(
            value: value,
            updatedAt: updatedAt,
            isFresh: now.timeIntervalSince(updatedAt) < maxAge
        )
    }

    static func load<T: Decodable>(
        _ type: T.Type,
        key: String,
        maxAge: TimeInterval,
        now: Date = Date()
    ) -> T? {
        guard let record = record(type, key: key, maxAge: maxAge, now: now),
              record.isFresh else {
            return nil
        }
        return record.value
    }

    static func clear(prefix: String) {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Legacy React Native storage migration

struct LegacyMigrationReport: Equatable {
    enum Outcome: String, Equatable {
        case noStore
        case alreadyComplete
        case migrated
        case migratedAfterDiscardingInvalidState
        case needsAttention
        case discardedCorruptStore
    }

    var outcome: Outcome
    var migratedKeys: [String]
    var invalidatedKeys: [String]
    var retainedKeys: [String]
}

struct LegacyCourseBindingReport: Equatable {
    var importedAssignments: Int
    var importedFinalExamGrades: Int
    var importedShowCalculatedValues: Int
    var remainingGroups: Int
}

enum LegacyAsyncStorageMigration {
    private static let folderName = "RCTAsyncLocalStorage_V1"
    private static let manifestName = "manifest.json"
    private static let completionKey = "legacyAsyncStorageMigration.v1.complete"
    private static let pendingKeySuffix = "legacyCourseData.v1"
    private static let accountScopeMarkerKey = "__elevateLegacyAccountScope"
    private static let unboundAccountScopeMarker = "unbound"
    private static let expoManualPrefix = "manual.account."

    private static let credentialKeys: Set<String> = ["skywardUser", "skywardPass", "skywardLink"]
    private static let sessionKeys: Set<String> = [
        "dwd", "wfaacl", "encses", "User-Type", "sessionid", "skywardBaseURL",
    ]
    private static let courseDataKeys: Set<String> = ["artificialAssignments", "finalExamGrades"]
    private static let manualGradeLevels: [GradeLevel] = [.freshman, .sophomore, .junior, .senior, .allTime]

    private struct PendingCourseData: Codable {
        var assignments: [String: [WhatIfAssignment]] = [:]
        var finalExamGrades: [String: [String: Double]] = [:]
        var showCalculated: [String: Bool] = [:]

        var groupCount: Int {
            assignments.count + finalExamGrades.count + showCalculated.count
        }
    }

    private enum StoreError: LocalizedError {
        case corruptManifest
        case invalidValue(String)
        case missingExternalValue(String)

        var errorDescription: String? {
            switch self {
            case .corruptManifest:
                return "The legacy AsyncStorage manifest is corrupt."
            case .invalidValue(let key):
                return "The legacy AsyncStorage value for \(key) is invalid."
            case .missingExternalValue(let key):
                return "The legacy AsyncStorage external value for \(key) is missing."
            }
        }
    }

    private struct LegacyStore {
        let directory: URL
        var manifest: [String: Any]

        init(directory: URL) throws {
            self.directory = directory
            let manifestURL = directory.appendingPathComponent(manifestName)
            guard let data = try? Data(contentsOf: manifestURL),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let manifest = object as? [String: Any] else {
                throw StoreError.corruptManifest
            }
            self.manifest = manifest
        }

        func string(for key: String) throws -> String? {
            guard let value = manifest[key] else { return nil }
            if let inline = value as? String { return inline }
            guard value is NSNull else { throw StoreError.invalidValue(key) }
            let externalURL = directory.appendingPathComponent(Self.externalFileName(for: key))
            guard let data = try? Data(contentsOf: externalURL),
                  let external = String(data: data, encoding: .utf8) else {
                throw StoreError.missingExternalValue(key)
            }
            return external
        }

        mutating func retainOnly(_ keys: Set<String>) throws {
            let retainedManifest = manifest.filter { keys.contains($0.key) }
            let retainedFiles = Set(retainedManifest.compactMap { key, value in
                value is NSNull ? Self.externalFileName(for: key) : nil
            })

            let fileManager = FileManager.default
            for child in try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) where child.lastPathComponent != manifestName && !retainedFiles.contains(child.lastPathComponent) {
                try fileManager.removeItem(at: child)
            }

            manifest = retainedManifest
            if manifest.isEmpty {
                try fileManager.removeItem(at: directory)
                return
            }
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            try data.write(to: directory.appendingPathComponent(manifestName), options: .atomic)
        }

        mutating func setInline(_ value: String, for key: String) {
            manifest[key] = value
        }

        private static func externalFileName(for key: String) -> String {
            Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    static func defaultStoreURL(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL? {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first, let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return nil
        }
        return applicationSupport
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func migrateIfNeeded() throws -> LegacyMigrationReport {
        let migratedExpoCredentials = try CredentialStore.migrateExpoSecureStoreCredentials()
        try SessionStore.invalidateUnboundLegacySessionsChecked()
        guard let directory = defaultStoreURL() else {
            return LegacyMigrationReport(
                outcome: migratedExpoCredentials ? .migrated : .noStore,
                migratedKeys: migratedExpoCredentials ? ["expo-secure-store:skyward"] : [],
                invalidatedKeys: ["expo-secure-store:current"],
                retainedKeys: []
            )
        }
        var report = try migrate(
            at: directory,
            defaults: .standard,
            currentCredentials: CredentialStore.load,
            saveCredentials: CredentialStore.save
        )
        if migratedExpoCredentials {
            report.migratedKeys.append("expo-secure-store:skyward")
            if report.outcome == .noStore || report.outcome == .alreadyComplete {
                report.outcome = .migrated
            }
        }
        if !report.invalidatedKeys.contains("expo-secure-store:current") {
            report.invalidatedKeys.append("expo-secure-store:current")
        }
        return report
    }

    /// Injectable boundary used by tests; credential values never enter the report or defaults.
    static func migrate(
        at directory: URL,
        defaults: UserDefaults,
        currentCredentials: () -> SkywardCredentials?,
        saveCredentials: (String, String) throws -> Void
    ) throws -> LegacyMigrationReport {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return LegacyMigrationReport(
                outcome: defaults.bool(forKey: completionKey) ? .alreadyComplete : .noStore,
                migratedKeys: [], invalidatedKeys: [], retainedKeys: []
            )
        }

        var store: LegacyStore
        do {
            store = try LegacyStore(directory: directory)
        } catch StoreError.corruptManifest {
            // A corrupt manifest cannot be recovered without risking a plaintext secret copy.
            try FileManager.default.removeItem(at: directory)
            defaults.set(true, forKey: completionKey)
            return LegacyMigrationReport(
                outcome: .discardedCorruptStore,
                migratedKeys: [],
                invalidatedKeys: Array(credentialKeys.union(sessionKeys)).sorted(),
                retainedKeys: []
            )
        }

        var migrated: Set<String> = []
        let invalidated = credentialKeys.union(sessionKeys).intersection(Set(store.manifest.keys))
        var retained: Set<String> = []
        var readFailures: Set<String> = []

        func read(_ key: String) -> String? {
            do { return try store.string(for: key) }
            catch {
                readFailures.insert(key)
                return nil
            }
        }

        let legacyUsername = read("skywardUser")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyPassword = read("skywardPass")
        let retainedScopeMarker = read(accountScopeMarkerKey)
        let existingCredentials = currentCredentials()
        let hadCredentialArtifact = store.manifest["skywardUser"] != nil
            || store.manifest["skywardPass"] != nil
        let hasCompleteLegacyCredentials = legacyUsername?.isEmpty == false
            && legacyPassword?.isEmpty == false
            && !readFailures.contains("skywardUser")
            && !readFailures.contains("skywardPass")
        let discardedInvalidState = !readFailures.isDisjoint(with: credentialKeys.union(sessionKeys))
            || (hadCredentialArtifact && !hasCompleteLegacyCredentials)

        if existingCredentials == nil,
           let legacyUsername, !legacyUsername.isEmpty,
           let legacyPassword, !legacyPassword.isEmpty,
           !readFailures.contains("skywardUser"), !readFailures.contains("skywardPass") {
            try saveCredentials(legacyUsername, legacyPassword)
            migrated.formUnion(["skywardUser", "skywardPass"])
        }

        // User data is bound only to the actual native account. A partial legacy
        // username cannot invent a destination, and a conflicting legacy account
        // remains available for an explicit retry rather than crossing accounts.
        var accountIdentifier: String?
        var activeAccountIdentifier: String?
        if let existingCredentials {
            let existingScope = CredentialStore.accountIdentifier(for: existingCredentials.username)
            activeAccountIdentifier = existingScope
            if let retainedScopeMarker {
                accountIdentifier = retainedScopeMarker == existingScope ? existingScope : nil
            } else if let legacyUsername, !legacyUsername.isEmpty,
               CredentialStore.accountIdentifier(for: legacyUsername) != existingScope {
                accountIdentifier = nil
            } else {
                accountIdentifier = existingScope
            }
        } else if hasCompleteLegacyCredentials, let legacyUsername {
            accountIdentifier = CredentialStore.accountIdentifier(for: legacyUsername)
            activeAccountIdentifier = accountIdentifier
        }

        // Expo 2.0.4 writes manual academic data under the exact deterministic
        // native account hash. Only the active verified account may import its
        // scope; foreign scopes are retained for an explicit later migration.
        let allExpoScopedKeys = Set(store.manifest.keys.filter { $0.hasPrefix(expoManualPrefix) })
        let expoScopedKeys = Set(allExpoScopedKeys.compactMap { key -> String? in
            guard let parsed = parseExpoManualKey(key), parsed.scope == activeAccountIdentifier else {
                return nil
            }
            return key
        })
        retained.formUnion(allExpoScopedKeys.subtracting(expoScopedKeys))
        var expoPending = activeAccountIdentifier.map { loadPending(scope: $0, defaults: defaults) }
        for key in expoScopedKeys.sorted() {
            guard let (scope, baseKey) = parseExpoManualKey(key), let raw = read(key) else {
                retained.insert(key)
                continue
            }
            var pending = expoPending ?? PendingCourseData()
            let imported: Bool
            if baseKey == "artificialAssignments",
               let decoded = decodeAssignments(raw, accountIdentifier: scope) {
                for (sourceKey, assignments) in decoded {
                    var existing = pending.assignments[sourceKey] ?? []
                    let existingIDs = Set(existing.map(\.id))
                    existing.append(contentsOf: assignments.filter { !existingIDs.contains($0.id) })
                    pending.assignments[sourceKey] = existing
                }
                imported = true
            } else if baseKey == "finalExamGrades", let decoded = decodeFinalExamGrades(raw) {
                for (classKey, values) in decoded {
                    pending.finalExamGrades[classKey, default: [:]].merge(values) { current, _ in current }
                }
                imported = true
            } else if baseKey.hasPrefix("showCalculated_"), let value = parseBool(raw) {
                pending.showCalculated[baseKey] = value
                imported = true
            } else if baseKey.hasPrefix("savedClasses-"),
                      let classes = decodeManualClasses(raw, sourceKey: baseKey) {
                let destination = scopedKey(baseKey, scope: scope)
                let current = defaults.data(forKey: destination)
                    .flatMap { try? JSONDecoder().decode([ManualClass].self, from: $0) } ?? []
                let merge = mergeManualClasses(current: current, incoming: classes)
                defaults.set(try JSONEncoder().encode(merge.classes), forKey: destination)
                imported = merge.complete
            } else {
                imported = false
            }

            if imported {
                expoPending = pending
                migrated.insert(key)
            } else {
                retained.insert(key)
            }
        }
        if let activeAccountIdentifier, let expoPending {
            savePending(expoPending, scope: activeAccountIdentifier, defaults: defaults)
        }

        let userKeys = Set(store.manifest.keys.filter { key in
            courseDataKeys.contains(key)
                || key.hasPrefix("savedClasses-")
                || key.hasPrefix("showCalculated_")
        })

        guard let accountIdentifier else {
            retained.formUnion(userKeys)
            retained.formUnion(allExpoScopedKeys.subtracting(expoScopedKeys))
            if !retained.isEmpty {
                let scope = retainedScopeMarker
                    ?? legacyUsername.flatMap { username in
                        username.isEmpty ? nil : CredentialStore.accountIdentifier(for: username)
                    }
                    ?? unboundAccountScopeMarker
                store.setInline(scope, for: accountScopeMarkerKey)
                try store.retainOnly(retained.union([accountScopeMarkerKey]))
            } else {
                try store.retainOnly([])
            }
            return LegacyMigrationReport(
                outcome: retained.isEmpty ? .migratedAfterDiscardingInvalidState : .needsAttention,
                migratedKeys: migrated.sorted(),
                invalidatedKeys: invalidated.sorted(),
                retainedKeys: retained.sorted()
            )
        }

        var pending = loadPending(scope: accountIdentifier, defaults: defaults)

        if userKeys.contains("artificialAssignments") {
            if let raw = read("artificialAssignments"),
               let decoded = decodeAssignments(raw, accountIdentifier: accountIdentifier) {
                for (key, assignments) in decoded {
                    var existing = pending.assignments[key] ?? []
                    let existingIDs = Set(existing.map(\.id))
                    existing.append(contentsOf: assignments.filter { !existingIDs.contains($0.id) })
                    pending.assignments[key] = existing
                }
                migrated.insert("artificialAssignments")
            } else {
                retained.insert("artificialAssignments")
            }
        }

        if userKeys.contains("finalExamGrades") {
            if let raw = read("finalExamGrades"), let decoded = decodeFinalExamGrades(raw) {
                for (key, values) in decoded {
                    pending.finalExamGrades[key, default: [:]].merge(values) { current, _ in current }
                }
                migrated.insert("finalExamGrades")
            } else {
                retained.insert("finalExamGrades")
            }
        }

        for key in userKeys where key.hasPrefix("showCalculated_") {
            guard let raw = read(key), let value = parseBool(raw) else {
                retained.insert(key)
                continue
            }
            pending.showCalculated[key] = value
            migrated.insert(key)
        }

        for level in manualGradeLevels {
            let key = "savedClasses-\(level.rawValue)"
            guard userKeys.contains(key) else { continue }
            guard let raw = read(key), let classes = decodeManualClasses(raw, sourceKey: key) else {
                retained.insert(key)
                continue
            }
            let destination = scopedKey("savedClasses-\(level.rawValue)", scope: accountIdentifier)
            let current = defaults.data(forKey: destination)
                .flatMap { try? JSONDecoder().decode([ManualClass].self, from: $0) } ?? []
            let merge = mergeManualClasses(current: current, incoming: classes)
            defaults.set(try JSONEncoder().encode(merge.classes), forKey: destination)
            if merge.complete {
                migrated.insert(key)
            } else {
                retained.insert(key)
            }
        }

        savePending(pending, scope: accountIdentifier, defaults: defaults)
        if !retained.isEmpty {
            store.setInline(accountIdentifier, for: accountScopeMarkerKey)
            try store.retainOnly(retained.union([accountScopeMarkerKey]))
        } else {
            try store.retainOnly([])
        }
        if retained.isEmpty { defaults.set(true, forKey: completionKey) }
        return LegacyMigrationReport(
            outcome: !retained.isEmpty ? .needsAttention
                : discardedInvalidState ? .migratedAfterDiscardingInvalidState : .migrated,
            migratedKeys: migrated.sorted(),
            invalidatedKeys: invalidated.sorted(),
            retainedKeys: retained.sorted()
        )
    }

    static func cleanupLegacyArtifacts(accountIdentifier: String? = CredentialStore.currentAccountIdentifier) throws {
        try cleanupLegacyArtifacts(
            at: defaultStoreURL(), defaults: .standard, accountIdentifier: accountIdentifier
        )
        try CredentialStore.deleteExpoLegacyCredentials()
        try SessionStore.invalidateUnboundLegacySessionsChecked()
    }

    static func cleanupLegacyArtifacts(
        at directory: URL?,
        defaults: UserDefaults,
        accountIdentifier: String?
    ) throws {
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            do {
                var store = try LegacyStore(directory: directory)
                // Disconnect removes secrets and the active account's legacy
                // artifacts, but a sibling Expo scope may be the only copy of
                // that student's manual GPA/what-if work.
                let retainedForeignScopes = Set(store.manifest.keys.filter { key in
                    guard let parsed = parseExpoManualKey(key) else { return false }
                    return accountIdentifier == nil || parsed.scope != accountIdentifier
                })
                var retained = retainedForeignScopes
                let retainedScope = try store.string(for: accountScopeMarkerKey)
                if let retainedScope,
                   accountIdentifier == nil || retainedScope != accountIdentifier {
                    // Pre-namespace manual data is quarantined behind this
                    // non-secret scope marker. A different account's Disconnect
                    // must not erase its only recovery copy.
                    retained.formUnion(store.manifest.keys.filter { key in
                        courseDataKeys.contains(key)
                            || key.hasPrefix("savedClasses-")
                            || key.hasPrefix("showCalculated_")
                    })
                    retained.insert(accountScopeMarkerKey)
                }
                try store.retainOnly(retained)
            } catch {
                // Corrupt legacy storage cannot be retained safely because it may
                // still contain plaintext credentials or sessions.
                try FileManager.default.removeItem(at: directory)
            }
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasSuffix(".\(pendingKeySuffix)") {
            if let accountIdentifier {
                guard key == "account.\(accountIdentifier).\(pendingKeySuffix)" else { continue }
            }
            defaults.removeObject(forKey: key)
        }
        let storeStillExists = directory.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        defaults.set(!storeStillExists, forKey: completionKey)
    }

    static func bindPendingCourseData(
        to courses: [UnifiedCourseData],
        accountIdentifier: String? = CredentialStore.currentAccountIdentifier,
        defaults: UserDefaults = .standard
    ) -> LegacyCourseBindingReport {
        guard let accountIdentifier else {
            return LegacyCourseBindingReport(
                importedAssignments: 0, importedFinalExamGrades: 0,
                importedShowCalculatedValues: 0, remainingGroups: 0
            )
        }
        var pending = loadPending(scope: accountIdentifier, defaults: defaults)
        var importedAssignments = 0
        var importedFinals = 0
        var importedToggles = 0

        let eligibleCourses = courses.filter(\.hasGradebookParams)
        let coursesByLegacyKey = Dictionary(grouping: eligibleCourses, by: legacyCourseKey)
        let toggleMatchCounts = eligibleCourses.reduce(into: [String: Int]()) { counts, course in
            for key in toggleKeys(course) { counts[key, default: 0] += 1 }
        }

        for (legacyKey, matches) in coursesByLegacyKey where matches.count == 1 {
            guard let course = matches.first else { continue }
            let nativeKey = nativeClassKey(course)

            for sourceKey in pending.assignments.keys.sorted() {
                guard let assignments = pending.assignments[sourceKey],
                      assignments.allSatisfy({ sourceKey == "\(legacyKey)_\($0.term)" }) else { continue }
                let destination = scopedKey("artificialAssignments", scope: accountIdentifier)
                var all = defaults.data(forKey: destination)
                    .flatMap { try? JSONDecoder().decode([String: [WhatIfAssignment]].self, from: $0) } ?? [:]
                for assignment in assignments {
                    let key = "\(nativeKey)_\(assignment.term)"
                    if !(all[key] ?? []).contains(where: { $0.id == assignment.id }) {
                        all[key, default: []].append(assignment)
                        importedAssignments += 1
                    }
                }
                if let encoded = try? JSONEncoder().encode(all) { defaults.set(encoded, forKey: destination) }
                pending.assignments.removeValue(forKey: sourceKey)
            }

            if let legacyFinals = pending.finalExamGrades.removeValue(forKey: legacyKey) {
                let destination = scopedKey("finalExamGrades", scope: accountIdentifier)
                var all = defaults.data(forKey: destination)
                    .flatMap { try? JSONDecoder().decode([String: [String: Double]].self, from: $0) } ?? [:]
                var existing = all[nativeKey] ?? [:]
                for (exam, grade) in legacyFinals where existing[exam] == nil {
                    existing[exam] = grade
                    importedFinals += 1
                }
                all[nativeKey] = existing
                if let encoded = try? JSONEncoder().encode(all) { defaults.set(encoded, forKey: destination) }
            }

            for sourceKey in toggleKeys(course) where toggleMatchCounts[sourceKey] == 1 {
                guard let value = pending.showCalculated.removeValue(forKey: sourceKey) else { continue }
                let destination = scopedKey("showCalculated_\(nativeKey)", scope: accountIdentifier)
                if defaults.object(forKey: destination) == nil {
                    defaults.set(value, forKey: destination)
                    importedToggles += 1
                }
            }
        }

        savePending(pending, scope: accountIdentifier, defaults: defaults)
        return LegacyCourseBindingReport(
            importedAssignments: importedAssignments,
            importedFinalExamGrades: importedFinals,
            importedShowCalculatedValues: importedToggles,
            remainingGroups: pending.groupCount
        )
    }

    private static func decodeAssignments(
        _ raw: String,
        accountIdentifier: String
    ) -> [String: [WhatIfAssignment]]? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var result: [String: [WhatIfAssignment]] = [:]
        for (sourceKey, value) in object {
            guard let rows = value as? [[String: Any]] else { return nil }
            var assignments: [WhatIfAssignment] = []
            for (index, row) in rows.enumerated() {
                guard let className = nonemptyString(row["className"]),
                      let name = nonemptyString(row["name"]),
                      let term = nonemptyString(row["term"]),
                      let category = nonemptyString(row["category"]),
                      sourceKey.hasPrefix("\(className)_"), sourceKey.hasSuffix("_\(term)"),
                      let outOf = number(row["outOf"]), outOf > 0, outOf <= 1_000_000,
                      let decodedGrade = decodeOptionalNumber(row["grade"]) else { return nil }
                let grade = decodedGrade.value
                let id = nonemptyString(row["id"])
                    ?? stableIdentifier("\(accountIdentifier)|\(sourceKey)|\(index)|\(name)")
                let metaTypes = (row["meta"] as? [[String: Any]])?
                    .compactMap { nonemptyString($0["type"]) } ?? []
                let status: WhatIfAssignmentStatus = metaTypes.contains("noCount") ? .noCount
                    : metaTypes.contains("missing") ? .missing
                    : metaTypes.contains("absent") ? .absent : .counted
                assignments.append(WhatIfAssignment(
                    id: id, className: className, name: name, term: term,
                    category: category, grade: grade, outOf: outOf,
                    dueDate: (row["dueDate"] as? String) ?? "", status: status
                ))
            }
            result[sourceKey] = assignments
        }
        return result
    }

    private static func decodeFinalExamGrades(_ raw: String) -> [String: [String: Double]]? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var result: [String: [String: Double]] = [:]
        for (classKey, value) in object {
            guard let exams = value as? [String: Any] else { return nil }
            var decoded: [String: Double] = [:]
            for (exam, rawGrade) in exams where exam == "EX1" || exam == "EX2" {
                guard let grade = number(rawGrade), abs(grade) <= 1_000_000 else { return nil }
                decoded[exam] = grade
            }
            result[classKey] = decoded
        }
        return result
    }

    private static func decodeManualClasses(_ raw: String, sourceKey: String) -> [ManualClass]? {
        guard let data = raw.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var result: [ManualClass] = []
        for (index, row) in rows.enumerated() {
            guard let name = nonemptyString(row["className"])
                    ?? nonemptyString(row["courseName"])
                    ?? nonemptyString(row["name"]) else { return nil }
            let grades = row["grades"] as? [String: Any]
            guard let sm1 = decodeOptionalNumber(row["sm1"] ?? grades?["sm1"]),
                  let sm2 = decodeOptionalNumber(row["sm2"] ?? grades?["sm2"]) else { return nil }
            result.append(ManualClass(
                id: nonemptyString(row["id"]) ?? stableIdentifier("\(sourceKey)|\(index)|\(name)"),
                className: name, sm1: sm1.value, sm2: sm2.value
            ))
        }
        return result
    }

    private static func mergeManualClasses(
        current: [ManualClass],
        incoming: [ManualClass]
    ) -> (classes: [ManualClass], complete: Bool) {
        var merged = current
        var byName: [String: ManualClass] = [:]
        for existing in current {
            let name = existing.className
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if byName[name] == nil { byName[name] = existing }
        }
        var complete = true

        for candidate in incoming {
            let name = candidate.className
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if let existing = byName[name] {
                if existing.sm1 != candidate.sm1 || existing.sm2 != candidate.sm2 {
                    complete = false
                }
            } else {
                merged.append(candidate)
                byName[name] = candidate
            }
        }
        return (merged, complete)
    }

    private static func number(_ value: Any?) -> Double? {
        let parsed: Double?
        if let number = value as? NSNumber { parsed = number.doubleValue }
        else if let string = value as? String { parsed = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        else { parsed = nil }
        guard let parsed, parsed.isFinite else { return nil }
        return parsed
    }

    private struct DecodedOptionalNumber {
        var value: Double?
    }

    private static func decodeOptionalNumber(_ value: Any?) -> DecodedOptionalNumber? {
        guard let value, !(value is NSNull) else { return DecodedOptionalNumber(value: nil) }
        if let string = value as? String,
           string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DecodedOptionalNumber(value: nil)
        }
        guard let parsed = number(value) else { return nil }
        return DecodedOptionalNumber(value: parsed)
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }

    private static func parseExpoManualKey(_ key: String) -> (scope: String, baseKey: String)? {
        guard key.hasPrefix(expoManualPrefix) else { return nil }
        let remainder = String(key.dropFirst(expoManualPrefix.count))
        guard let separator = remainder.firstIndex(of: ".") else { return nil }
        let scope = String(remainder[..<separator])
        let baseKey = String(remainder[remainder.index(after: separator)...])
        guard scope.range(of: #"^[0-9a-f]{24}$"#, options: .regularExpression) != nil,
              courseDataKeys.contains(baseKey)
                || baseKey.hasPrefix("savedClasses-")
                || baseKey.hasPrefix("showCalculated_") else {
            return nil
        }
        return (scope, baseKey)
    }

    private static func stableIdentifier(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func scopedKey(_ key: String, scope: String) -> String {
        "account.\(scope).\(key)"
    }

    private static func pendingKey(scope: String) -> String {
        scopedKey(pendingKeySuffix, scope: scope)
    }

    private static func loadPending(scope: String, defaults: UserDefaults) -> PendingCourseData {
        guard let data = defaults.data(forKey: pendingKey(scope: scope)),
              let pending = try? JSONDecoder().decode(PendingCourseData.self, from: data) else {
            return PendingCourseData()
        }
        return pending
    }

    private static func savePending(_ pending: PendingCourseData, scope: String, defaults: UserDefaults) {
        let key = pendingKey(scope: scope)
        guard pending.groupCount > 0 else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(pending) { defaults.set(data, forKey: key) }
    }

    private static func legacyCourseKey(_ course: UnifiedCourseData) -> String {
        "\(course.courseName)_\(course.corNumId)_\(course.section)_\(course.gbId)"
    }

    private static func nativeClassKey(_ course: UnifiedCourseData) -> String {
        "\(course.stuId)|\(legacyCourseKey(course))"
    }

    private static func toggleKeys(_ course: UnifiedCourseData) -> [String] {
        var keys = ["showCalculated_\(course.courseName)"]
        if let courseId = course.courseId {
            keys.insert("showCalculated_\(course.courseName)_\(courseId)", at: 0)
        }
        return keys
    }
}

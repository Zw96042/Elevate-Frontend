import CryptoKit
import Foundation
import Security
import Testing
@testable import ElevateCore

@Suite("Legacy React Native storage migration", .serialized)
struct LegacyAsyncStorageMigrationTests {
    @Test("Expo SecureStore no-auth services are the explicit legacy bridge")
    func expoSecureStoreServices() {
        #expect(CredentialStore.expoLegacyService == "com.zacharywilson.elevate.skyward:no-auth")
        #expect(CredentialStore.account == "skyward")
        #expect(SessionStore.expoLegacyService == "com.zacharywilson.elevate.skyward.session:no-auth")
        let query = ExpoKeychainStore.baseQuery(
            service: CredentialStore.expoLegacyService,
            key: CredentialStore.account
        )
        #expect(query[kSecAttrAccount as String] as? Data == Data("skyward".utf8))
        #expect(query[kSecAttrGeneric as String] as? Data == Data("skyward".utf8))
    }

    @Test("A complete Expo credential record is saved before its legacy item is deleted")
    func expoCredentialMigrationOrdering() throws {
        var events: [String] = []
        let migrated = try CredentialStore.migrateCompleteLegacyCredentials(
            username: " student ", password: "password", hasCurrentCredentials: false,
            save: { username, password in
                #expect(username == "student")
                #expect(password == "password")
                events.append("save")
            },
            deleteLegacy: { events.append("delete") }
        )
        #expect(migrated)
        #expect(events == ["save", "delete"])
    }

    @Test("Incomplete Expo credentials and sessions are invalidated, never imported")
    func expoPartialCredentialInvalidation() throws {
        var saved = false
        var deleted = false
        let migrated = try CredentialStore.migrateCompleteLegacyCredentials(
            username: "student", password: nil, hasCurrentCredentials: false,
            save: { _, _ in saved = true },
            deleteLegacy: { deleted = true }
        )
        #expect(!migrated)
        #expect(!saved)
        #expect(deleted)
    }

    @Test("Inline and external values migrate without retaining plaintext secrets")
    func migratesInlineAndExternalValues() throws {
        let context = try TestContext()
        defer { context.cleanup() }

        let assignmentKey = "Algebra II_101_2_GB_Q1"
        let legacyAssignments: [String: Any] = [
            assignmentKey: [[
                "className": "Algebra II", "name": "Unit 1 retake", "term": "Q1",
                "category": "Tests", "grade": "98", "outOf": 100,
                "dueDate": "08/20/2026", "artificial": true,
            ]],
        ]
        let legacyFinals: [String: Any] = ["Algebra II_101_2_GB": ["EX1": "93"]]
        let legacyManual: [[String: Any]] = [[
            "name": "Biology", "grades": ["sm1": "91", "sm2": "94"],
        ]]
        let manifest: [String: Any] = [
            "skywardUser": "Student.One",
            "skywardPass": NSNull(),
            "sessionid": "plaintext-session",
            "artificialAssignments": try jsonString(legacyAssignments),
            "finalExamGrades": try jsonString(legacyFinals),
            "savedClasses-Senior": try jsonString(legacyManual),
            "showCalculated_Algebra II_77": "true",
            "unifiedCourseData": "private cached academic data",
        ]
        try context.writeStore(manifest: manifest, external: ["skywardPass": "correct horse battery staple"])

        var savedCredentials: (String, String)?
        let report = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL,
            defaults: context.defaults,
            currentCredentials: { nil },
            saveCredentials: { savedCredentials = ($0, $1) }
        )

        #expect(report.outcome == .migrated)
        #expect(savedCredentials?.0 == "Student.One")
        #expect(savedCredentials?.1 == "correct horse battery staple")
        #expect(!FileManager.default.fileExists(atPath: context.storeURL.path))

        let scope = CredentialStore.accountIdentifier(for: "Student.One")
        let manualData = try #require(context.defaults.data(forKey: "account.\(scope).savedClasses-Senior"))
        let manual = try JSONDecoder().decode([ManualClass].self, from: manualData)
        #expect(manual.first?.className == "Biology")
        #expect(manual.first?.sm1 == 91)

        let pendingData = try #require(context.defaults.data(forKey: "account.\(scope).legacyCourseData.v1"))
        #expect(!String(decoding: pendingData, as: UTF8.self).contains("correct horse battery staple"))

        let binding = LegacyAsyncStorageMigration.bindPendingCourseData(
            to: [try courseFixture()], accountIdentifier: scope, defaults: context.defaults
        )
        #expect(binding.importedAssignments == 1)
        #expect(binding.importedFinalExamGrades == 1)
        #expect(binding.importedShowCalculatedValues == 1)
        #expect(binding.remainingGroups == 0)

        let nativeKey = "STU|Algebra II_101_2_GB"
        let assignmentData = try #require(context.defaults.data(forKey: "account.\(scope).artificialAssignments"))
        let assignments = try JSONDecoder().decode([String: [WhatIfAssignment]].self, from: assignmentData)
        #expect(assignments["\(nativeKey)_Q1"]?.first?.name == "Unit 1 retake")

        let finalData = try #require(context.defaults.data(forKey: "account.\(scope).finalExamGrades"))
        let finals = try JSONDecoder().decode([String: [String: Double]].self, from: finalData)
        #expect(finals[nativeKey]?["EX1"] == 93)
        #expect(context.defaults.bool(forKey: "account.\(scope).showCalculated_\(nativeKey)"))
    }

    @Test("Reappearing or interrupted stores are idempotent")
    func repeatedMigrationIsIdempotent() throws {
        let context = try TestContext()
        defer { context.cleanup() }

        let assignments: [String: Any] = [
            "Algebra II_101_2_GB_Q1": [[
                "className": "Algebra II", "name": "Prediction", "term": "Q1",
                "category": "Tests", "grade": 90, "outOf": 100,
            ]],
        ]
        let manifest: [String: Any] = [
            "skywardUser": "student", "skywardPass": "password",
            "artificialAssignments": try jsonString(assignments),
        ]
        var credential: SkywardCredentials?
        var writes = 0

        for _ in 0..<2 {
            try context.writeStore(manifest: manifest)
            _ = try LegacyAsyncStorageMigration.migrate(
                at: context.storeURL,
                defaults: context.defaults,
                currentCredentials: { credential },
                saveCredentials: { username, password in
                    writes += 1
                    credential = SkywardCredentials(
                        username: username, password: password, baseURL: CredentialStore.baseURL
                    )
                }
            )
        }

        let scope = CredentialStore.accountIdentifier(for: "student")
        let binding = LegacyAsyncStorageMigration.bindPendingCourseData(
            to: [try courseFixture()], accountIdentifier: scope, defaults: context.defaults
        )
        #expect(writes == 1)
        #expect(binding.importedAssignments == 1)
        #expect(binding.remainingGroups == 0)

        let repeated = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL,
            defaults: context.defaults,
            currentCredentials: { credential },
            saveCredentials: { _, _ in writes += 1 }
        )
        #expect(repeated.outcome == .alreadyComplete)
        #expect(writes == 1)
    }

    @Test("Expo 2.0.4 account-scoped manual data crosses into only the matching native account")
    func expoScopedManualData() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let accountA = "Student.One"
        let scopeA = CredentialStore.accountIdentifier(for: accountA)
        let scopeB = CredentialStore.accountIdentifier(for: "Sibling.Two")
        let assignmentKey = "Algebra II_101_2_GB_Q1"
        let assignments: [String: Any] = [
            assignmentKey: [[
                "className": "Algebra II", "name": "Scoped prediction", "term": "Q1",
                "category": "Tests", "grade": "96", "outOf": 100,
            ]],
        ]
        let manual: [[String: Any]] = [[
            "name": "Biology", "grades": ["sm1": "91", "sm2": "94"],
        ]]
        try context.writeStore(manifest: [
            "manual.account.\(scopeA).artificialAssignments": try jsonString(assignments),
            "manual.account.\(scopeA).savedClasses-Senior": try jsonString(manual),
            "manual.account.\(scopeB).savedClasses-Senior": try jsonString(manual),
        ])
        let current = SkywardCredentials(
            username: accountA, password: "password", baseURL: CredentialStore.baseURL
        )

        let report = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL, defaults: context.defaults,
            currentCredentials: { current }, saveCredentials: { _, _ in }
        )

        #expect(report.outcome == .needsAttention)
        #expect(report.migratedKeys.contains("manual.account.\(scopeA).artificialAssignments"))
        #expect(report.retainedKeys == ["manual.account.\(scopeB).savedClasses-Senior"])
        let manualData = try #require(
            context.defaults.data(forKey: "account.\(scopeA).savedClasses-Senior")
        )
        #expect(try JSONDecoder().decode([ManualClass].self, from: manualData).first?.className == "Biology")
        #expect(context.defaults.data(forKey: "account.\(scopeB).savedClasses-Senior") == nil)

        let binding = LegacyAsyncStorageMigration.bindPendingCourseData(
            to: [try courseFixture()], accountIdentifier: scopeA, defaults: context.defaults
        )
        #expect(binding.importedAssignments == 1)
        #expect(binding.remainingGroups == 0)
        #expect(FileManager.default.fileExists(atPath: context.storeURL.path))

        // Disconnecting A must not delete B's only manual-data copy.
        try LegacyAsyncStorageMigration.cleanupLegacyArtifacts(
            at: context.storeURL, defaults: context.defaults, accountIdentifier: scopeA
        )
        #expect(FileManager.default.fileExists(atPath: context.storeURL.path))

        let sibling = SkywardCredentials(
            username: "Sibling.Two", password: "password", baseURL: CredentialStore.baseURL
        )
        let siblingReport = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL, defaults: context.defaults,
            currentCredentials: { sibling }, saveCredentials: { _, _ in }
        )
        #expect(siblingReport.migratedKeys == ["manual.account.\(scopeB).savedClasses-Senior"])
        let siblingManualData = try #require(
            context.defaults.data(forKey: "account.\(scopeB).savedClasses-Senior")
        )
        #expect(try JSONDecoder().decode([ManualClass].self, from: siblingManualData).first?.className == "Biology")
        #expect(!FileManager.default.fileExists(atPath: context.storeURL.path))
    }

    @Test("Conflicting Expo manual classes remain recoverable across repeated migration")
    func conflictingExpoManualClassesRemainRecoverable() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let username = "Student.One"
        let scope = CredentialStore.accountIdentifier(for: username)
        let sourceKey = "manual.account.\(scope).savedClasses-Senior"
        let sourceClasses: [[String: Any]] = [
            ["className": "Biology", "sm1": 91, "sm2": 92],
            ["className": "Geometry", "sm1": 88, "sm2": 89],
        ]
        try context.writeStore(manifest: [sourceKey: try jsonString(sourceClasses)])
        let destination = "account.\(scope).savedClasses-Senior"
        context.defaults.set(try JSONEncoder().encode([
            ManualClass(id: "native-biology", className: "Biology", sm1: 95, sm2: 96),
        ]), forKey: destination)
        let current = SkywardCredentials(
            username: username, password: "password", baseURL: CredentialStore.baseURL
        )

        for _ in 0..<2 {
            let report = try LegacyAsyncStorageMigration.migrate(
                at: context.storeURL, defaults: context.defaults,
                currentCredentials: { current }, saveCredentials: { _, _ in }
            )
            #expect(report.outcome == .needsAttention)
            #expect(report.retainedKeys == [sourceKey])
        }

        let nativeData = try #require(context.defaults.data(forKey: destination))
        let nativeClasses = try JSONDecoder().decode([ManualClass].self, from: nativeData)
        #expect(nativeClasses.count == 2)
        #expect(nativeClasses.first(where: { $0.className == "Biology" })?.sm1 == 95)
        #expect(nativeClasses.first(where: { $0.className == "Geometry" })?.sm1 == 88)

        let manifestData = try Data(contentsOf: context.storeURL.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let retainedRaw = try #require(manifest[sourceKey] as? String)
        let retainedRows = try #require(
            JSONSerialization.jsonObject(with: Data(retainedRaw.utf8)) as? [[String: Any]]
        )
        #expect((retainedRows.first?["sm1"] as? NSNumber)?.doubleValue == 91)
    }

    @Test("Partial credential state is explicitly discarded, not migrated")
    func partialCredentialsAreInvalidated() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        try context.writeStore(
            manifest: ["skywardUser": "student", "skywardPass": NSNull(), "sessionid": "secret"]
        )

        var writes = 0
        let report = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL,
            defaults: context.defaults,
            currentCredentials: { nil },
            saveCredentials: { _, _ in writes += 1 }
        )

        #expect(report.outcome == .migratedAfterDiscardingInvalidState)
        #expect(report.invalidatedKeys.contains("skywardPass"))
        #expect(report.invalidatedKeys.contains("sessionid"))
        #expect(writes == 0)
        #expect(!FileManager.default.fileExists(atPath: context.storeURL.path))
    }

    @Test("A corrupt manifest is explicitly discarded without a recovery copy")
    func corruptManifestIsDiscarded() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        try FileManager.default.createDirectory(at: context.storeURL, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: context.storeURL.appendingPathComponent("manifest.json"))

        let report = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL,
            defaults: context.defaults,
            currentCredentials: { nil },
            saveCredentials: { _, _ in Issue.record("Corrupt credentials must not be saved") }
        )

        #expect(report.outcome == .discardedCorruptStore)
        #expect(!FileManager.default.fileExists(atPath: context.storeURL.path))
        #expect(context.defaults.dictionaryRepresentation().keys.allSatisfy { !$0.contains("recovery") })
    }

    @Test("Disconnect cleanup removes only active-account artifacts")
    func cleanupRemovesOnlyActiveArtifacts() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let foreignScope = "abcdef0123456789abcdef01"
        let foreignKey = "manual.account.\(foreignScope).savedClasses-Senior"
        try context.writeStore(manifest: [
            "sessionid": "secret",
            foreignKey: "[{\"className\":\"Physics\",\"sm1\":91,\"sm2\":92}]",
        ])
        let scope = "account-scope"
        context.defaults.set(Data("staged".utf8), forKey: "account.\(scope).legacyCourseData.v1")
        context.defaults.set(Data("other".utf8), forKey: "account.other-scope.legacyCourseData.v1")

        try LegacyAsyncStorageMigration.cleanupLegacyArtifacts(
            at: context.storeURL, defaults: context.defaults, accountIdentifier: scope
        )

        #expect(FileManager.default.fileExists(atPath: context.storeURL.path))
        let manifestData = try Data(contentsOf: context.storeURL.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        #expect(Set(manifest.keys) == [foreignKey])
        #expect(context.defaults.data(forKey: "account.\(scope).legacyCourseData.v1") == nil)
        #expect(context.defaults.data(forKey: "account.other-scope.legacyCourseData.v1") != nil)
    }

    @Test("Ambiguous sibling courses retain pending data instead of binding the wrong student")
    func ambiguousSiblingBinding() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let assignments: [String: Any] = [
            "Algebra II_101_2_GB_Q1": [[
                "className": "Algebra II", "name": "Prediction", "term": "Q1",
                "category": "Tests", "grade": 90, "outOf": 100,
            ]],
        ]
        try context.writeStore(manifest: [
            "skywardUser": "parent", "skywardPass": "password",
            "artificialAssignments": try jsonString(assignments),
        ])
        _ = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL,
            defaults: context.defaults,
            currentCredentials: { nil },
            saveCredentials: { _, _ in }
        )
        let scope = CredentialStore.accountIdentifier(for: "parent")
        let first = try courseFixture(studentID: "CHILD-A")
        let second = try courseFixture(studentID: "CHILD-B")
        let result = LegacyAsyncStorageMigration.bindPendingCourseData(
            to: [first, second], accountIdentifier: scope, defaults: context.defaults
        )
        #expect(result.importedAssignments == 0)
        #expect(result.remainingGroups == 1)
        #expect(context.defaults.data(forKey: "account.\(scope).artificialAssignments") == nil)
    }

    @Test("A partial legacy username cannot invent a user-data destination")
    func partialCredentialsRetainUserData() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        try context.writeStore(manifest: [
            "skywardUser": "unverified-user",
            "artificialAssignments": try jsonString([String: Any]()),
        ])
        let report = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL, defaults: context.defaults,
            currentCredentials: { nil }, saveCredentials: { _, _ in }
        )
        #expect(report.outcome == .needsAttention)
        #expect(report.retainedKeys == ["artificialAssignments"])
        #expect(context.defaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasSuffix("legacyCourseData.v1") })
    }

    @Test("A retained conflicting account cannot bind to the current account on a later launch")
    func conflictingAccountRemainsIsolatedAcrossRuns() throws {
        let context = try TestContext()
        defer { context.cleanup() }
        let assignments: [String: Any] = [
            "Algebra II_101_2_GB_Q1": [[
                "className": "Algebra II", "name": "Account A prediction", "term": "Q1",
                "category": "Tests", "grade": 90, "outOf": 100,
            ]],
        ]
        try context.writeStore(manifest: [
            "skywardUser": "account-a", "skywardPass": "password-a",
            "artificialAssignments": try jsonString(assignments),
        ])
        let accountB = SkywardCredentials(
            username: "account-b", password: "password-b", baseURL: CredentialStore.baseURL
        )

        let first = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL, defaults: context.defaults,
            currentCredentials: { accountB }, saveCredentials: { _, _ in }
        )
        let second = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL, defaults: context.defaults,
            currentCredentials: { accountB }, saveCredentials: { _, _ in }
        )

        let scopeB = CredentialStore.accountIdentifier(for: accountB.username)
        #expect(first.outcome == .needsAttention)
        #expect(second.outcome == .needsAttention)
        #expect(second.retainedKeys == ["artificialAssignments"])
        #expect(context.defaults.data(forKey: "account.\(scopeB).legacyCourseData.v1") == nil)
        #expect(FileManager.default.fileExists(atPath: context.storeURL.path))

        try LegacyAsyncStorageMigration.cleanupLegacyArtifacts(
            at: context.storeURL, defaults: context.defaults, accountIdentifier: scopeB
        )
        let manifestData = try Data(contentsOf: context.storeURL.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        #expect(Set(manifest.keys) == ["artificialAssignments", "__elevateLegacyAccountScope"])
        #expect(manifest["skywardPass"] == nil)

        let afterDisconnect = try LegacyAsyncStorageMigration.migrate(
            at: context.storeURL, defaults: context.defaults,
            currentCredentials: { accountB }, saveCredentials: { _, _ in }
        )
        #expect(afterDisconnect.outcome == .needsAttention)
        #expect(afterDisconnect.retainedKeys == ["artificialAssignments"])
    }

    private func jsonString(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func courseFixture(studentID: String = "STU") throws -> UnifiedCourseData {
        let data = Data("""
        {
          "courseId": 77, "corNumId": "101", "stuId": "\(studentID)", "section": "2", "gbId": "GB",
          "courseName": "Algebra II", "semester": "fall", "termLength": "1-2",
          "currentScores": [], "historicalGrades": {}
        }
        """.utf8)
        return try JSONDecoder().decode(UnifiedCourseData.self, from: data)
    }

    private final class TestContext {
        let rootURL: URL
        let storeURL: URL
        let suiteName: String
        let defaults: UserDefaults

        init() throws {
            rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ElevateMigrationTests-\(UUID().uuidString)", isDirectory: true)
            storeURL = rootURL.appendingPathComponent("RCTAsyncLocalStorage_V1", isDirectory: true)
            suiteName = "ElevateMigrationTests.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        func writeStore(manifest: [String: Any], external: [String: String] = [:]) throws {
            if FileManager.default.fileExists(atPath: storeURL.path) {
                try FileManager.default.removeItem(at: storeURL)
            }
            try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            try data.write(to: storeURL.appendingPathComponent("manifest.json"), options: .atomic)
            for (key, value) in external {
                let fileName = Insecure.MD5.hash(data: Data(key.utf8))
                    .map { String(format: "%02x", $0) }.joined()
                try Data(value.utf8).write(to: storeURL.appendingPathComponent(fileName))
            }
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: rootURL)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}

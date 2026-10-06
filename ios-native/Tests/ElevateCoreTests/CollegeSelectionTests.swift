import Foundation
import Testing
@testable import ElevateCore

@Suite("Account-local college selection")
struct CollegeSelectionTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "CollegeSelectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func saved(_ ids: [String], version: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": version, "collegeIDs": ids])
    }

    @Test func choicesPersistInInsertionOrderWithoutDuplicates() throws {
        try withDefaults { defaults in
            let store = CollegeSelectionStore(accountIdentifier: "synthetic-a", defaults: defaults)
            #expect(store.selectedCollegeIDs.isEmpty && !store.storageUnavailable)
            #expect(store.setSelected(true, collegeID: "school-b", expectedAccountIdentifier: "synthetic-a"))
            #expect(store.setSelected(true, collegeID: "school-a", expectedAccountIdentifier: "synthetic-a"))
            #expect(store.setSelected(true, collegeID: "school-b", expectedAccountIdentifier: "synthetic-a"))
            #expect(store.selectedCollegeIDs == ["school-b", "school-a"])
            let reloaded = CollegeSelectionStore(accountIdentifier: "synthetic-a", defaults: defaults)
            #expect(reloaded.selectedCollegeIDs == ["school-b", "school-a"])
            #expect(reloaded.setSelected(false, collegeID: "school-b", expectedAccountIdentifier: "synthetic-a"))
            #expect(store.selectedCollegeIDs == ["school-a"])
            #expect(store.setSelected(true, collegeID: "school-c", expectedAccountIdentifier: "synthetic-a"))
            #expect(reloaded.selectedCollegeIDs == ["school-a", "school-c"])
            #expect(reloaded.setSelected(false, collegeID: "never-selected", expectedAccountIdentifier: "synthetic-a"))
            #expect(reloaded.selectedCollegeIDs == ["school-a", "school-c"])
        }
    }

    @Test func accountIsolationAndExpectedScopePreventStaleMutations() throws {
        try withDefaults { defaults in
            let a = CollegeSelectionStore(accountIdentifier: "synthetic-a", defaults: defaults)
            let b = CollegeSelectionStore(accountIdentifier: "synthetic-b", defaults: defaults)
            #expect(a.setSelected(true, collegeID: "school-a", expectedAccountIdentifier: "synthetic-a"))
            #expect(b.setSelected(true, collegeID: "school-b", expectedAccountIdentifier: "synthetic-b"))
            #expect(!b.setSelected(true, collegeID: "stale-choice", expectedAccountIdentifier: "synthetic-a"))
            #expect(!a.setSelected(false, collegeID: "school-a", expectedAccountIdentifier: nil))
            #expect(!a.reset(expectedAccountIdentifier: "synthetic-b"))
            #expect(!a.reset(expectedAccountIdentifier: nil))
            #expect(a.selectedCollegeIDs == ["school-a"] && b.selectedCollegeIDs == ["school-b"])
            for scope in ["", " \n"] {
                let noAccount = CollegeSelectionStore(accountIdentifier: scope, defaults: defaults)
                #expect(!noAccount.setSelected(true, collegeID: "school", expectedAccountIdentifier: scope))
                #expect(!noAccount.reset(expectedAccountIdentifier: scope))
                #expect(noAccount.selectedCollegeIDs.isEmpty && !noAccount.storageUnavailable)
                #expect(defaults.object(forKey: "account.\(scope).collegeSelection.v1") == nil)
            }
            #expect(a.reset(expectedAccountIdentifier: "synthetic-a"))
            #expect(a.selectedCollegeIDs.isEmpty && b.selectedCollegeIDs == ["school-b"])
        }
    }

    @Test func unknownCatalogIDsSurviveLoadAndCanBeRemoved() throws {
        try withDefaults { defaults in
            let key = "account.synthetic-a.collegeSelection.v1"
            defaults.set(try saved(["removed-school", "new-school", "removed-school", "other-school"]), forKey: key)
            let store = CollegeSelectionStore(accountIdentifier: "synthetic-a", defaults: defaults)
            #expect(store.selectedCollegeIDs == ["removed-school", "new-school", "other-school"])
            #expect(!store.storageUnavailable)
            #expect(store.setSelected(false, collegeID: "removed-school", expectedAccountIdentifier: "synthetic-a"))
            #expect(store.selectedCollegeIDs == ["new-school", "other-school"])
            #expect(CollegeSelectionStore(accountIdentifier: "synthetic-a", defaults: defaults).selectedCollegeIDs == ["new-school", "other-school"])
        }
    }

    @Test func corruptStorageIsPreservedUntilExplicitScopedReset() throws {
        try withDefaults { defaults in
            let key = "account.synthetic-a.collegeSelection.v1"
            let malformed = Data("unreadable selection".utf8)
            defaults.set(malformed, forKey: key)
            let store = CollegeSelectionStore(accountIdentifier: "synthetic-a", defaults: defaults)
            #expect(store.storageUnavailable && store.selectedCollegeIDs.isEmpty)
            #expect(!store.setSelected(true, collegeID: "school", expectedAccountIdentifier: "synthetic-a"))
            #expect(!store.setSelected(false, collegeID: "school", expectedAccountIdentifier: "synthetic-a"))
            #expect(!store.reset(expectedAccountIdentifier: "synthetic-b"))
            #expect(defaults.data(forKey: key) == malformed)
            #expect(store.reset(expectedAccountIdentifier: "synthetic-a"))
            #expect(!store.storageUnavailable && defaults.object(forKey: key) == nil)
            #expect(store.setSelected(true, collegeID: "school", expectedAccountIdentifier: "synthetic-a"))
            defaults.set(malformed, forKey: key)
            #expect(!store.setSelected(true, collegeID: "another-school", expectedAccountIdentifier: "synthetic-a"))
            #expect(store.storageUnavailable && defaults.data(forKey: key) == malformed)
        }
    }


import Foundation
import Testing
@testable import ElevateCore

@Suite("Timestamped JSON cache", .serialized)
struct JSONCacheTests {
    @Test("Account namespaces make interrupted credential activation fail closed")
    func accountNamespaces() {
        let accountA = AccountCacheNamespace.key(base: "unifiedCourseData", accountIdentifier: "a")
        let accountB = AccountCacheNamespace.key(base: "unifiedCourseData", accountIdentifier: "b")

        #expect(accountA == "unifiedCourseData.account.a")
        #expect(accountB == "unifiedCourseData.account.b")
        #expect(accountA != accountB)
        #expect(AccountCacheNamespace.key(base: "unifiedCourseData", accountIdentifier: nil) == nil)
    }

    @Test("Expired values remain available only as explicitly stale records")
    func staleFallbackRecord() {
        let key = "JSONCacheTests.\(UUID().uuidString)"
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        defer { JSONCache.clear(prefix: key) }

        JSONCache.save(["last known good"], key: key, updatedAt: savedAt)
        let now = savedAt.addingTimeInterval(31 * 60)
        let record = JSONCache.record(
            [String].self,
            key: key,
            maxAge: 30 * 60,
            now: now
        )

        #expect(record?.value == ["last known good"])
        #expect(record?.updatedAt == savedAt)
        #expect(record?.isFresh == false)
        #expect(JSONCache.load(
            [String].self,
            key: key,
            maxAge: 30 * 60,
            now: now
        ) == nil)
    }

    @Test("Fresh records preserve their original update timestamp")
    func freshRecord() {
        let key = "JSONCacheTests.\(UUID().uuidString)"
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        defer { JSONCache.clear(prefix: key) }

        JSONCache.save([1, 2, 3], key: key, updatedAt: savedAt)
        let now = savedAt.addingTimeInterval(5 * 60)
        let record = JSONCache.record(
            [Int].self,
            key: key,
            maxAge: 30 * 60,
            now: now
        )

        #expect(record?.value == [1, 2, 3])
        #expect(record?.updatedAt == savedAt)
        #expect(record?.isFresh == true)
        #expect(JSONCache.load(
            [Int].self,
            key: key,
            maxAge: 30 * 60,
            now: now
        ) == [1, 2, 3])
    }
}

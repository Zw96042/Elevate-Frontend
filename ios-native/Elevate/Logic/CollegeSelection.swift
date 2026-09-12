import Foundation

/// Local, ordered college choices. Catalog changes never discard saved IDs.
final class CollegeSelectionStore {
    static let maximumIDs = 512
    static let maximumIDBytes = 128
    static let maximumStorageBytes = 128 * 1_024

    private struct Saved: Codable {
        let version: Int
        let collegeIDs: [String]
    }

    private static let lock = NSLock()
    private let defaults: UserDefaults
    let accountIdentifier: String
    private let storageKey: String

    init(accountIdentifier: String, defaults: UserDefaults = .standard) {
        self.accountIdentifier = accountIdentifier
        self.defaults = defaults
        storageKey = "account.\(accountIdentifier).collegeSelection.v1"
    }

    var snapshot: (selectedIDs: [String], storageUnavailable: Bool) {
        locked {
            guard hasAccount else { return ([], false) }
            guard let ids = load() else { return ([], true) }
            return (ids, false)
        }
    }

    var selectedCollegeIDs: [String] { snapshot.selectedIDs }
    var storageUnavailable: Bool { snapshot.storageUnavailable }

    @discardableResult
    func setSelected(_ selected: Bool, collegeID: String, expectedAccountIdentifier: String?) -> Bool {
        guard hasAccount, expectedAccountIdentifier == accountIdentifier, Self.validID(collegeID) else { return false }
        return locked {
            guard var ids = load() else { return false }
            if selected {
                if ids.contains(collegeID) { return true }
                guard ids.count < Self.maximumIDs else { return false }
                ids.append(collegeID)
            } else {
                ids.removeAll { $0 == collegeID }
            }
            guard let data = try? JSONEncoder().encode(Saved(version: 1, collegeIDs: ids)),
                  data.count <= Self.maximumStorageBytes else { return false }
            defaults.set(data, forKey: storageKey)
            return true
        }
    }

    @discardableResult
    func reset(expectedAccountIdentifier: String?) -> Bool {
        guard hasAccount, expectedAccountIdentifier == accountIdentifier else { return false }
        locked { defaults.removeObject(forKey: storageKey) }
        return true
    }

    private var hasAccount: Bool {
        !accountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() -> [String]? {
        guard defaults.object(forKey: storageKey) != nil else { return [] }
        guard let data = defaults.data(forKey: storageKey), data.count <= Self.maximumStorageBytes,
              let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.version == 1,
              saved.collegeIDs.count <= Self.maximumIDs, saved.collegeIDs.allSatisfy(Self.validID) else { return nil }
        var seen: Set<String> = []
        return saved.collegeIDs.filter { seen.insert($0).inserted }
    }

    private static func validID(_ id: String) -> Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && id.utf8.count <= maximumIDBytes &&
        id.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private func locked<T>(_ body: () -> T) -> T {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return body()
    }
}

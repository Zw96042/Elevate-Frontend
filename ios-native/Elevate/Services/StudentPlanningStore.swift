import Foundation
import Observation

/// Observable account-local planning, independent of every official school cache.
@Observable @MainActor
final class StudentPlanningStore {
    private(set) var accountScope: String?
    private(set) var coursePlan = CoursePlan()
    private(set) var completedIDs: Set<String> = []
    private(set) var gradeChanges: [GradeJournalEvent] = []
    private(set) var historyUnavailable = false
    private(set) var planUnavailable = false
    private(set) var completionUnavailable = false
    private(set) var selectedCollegeIDs: [String] = []
    private(set) var collegeSelectionUnavailable = false
    private(set) var collegeSelectionError: String?
    private(set) var error: String?
    @ObservationIgnored private var completionStore: AssignmentCompletionStore?
    @ObservationIgnored private var journal: GradeJournalStore?
    @ObservationIgnored private var collegeSelectionStore: CollegeSelectionStore?

    func activate(accountScope: String?) {
        guard accountScope != self.accountScope else { reloadHistory(); reloadCollegeSelection(); return }
        self.accountScope = accountScope
        coursePlan = CoursePlan()
        completedIDs = []
        gradeChanges = []
        completionStore = nil
        journal = nil
        collegeSelectionStore = nil
        selectedCollegeIDs = []
        collegeSelectionUnavailable = false
        collegeSelectionError = nil
        error = nil
        historyUnavailable = false
        planUnavailable = false
        completionUnavailable = false
        guard let accountScope else { return }
        completionStore = AssignmentCompletionStore(accountIdentifier: accountScope)
        completedIDs = Set(completionStore?.completed.keys.map { $0 } ?? [])
        completionUnavailable = completionStore?.storageUnavailable == true
        journal = GradeJournalStore(accountIdentifier: accountScope)
        collegeSelectionStore = CollegeSelectionStore(accountIdentifier: accountScope)
        reloadCollegeSelection()
        reloadHistory()
        let key = "account.\(accountScope).coursePlan.v1"
        if UserDefaults.standard.object(forKey: key) != nil {
            if let data = UserDefaults.standard.data(forKey: key), data.count <= 2_000_000,
               let plan = try? JSONDecoder().decode(CoursePlan.self, from: data), Self.valid(plan) {
                coursePlan = plan
            } else { planUnavailable = true }
        }
    }

    func reloadHistory() {
        gradeChanges = journal?.events ?? []
        historyUnavailable = journal?.hasUnreadableHistory == true
    }

    func clearHistory(expectedAccountScope: String?) {
        guard let expectedAccountScope, expectedAccountScope == accountScope else { return }
        journal?.clearHistory(expectedAccountIdentifier: expectedAccountScope)
        reloadHistory()
    }

    @discardableResult
    func setCompleted(_ done: Bool, assignmentID: String, expectedAccountScope: String?) -> Bool {
        guard let expectedAccountScope, expectedAccountScope == accountScope else { return false }
        guard completionStore?.setCompleted(done, id: assignmentID, expectedAccountIdentifier: expectedAccountScope) == true else {
            error = "Couldn't save this personal checkmark."
            return false
        }
        completedIDs = Set(completionStore?.completed.keys.map { $0 } ?? [])
        error = nil
        return true
    }

    func clearCompletions(expectedAccountScope: String?) {
        guard let expectedAccountScope, expectedAccountScope == accountScope else { return }
        completionStore?.clear()
        completedIDs = []
        completionUnavailable = false
        error = nil
    }

    @discardableResult
    func saveCoursePlan(_ plan: CoursePlan, expectedAccountScope: String?) -> Bool {
        guard let expectedAccountScope, expectedAccountScope == accountScope else { return false }
        guard !planUnavailable, Self.valid(plan), let data = try? JSONEncoder().encode(plan), data.count <= 2_000_000 else {
            error = "Couldn't save this course plan. Check the entered courses and credits."
            return false
        }
        UserDefaults.standard.set(data, forKey: "account.\(expectedAccountScope).coursePlan.v1")
        coursePlan = plan
        error = nil
        return true
    }

    func resetCoursePlan(expectedAccountScope: String?) {
        guard let expectedAccountScope, expectedAccountScope == accountScope else { return }
        UserDefaults.standard.removeObject(forKey: "account.\(expectedAccountScope).coursePlan.v1")
        coursePlan = CoursePlan()
        planUnavailable = false
        error = nil
    }

    @discardableResult
    func setCollegeSelected(_ selected: Bool, collegeID: String, expectedAccountScope: String?) -> Bool {
        guard let expectedAccountScope, expectedAccountScope == accountScope else { return false }
        let saved = collegeSelectionStore?.setSelected(selected, collegeID: collegeID,
                                                       expectedAccountIdentifier: expectedAccountScope) == true
        reloadCollegeSelection()
        collegeSelectionError = saved ? nil : "Couldn't save your college selection."
        return saved
    }

    func resetCollegeSelection(expectedAccountScope: String?) {
        guard let expectedAccountScope, expectedAccountScope == accountScope else { return }
        guard collegeSelectionStore?.reset(expectedAccountIdentifier: expectedAccountScope) == true else { return }
        reloadCollegeSelection()
        collegeSelectionError = nil
    }

    private func reloadCollegeSelection() {
        let snapshot = collegeSelectionStore?.snapshot
        selectedCollegeIDs = snapshot?.selectedIDs ?? []
        collegeSelectionUnavailable = snapshot?.storageUnavailable == true
    }

    private static func valid(_ plan: CoursePlan) -> Bool {
        plan.isValidForStorage
    }
}

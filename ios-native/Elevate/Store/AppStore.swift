import Foundation
import Observation
import WidgetKit

/// App-wide observable state: replaces the React context providers
/// (UnifiedDataContext, BottomSheetContext, SettingSheetContext, inbox hooks).
@Observable
@MainActor
final class AppStore {
    @ObservationIgnored private var widgetSnapshotTask: Task<Void, Never>?
    @ObservationIgnored private var accountGeneration = 0
    // Credentials / auth
    var hasCredentials: Bool = CredentialStore.hasCredentials
    var isUsingSampleData = false
    var authError: String?

    // Unified course data
    var courses: [UnifiedCourseData]?
    var coursesLoading = false
    var coursesError: String?
    var coursesLastUpdated: Date?

    // Term selection (shared by Courses tab and class detail, like BottomSheetContext)
    var selectedTerm: TermLabel = AcademicCalendar.currentTerm()

    // Grade level
    var selectedGradeLevel: GradeLevel = .senior

    // Inbox
    var messages: [SkywardMessage] = []
    var messagesLoading = false
    var messagesLoadingMore = false
    var messagesError: String?
    var messagesPaginationError: String?
    var messagesLastUpdated: Date?
    @ObservationIgnored private var hasLoadedMessages = false
    @ObservationIgnored private var messagesExhausted = false
    @ObservationIgnored private var messagePaginationCursor: String?

    init() {
        #if DEBUG
        if !hasCredentials || ProcessInfo.processInfo.arguments.contains("-SampleData") {
            isUsingSampleData = true
            courses = SampleData.courses
            messages = SampleData.messages
            hasLoadedMessages = true
            selectedGradeLevel = .senior
            coursesLastUpdated = Date()
            messagesLastUpdated = Date()
            SampleData.install()
        }
        #endif
    }

    // MARK: - Derived

    var canShowData: Bool { hasCredentials || isUsingSampleData }

    var availableGradeLevels: [GradeLevel] {
        guard let courses else { return GradeLevel.allCases }
        guard !courses.isEmpty else { return GradeLevel.allCases.filter { $0 != .current } }
        let years = Set(courses.compactMap(\.gradeYear)).sorted()
        var levels = years.map(GradeLevel.from(gradeYear:))
        if courses.contains(where: { $0.gradeYear == nil }) { levels.append(.current) }
        if levels.count > 1 { levels.append(.allTime) }
        return levels
    }

    var currentGradeLevel: GradeLevel {
        guard let courses else { return .senior }
        if let maxYear = courses.compactMap(\.gradeYear).max() {
            return GradeLevel.from(gradeYear: maxYear)
        }
        return courses.contains(where: { $0.gradeYear == nil }) ? .current : .senior
    }

    func courses(for level: GradeLevel) -> [UnifiedCourseData] {
        guard let courses else { return [] }
        if level == .current { return courses.filter { $0.gradeYear == nil } }
        guard let year = level.gradeYear else { return courses }
        return courses.filter { $0.gradeYear == year }
    }

    /// Courses shown on the Courses tab: current grade level, valid gradebook
    /// params, filtered to the semester containing the selected term.
    var visibleCourses: [UnifiedCourseData] {
        let base = courses(for: currentGradeLevel).filter(\.hasGradebookParams)
        let targets: Set<Semester> = selectedTerm.isFall ? [.fall, .both] : [.spring, .both]
        return base.filter { $0.semester == .unknown || targets.contains($0.semester) }
    }

    // MARK: - Actions

    func saveCredentials(username: String, password: String) async -> Bool {
        let previousAccount = CredentialStore.currentAccountIdentifier
        let credentials = SkywardCredentials(
            username: username,
            password: password,
            baseURL: CredentialStore.baseURL
        )
        do {
            let codes = try await AuthService.verify(credentials: credentials)
            try SessionStore.save(codes)
            do {
                try CredentialStore.save(username: username, password: password)
            } catch {
                try? SessionStore.clear()
                throw error
            }
            let newAccount = CredentialStore.accountIdentifier(for: username)
            if let previousAccount, previousAccount != newAccount {
                WhatIfStore.clearAccountData(scope: previousAccount)
            }
            isUsingSampleData = false
            await clearAccountScopedData()
            hasCredentials = true
            authError = nil
            Task {
                await refreshCourses(force: true)
                await refreshMessages(force: true)
            }
            return true
        } catch {
            authError = error.localizedDescription
            hasCredentials = CredentialStore.hasCredentials
            return false
        }
    }

    func refreshCourses(force: Bool = false) async {
        #if DEBUG
        if isUsingSampleData {
            courses = SampleData.courses
            coursesLastUpdated = Date()
            SampleData.install()
            return
        }
        #endif
        guard hasCredentials else { return }
        let generation = accountGeneration
        coursesLoading = courses == nil || force
        coursesError = nil
        do {
            let result = try await DataService.shared.combinedCourses(forceRefresh: force)
            guard generation == accountGeneration else { return }
            courses = result
            coursesLastUpdated = Date()
            if !availableGradeLevels.contains(selectedGradeLevel) {
                selectedGradeLevel = currentGradeLevel
            }
            updateWidgetSnapshot()
        } catch {
            if generation == accountGeneration {
                coursesError = error.localizedDescription
            }
        }
        if generation == accountGeneration { coursesLoading = false }
    }

    func refreshMessages(force: Bool = false) async {
        #if DEBUG
        if isUsingSampleData {
            messages = SampleData.messages
            hasLoadedMessages = true
            SampleData.install()
            return
        }
        #endif
        guard hasCredentials else { return }
        let generation = accountGeneration
        if messages.isEmpty || force {
            messagesLoading = messages.isEmpty
        }
        messagesError = nil
        messagesPaginationError = nil
        do {
            let result = try await DataService.shared.loadMessages()
            guard generation == accountGeneration else { return }
            messages = result
            hasLoadedMessages = true
            messagesLastUpdated = Date()
            messagesExhausted = result.isEmpty
            messagePaginationCursor = nil
            updateWidgetSnapshot()
        } catch {
            if generation == accountGeneration {
                messagesError = error.localizedDescription
            }
        }
        if generation == accountGeneration { messagesLoading = false }
    }

    /// Rebuilds the shared widget snapshot in the background.
    private func updateWidgetSnapshot() {
        guard let courses, hasLoadedMessages else { return }
        let messages = messages
        widgetSnapshotTask?.cancel()
        widgetSnapshotTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            await WidgetSnapshotBuilder.refresh(courses: courses, messages: messages)
        }
    }

    func loadMoreMessages() async {
        guard !isUsingSampleData else { return }
        guard !messagesLoadingMore, !messagesExhausted,
              let last = messages.last, !last.messageRowId.isEmpty,
              messagePaginationCursor != last.messageRowId else { return }
        let generation = accountGeneration
        messagePaginationCursor = last.messageRowId
        messagesPaginationError = nil
        messagesLoadingMore = true
        defer { messagesLoadingMore = false }
        do {
            let more = try await DataService.shared.loadMoreMessages(after: last.messageRowId, limit: 6)
            guard generation == accountGeneration else { return }
            let existingIds = Set(messages.map(\.id))
            let unique = more.filter { !existingIds.contains($0.id) }
            if more.isEmpty || unique.isEmpty {
                messagesExhausted = true
            } else {
                messages.append(contentsOf: unique)
            }
        } catch {
            if generation == accountGeneration {
                messagePaginationCursor = nil
                messagesPaginationError = error.localizedDescription
            }
        }
    }

    func clearAllCaches() async {
        #if DEBUG
        if isUsingSampleData {
            courses = SampleData.courses
            messages = SampleData.messages
            coursesLastUpdated = Date()
            messagesLastUpdated = Date()
            SampleData.install()
            return
        }
        #endif
        guard hasCredentials else { return }
        await DataService.shared.clearCaches()
        async let courses: Void = refreshCourses(force: true)
        async let messages: Void = refreshMessages(force: true)
        _ = await (courses, messages)
    }

    func disconnect() async throws {
        let account = CredentialStore.currentAccountIdentifier
        try SessionStore.clear()
        try CredentialStore.clear()
        SkywardHTTP.clearCookies()
        WhatIfStore.clearAccountData(scope: account)
        await clearAccountScopedData()

        hasCredentials = false
        isUsingSampleData = false
        authError = nil
        coursesLastUpdated = nil
        messagesLastUpdated = nil
        selectedTerm = AcademicCalendar.currentTerm()
        selectedGradeLevel = .senior
    }

    private func clearAccountScopedData() async {
        accountGeneration += 1
        widgetSnapshotTask?.cancel()
        await DataService.shared.clearCaches()
        courses = nil
        messages = []
        coursesError = nil
        messagesError = nil
        messagesPaginationError = nil
        hasLoadedMessages = false
        messagesExhausted = false
        messagePaginationCursor = nil
        coursesLastUpdated = nil
        messagesLastUpdated = nil
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import Foundation
import Observation
import WidgetKit

/// App-wide observable state: replaces the React context providers
/// (UnifiedDataContext, BottomSheetContext, SettingSheetContext, inbox hooks).
@Observable
@MainActor
final class AppStore {
    @ObservationIgnored private var widgetSnapshotTask: Task<Void, Never>?
    @ObservationIgnored private var coursesRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var messagesRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var foregroundRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var coursesRefreshIsForced = false
    @ObservationIgnored private var coursesRefreshID: UUID?
    @ObservationIgnored private var messagesRefreshID: UUID?
    @ObservationIgnored private var foregroundRefreshID: UUID?
    @ObservationIgnored private var hasStartedForegroundHydration = false
    @ObservationIgnored private var lastAutomaticallySelectedTerm: TermLabel?
    @ObservationIgnored private var accountGeneration = 0
    @ObservationIgnored private var credentialSaveOwnership = CredentialSaveOwnership()
    private static let foregroundRefreshMaxAge: TimeInterval = 15 * 60
    // Credentials / auth
    var hasCredentials = false
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
        lastAutomaticallySelectedTerm = selectedTerm
        do {
            _ = try LegacyAsyncStorageMigration.migrateIfNeeded()
        } catch {
            authError = error.localizedDescription
        }
        hasCredentials = CredentialStore.hasCredentials

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
        let saveID = credentialSaveOwnership.begin()
        let previousAccount = CredentialStore.currentAccountIdentifier
        let requestGeneration = accountGeneration
        let credentials = SkywardCredentials(
            username: username,
            password: password,
            baseURL: CredentialStore.baseURL
        )
        let newAccount = CredentialStore.accountIdentifier(for: username)
        if let previousAccount, previousAccount != newAccount {
            SkywardHTTP.clearCookies()
        }
        do {
            let codes = try await AuthService.verify(credentials: credentials)
            guard AuthenticationRequestPolicy.permitsCompletion(
                isCancelled: Task.isCancelled,
                requestGeneration: requestGeneration,
                currentGeneration: accountGeneration
            ), credentialSaveOwnership.owns(saveID) else {
                throw CancellationError()
            }
            // Make old UI, disk caches, and widget data unreachable before a
            // replacement identity becomes authoritative in Keychain. A crash
            // during the remaining writes can therefore expose no prior data.
            hasCredentials = false
            isUsingSampleData = false
            await clearAccountScopedData()
            guard credentialSaveOwnership.owns(saveID) else {
                throw CancellationError()
            }
            SkywardHTTP.clearCookies()

            if let previousAccount, previousAccount != newAccount {
                // Verification has succeeded, so the replacement session is
                // ready to become authoritative. Remove the old account's
                // secret even if the later credential write has to fall back
                // to re-authenticating that unchanged account.
                try SessionStore.clear(accountIdentifier: previousAccount)
            }
            try SessionStore.save(codes, accountIdentifier: newAccount)
            do {
                try CredentialStore.save(username: username, password: password)
            } catch {
                try? SessionStore.clear(accountIdentifier: newAccount)
                throw error
            }
            // A prior Expo install may retain manual data for multiple account
            // scopes. Activating one of those accounts is the explicit signal
            // that its matching scope may now be imported.
            _ = try? LegacyAsyncStorageMigration.migrateIfNeeded()
            if let previousAccount, previousAccount != newAccount {
                WhatIfStore.clearAccountData(scope: previousAccount)
            }
            hasCredentials = true
            authError = nil
            credentialSaveOwnership.finish(saveID)
            Task {
                await refreshCourses(force: true)
                await refreshMessages(force: true)
            }
            return true
        } catch {
            if credentialSaveOwnership.owns(saveID) {
                credentialSaveOwnership.finish(saveID)
                authError = error.localizedDescription
                hasCredentials = CredentialStore.hasCredentials
            }
            return false
        }
    }

    func refreshCourses(force: Bool = false) async {
        if let task = coursesRefreshTask {
            let activeRefreshID = coursesRefreshID
            let needsForcedFollowUp = force && !coursesRefreshIsForced
            await task.value
            if needsForcedFollowUp {
                if coursesRefreshID == activeRefreshID {
                    coursesRefreshTask = nil
                    coursesRefreshID = nil
                    coursesRefreshIsForced = false
                }
                await refreshCourses(force: true)
            }
            return
        }

        coursesRefreshIsForced = force
        let refreshID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefreshCourses(force: force)
        }
        coursesRefreshID = refreshID
        coursesRefreshTask = task
        await task.value
        if coursesRefreshID == refreshID {
            coursesRefreshTask = nil
            coursesRefreshID = nil
            coursesRefreshIsForced = false
        }
    }

    private func performRefreshCourses(force: Bool) async {
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
        let diskFallback = DataService.shared.cachedCourses()
        coursesLoading = courses == nil || force
        coursesError = nil
        do {
            let diskDataExceedsForegroundAge = diskFallback.map {
                Date().timeIntervalSince($0.updatedAt) >= Self.foregroundRefreshMaxAge
            } ?? false
            let result = try await DataService.shared.combinedCourses(
                forceRefresh: force || diskDataExceedsForegroundAge
            )
            guard generation == accountGeneration else { return }
            courses = result
            coursesLastUpdated = DataService.shared.cachedCourses()?.updatedAt ?? Date()
            if !availableGradeLevels.contains(selectedGradeLevel) {
                selectedGradeLevel = currentGradeLevel
            }
        } catch {
            if generation == accountGeneration {
                if let diskFallback {
                    courses = diskFallback.value
                    coursesLastUpdated = diskFallback.updatedAt
                    if !availableGradeLevels.contains(selectedGradeLevel) {
                        selectedGradeLevel = currentGradeLevel
                    }
                }
                coursesError = error.localizedDescription
            }
        }
        if generation == accountGeneration { coursesLoading = false }
        updateWidgetSnapshot()
    }

    func refreshMessages(force: Bool = false) async {
        if let task = messagesRefreshTask {
            await task.value
            return
        }

        let refreshID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefreshMessages(force: force)
        }
        messagesRefreshID = refreshID
        messagesRefreshTask = task
        await task.value
        if messagesRefreshID == refreshID {
            messagesRefreshTask = nil
            messagesRefreshID = nil
        }
    }

    private func performRefreshMessages(force: Bool) async {
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
        let diskFallback = DataService.shared.cachedMessages()
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
            messagesLastUpdated = DataService.shared.cachedMessages()?.updatedAt ?? Date()
            messagesExhausted = result.isEmpty
            messagePaginationCursor = nil
        } catch {
            if generation == accountGeneration {
                if let diskFallback {
                    messages = diskFallback.value
                    hasLoadedMessages = true
                    messagesLastUpdated = diskFallback.updatedAt
                    messagesExhausted = diskFallback.value.isEmpty
                    messagePaginationCursor = nil
                }
                messagesError = error.localizedDescription
            }
        }
        if generation == accountGeneration { messagesLoading = false }
        updateWidgetSnapshot()
    }

    /// Entry point for scene activation. The first activation hydrates state;
    /// later activations refresh only data older than the foreground threshold.
    /// Repeated active notifications join the same task.
    func handleSceneBecameActive(now: Date = Date()) async {
        let currentTerm = AcademicCalendar.currentTerm(for: now)
        if let lastAutomaticallySelectedTerm {
            selectedTerm = TermSelectionPolicy.selectionOnActivation(
                selected: selectedTerm,
                current: currentTerm,
                lastAutomatic: lastAutomaticallySelectedTerm
            )
        }
        lastAutomaticallySelectedTerm = currentTerm
        guard canShowData else { return }
        if let foregroundRefreshTask {
            await foregroundRefreshTask.value
            return
        }

        let isInitialHydration = !hasStartedForegroundHydration
        hasStartedForegroundHydration = true
        let refreshCourses = needsForegroundRefresh(lastUpdated: coursesLastUpdated, now: now)
        let refreshMessages = needsForegroundRefresh(lastUpdated: messagesLastUpdated, now: now)
        guard refreshCourses || refreshMessages else { return }

        let refreshID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            if refreshCourses, refreshMessages {
                async let courses: Void = self.refreshCourses(force: !isInitialHydration)
                async let messages: Void = self.refreshMessages(force: !isInitialHydration)
                _ = await (courses, messages)
            } else if refreshCourses {
                await self.refreshCourses(force: !isInitialHydration)
            } else {
                await self.refreshMessages(force: !isInitialHydration)
            }
        }
        foregroundRefreshID = refreshID
        foregroundRefreshTask = task
        await task.value
        if foregroundRefreshID == refreshID {
            foregroundRefreshTask = nil
            foregroundRefreshID = nil
        }
    }

    private func needsForegroundRefresh(lastUpdated: Date?, now: Date) -> Bool {
        guard let lastUpdated else { return true }
        return now.timeIntervalSince(lastUpdated) >= Self.foregroundRefreshMaxAge
    }

    /// Rebuilds the shared widget snapshot in the background.
    private func updateWidgetSnapshot() {
        let courses = courses
        let messages = hasLoadedMessages ? messages : nil
        let coursesUpdatedAt = coursesLastUpdated
        let messagesUpdatedAt = messagesLastUpdated
        let coursesAreComplete = courses != nil && coursesError == nil
        let messagesAreComplete = hasLoadedMessages && messagesError == nil
        widgetSnapshotTask?.cancel()
        widgetSnapshotTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            await WidgetSnapshotBuilder.refresh(
                courses: courses,
                coursesUpdatedAt: coursesUpdatedAt,
                coursesAreComplete: coursesAreComplete,
                messages: messages,
                messagesUpdatedAt: messagesUpdatedAt,
                messagesAreComplete: messagesAreComplete
            )
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
        credentialSaveOwnership.cancel()
        let account = CredentialStore.currentAccountIdentifier
        // Stop every account-bound task before removing secrets. Otherwise an
        // authentication completing between session and credential deletion
        // could repopulate the just-cleared account session.
        await invalidateAccountScopedWork()
        try LegacyAsyncStorageMigration.cleanupLegacyArtifacts(accountIdentifier: account)
        if let account {
            try SessionStore.clear(accountIdentifier: account)
        }
        try CredentialStore.clear()
        SkywardHTTP.clearCookies()
        WhatIfStore.clearAccountData(scope: account)
        await resetAccountScopedState()

        hasCredentials = false
        isUsingSampleData = false
        authError = nil
        coursesLastUpdated = nil
        messagesLastUpdated = nil
        selectedGradeLevel = .senior
    }

    private func clearAccountScopedData() async {
        await invalidateAccountScopedWork()
        await resetAccountScopedState()
    }

    private func invalidateAccountScopedWork() async {
        accountGeneration += 1
        foregroundRefreshTask?.cancel()
        coursesRefreshTask?.cancel()
        messagesRefreshTask?.cancel()
        widgetSnapshotTask?.cancel()
        foregroundRefreshTask = nil
        coursesRefreshTask = nil
        messagesRefreshTask = nil
        foregroundRefreshID = nil
        coursesRefreshID = nil
        messagesRefreshID = nil
        coursesRefreshIsForced = false
        hasStartedForegroundHydration = false
        await DataService.shared.clearCaches()
        await DataService.shared.cancelAuthentication()
    }

    private func resetAccountScopedState() async {
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
        selectedTerm = AcademicCalendar.currentTerm()
        lastAutomaticallySelectedTerm = selectedTerm
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import Foundation
import Observation
import WidgetKit

/// App-wide observable state: replaces the React context providers
/// (UnifiedDataContext, BottomSheetContext, SettingSheetContext, inbox hooks).
@Observable
@MainActor
final class AppStore {
    let notifications = SchoolNotifications.shared
    let planning = StudentPlanningStore()
    var localAccountScope: String? { canShowData ? (isUsingSampleData ? "sample" : CredentialStore.currentAccountIdentifier) : nil }
    @ObservationIgnored private var previewFileURL: URL?
    @ObservationIgnored private var documentOpenID: UUID?
    @ObservationIgnored private var documentOpenTask: Task<Void, Never>?
    @ObservationIgnored private var widgetSnapshotTask: Task<Void, Never>?
    @ObservationIgnored private var widgetSnapshotID: UUID?
    @ObservationIgnored private var widgetSnapshotLastAttempt: Date?
    @ObservationIgnored private var coursesRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var messagesRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var attendanceRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var attendanceRefreshID: UUID?
    @ObservationIgnored private var attendanceRefreshIsForced = false
    @ObservationIgnored private var attendanceLastAttempt: Date?
    @ObservationIgnored private var feesRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var feesRefreshID: UUID?
    @ObservationIgnored private var feesRefreshIsForced = false
    @ObservationIgnored private var studentInfoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var studentInfoRefreshID: UUID?
    @ObservationIgnored private var studentInfoRefreshIsForced = false
    @ObservationIgnored private var documentsRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var documentsRefreshID: UUID?
    @ObservationIgnored private var documentsRefreshIsForced = false
    /// One in-flight load per quarter; joiners wait on the same task.
    @ObservationIgnored private var calendarRefreshes: [TermLabel: CalendarRefreshEntry] = [:]
    private struct CalendarRefreshScope: Equatable {
        var generation: Int
        var term: TermLabel
        var coursesRevision: Int
        var courses: [UnifiedCourseData]
    }
    private struct CalendarRefreshEntry {
        var task: Task<Void, Never>
        var id: UUID
        var isForced: Bool
        var scope: CalendarRefreshScope
    }
    #if DEBUG
    @ObservationIgnored private var calendarRevisionPreviewInjected = false
    #endif
    @ObservationIgnored private var foregroundRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var coursesRefreshIsForced = false
    @ObservationIgnored private var coursesRefreshID: UUID?
    @ObservationIgnored private var messagesRefreshID: UUID?
    @ObservationIgnored private var foregroundRefreshID: UUID?
    @ObservationIgnored private var hasStartedForegroundHydration = false
    @ObservationIgnored private var lastAutomaticallySelectedTerm: TermLabel?
    @ObservationIgnored private var lastAutomaticallySelectedCalendarTerm: TermLabel?
    @ObservationIgnored private var accountGeneration = 0
    @ObservationIgnored private var credentialSaveOwnership = CredentialSaveOwnership()
    static let automaticRefreshInterval = AutomaticRefreshPolicy.interval
    var automaticRefreshInterval: TimeInterval {
        #if DEBUG
        if isUsingSampleData,
           ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-FastAutomaticRefresh") { return 3 }
        #endif
        return Self.automaticRefreshInterval
    }
    var coursesRefreshRevision = 0
    var messagesRefreshRevision = 0
    @ObservationIgnored private var courseGradeTracker: GradeChangeTracker?
    @ObservationIgnored private var courseGradeTrackerScope: String?
    private var observedCourseGradeTerm: TermLabel?
    private var courseGradeChanges: [String: Double] = [:]
    @ObservationIgnored private var messageFeedGeneration = 0

    #if DEBUG
    private var sampleCourses: [UnifiedCourseData] {
        var result = SampleData.courses
        if ProcessInfo.processInfo.arguments.contains("-SevenCourses") {
            result.removeAll { $0.period == 5 }
        }
        if ProcessInfo.processInfo.arguments.contains("-UppercaseSampleTeachers") {
            for index in result.indices { result[index].instructor = result[index].instructor?.uppercased() }
        }
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-CourseRingEdgePreview") {
            let indices = result.indices.filter { result[$0].gradeYear == 12 }
            for (offset, index) in indices.prefix(4).enumerated() {
                result[index].currentScores.removeAll { $0.bucket == "Q1" }
                result[index].historicalGrades.rc1 = nil
                if offset < 3 {
                    let score = [100.7, 103.75, 0.0][offset]
                    result[index].currentScores.append(.init(bucket: "Q1", score: score))
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-PastCoursesCleanupPreview"),
           let template = result.first(where: { $0.gradeYear == 11 }) {
            result.removeAll { $0.gradeYear == 11 }
            func entry(_ name: String, _ key: String, _ semester: Semester, _ grades: HistoricalGrades) -> UnifiedCourseData {
                var course = template
                course.courseName = name
                course.historyRowKey = key
                course.semester = semester
                course.currentScores = []
                course.historicalGrades = grades
                course.postedHistoricalGrades = grades
                return course
            }
            result += [
                entry("STUDIO ART", "art-fall", .fall, .init(rc1: "88", rc2: "91", sm1: "90")),
                entry("STUDIO ART", "art-spring", .spring, .init(rc3: "93", rc4: "95", sm2: "94")),
                entry("SCIENCE H", "science-dropped", .both, .init()),
                entry("WORLD LANGUAGE LOTE", "language", .both, .init(sm1: "P", sm2: "P")),
            ]
        }
        if isUsingSampleData,
           ProcessInfo.processInfo.arguments.contains("-SampleData"),
           (ProcessInfo.processInfo.arguments.contains("-HigherSampleGrades") ||
            (ProcessInfo.processInfo.arguments.contains("-HigherSampleGradesAfterRefresh") && coursesRefreshRevision >= 6)),
           let courseIndex = result.firstIndex(where: { $0.gradeYear == 12 }),
           let scoreIndex = result[courseIndex].currentScores.firstIndex(where: { $0.bucket == "Q1" }) {
            result[courseIndex].currentScores[scoreIndex].score += 1
        }
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           let flag = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-PreviewStudentGrade=") }),
           let year = Int(flag.replacingOccurrences(of: "-PreviewStudentGrade=", with: "")),
           (9...12).contains(year) {
            result.removeAll { ($0.gradeYear ?? year) > year }
        }
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-AutomaticCreditPreview"), !result.isEmpty {
            func record(_ name: String, _ year: String, _ grade: Int, _ terms: String = "1-4",
                        _ fall: String? = "95", _ spring: String? = "96") -> PlanningTranscriptCourse {
                PlanningTranscriptCourse(academicYear: year, gradeYear: grade, name: name,
                    terms: terms, sm1: fall, sm2: spring, ex1: nil, ex2: nil)
            }
            result[0].planningTranscriptCourses = [
                record("English I", "2023-2024", 9),
                record("English II", "2024-2025", 10),
                record("AP English Language and Composition", "2025-2026", 11),
                record("Algebra I", "2022-2023", 8),
                record("Biology", "2023-2024", 9),
                record("AP World History", "2024-2025", 10),
                record("Spanish I", "2022-2023", 8),
                record("Physical Education", "2023-2024", 9),
                record("Health", "2024-2025", 10, "1-2", "95", nil),
                record("AP Art History", "2025-2026", 11),
                record("Robotics II", "2025-2026", 11),
                record("Unrecognized elective", "2024-2025", 10, "1-2", "P", nil),
            ]
        }
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-PerfectCollegePreview") {
            for index in result.indices where (result[index].gradeYear ?? 12) < 12 {
                result[index].historicalGrades.sm1 = "100"
                result[index].historicalGrades.sm2 = "100"
                result[index].postedHistoricalGrades = result[index].historicalGrades
            }
        }
        return result
    }
    #endif
    @ObservationIgnored private var coursesLastAttempt: Date?
    @ObservationIgnored private var messagesLastAttempt: Date?
    var isAuthenticating = false
    var accountRevision: Int { accountGeneration }
    // Credentials / auth
    var hasCredentials = false
    var isUsingSampleData = false
    var authError: String?

    // Unified course data
    /// Planning rows travel with the same account-scoped course snapshot, but
    /// never enter Courses, GPA, notifications or widget inputs.
    private(set) var planningTranscriptCourses: [PlanningTranscriptCourse]?
    private(set) var courses: [UnifiedCourseData]?

    private func assignCourseSnapshot(_ snapshot: [UnifiedCourseData]?) {
        planningTranscriptCourses = snapshot?.compactMap(\.planningTranscriptCourses).first
        courses = snapshot?.filter { $0.isPlanningOnly != true }
    }
    var coursesLoading = false
    var coursesError: String?
    var coursesLastUpdated: Date?

    // Attendance loads independently when its page is visited.
    var attendance: AttendanceData?
    var attendanceLoading = false
    var attendanceError: String?
    var attendanceLastUpdated: Date?

    // Calendar requests are quarter scoped and independent of Courses
    // selection. Each quarter loads on its own, when a page needs its dates,
    // and keeps its own saved data, error and timestamp.
    var calendarQuarters: [TermLabel: CalendarQuarterState] = [:] {
        didSet {
            // Any change to a quarter's saved rows, including one class's
            // grades while another keeps old data, bumps this; loading flags
            // and errors alone don't.
            if oldValue.mapValues(\.data) != calendarQuarters.mapValues(\.data) { calendarDataRevision &+= 1 }
        }
    }
    /// Changes whenever any quarter's saved assignments change, so a page can
    /// rebuild what it draws once per change.
    private(set) var calendarDataRevision = 0

    func calendarQuarter(_ term: TermLabel) -> CalendarQuarterState {
        calendarQuarters[SchoolCalendar.quarter(for: term)] ?? CalendarQuarterState()
    }

    /// The quarter Search works in. Changing it never discards another
    /// quarter's saved assignments.
    var calendarTerm: TermLabel = SchoolCalendar.quarter(for: AcademicCalendar.currentTerm()) {
        didSet {
            let quarter = SchoolCalendar.quarter(for: calendarTerm)
            if quarter != calendarTerm { calendarTerm = quarter }
        }
    }

    /// The selected quarter's state, for pages that work in one quarter.
    var calendarData: SchoolCalendarData? { calendarQuarter(calendarTerm).data }
    var calendarLoading: Bool { calendarQuarter(calendarTerm).isLoading }
    var calendarError: String? { calendarQuarter(calendarTerm).error }
    var calendarLastUpdated: Date? { calendarQuarter(calendarTerm).lastUpdated }

    // Account pages load independently when visited in Settings.
    var fees: FeesData?
    var feesLoading = false
    var feesError: String?
    var feesLastUpdated: Date?
    var studentInfo: StudentInfoData?
    var studentInfoLoading = false
    var studentInfoError: String?
    var studentInfoLastUpdated: Date?
    var documents: DocumentsData?
    var documentsLoading = false
    var documentsError: String?
    var documentsLastUpdated: Date?
    var documentLoadingID: String?
    var documentOpenError: String?
    var documentPreview: DocumentPreview?

    // Term selection (shared by Courses tab and class detail, like BottomSheetContext)
    var selectedTerm: TermLabel = AcademicCalendar.currentTerm()

    // Grade level
    var selectedGradeLevel: GradeLevel = .senior

    // Inbox
    var messages: [SkywardMessage] = []
    var messagesLoading = false
    var messagesRefreshing = false
    var messagesLoadingMore = false
    var messagesError: String?
    var messagesPaginationError: String?
    var messagesLastUpdated: Date?
    @ObservationIgnored private var hasLoadedMessages = false
    @ObservationIgnored private var messagesExhausted = false
    @ObservationIgnored private var messagePaginationCursor: String?

    init() {
        DocumentPreviewFiles.clear()
        selectedTerm = AcademicCalendar.currentTerm(for: Self.academicSelectionDate(Date()))
        calendarTerm = SchoolCalendar.quarter(for: selectedTerm)
        lastAutomaticallySelectedTerm = selectedTerm
        lastAutomaticallySelectedCalendarTerm = calendarTerm
        do {
            _ = try LegacyAsyncStorageMigration.migrateIfNeeded()
        } catch {
            authError = error.localizedDescription
        }
        hasCredentials = CredentialStore.hasCredentials

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-ResetFollowupData") {
            WhatIfStore.clearAccountData(scope: "sample")
        }
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-LegacyNotificationNamesPreview") {
            // Synthetic migration fixture; never touches a connected account.
            let legacy = Data(#"{"gradeChanges":false,"reminders":true,"showGradePreviews":true}"#.utf8)
            UserDefaults.standard.set(legacy, forKey: "account.sample.notifications.preferences")
        }
        if !hasCredentials || ProcessInfo.processInfo.arguments.contains("-SampleData") {
            isUsingSampleData = true
            assignCourseSnapshot(sampleCourses)
            messages = ProcessInfo.processInfo.arguments.contains("-EmptyInbox") ? [] : SampleData.messages
            hasLoadedMessages = true
            selectedGradeLevel = .senior
            coursesLastUpdated = Date()
            messagesLastUpdated = Date()
            SampleData.install()
            SampleData.installFollowupHistory(courses: courses ?? [])
            if ProcessInfo.processInfo.arguments.contains("-SampleData"),
               ProcessInfo.processInfo.arguments.contains("-FollowupReminderPreview"),
               let course = courses?.first(where: { $0.gradeYear == 12 }) {
                let reminder = LocalReminder(courseID: SchoolNotifications.notificationCourseID(for: course),
                    term: .q1, title: "Synthetic local reminder", courseName: course.courseName,
                    fireDate: Date().addingTimeInterval(1800))
                if let data = try? JSONEncoder().encode([reminder]) {
                    UserDefaults.standard.set(data, forKey: "account.sample.notifications.reminders")
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-SampleData") {
                if ProcessInfo.processInfo.arguments.contains("-PreviewTranscriptLoading") {
                    assignCourseSnapshot(nil)
                    coursesLoading = true
                    coursesLastUpdated = nil
                }
                if ProcessInfo.processInfo.arguments.contains("-PreviewInboxLoading") {
                    messages = []
                    messagesLoading = true
                    messagesLastUpdated = nil
                    hasLoadedMessages = false
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-SampleData"),
           ProcessInfo.processInfo.arguments.contains("-CorruptFollowupStoragePreview") {
            for suffix in ["gradeJournal.v1", "coursePlan.v1", "assignmentCompletion.v1", "namedWhatIfScenarios"] {
                UserDefaults.standard.set(Data("unreadable synthetic fixture".utf8), forKey: "account.sample.\(suffix)")
            }
        }
        #endif
        planning.activate(accountScope: localAccountScope)
    }

    func openDocument(_ document: SkywardDocument) async {
        guard canShowData, document.canOpen, documentOpenTask == nil, !Task.isCancelled else { return }
        let generation = accountGeneration
        let requestID = UUID()
        documentOpenID = requestID
        documentLoadingID = document.id
        documentOpenError = nil
        closeDocumentPreview()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let resource: SkywardBinaryHTTP.Resource
                #if DEBUG
                if self.isUsingSampleData {
                    if ProcessInfo.processInfo.arguments.contains("-DocumentOpenErrorPreview") {
                        throw SkywardError.invalidResponse("document is temporarily unavailable")
                    }
                    resource = SampleData.documentResource
                } else {
                    resource = try await DataService.shared.openDocument(id: document.id)
                }
                #else
                resource = try await DataService.shared.openDocument(id: document.id)
                #endif
                guard generation == self.accountGeneration, !Task.isCancelled else { return }
                let file = try await Task.detached(priority: .userInitiated) { try DocumentPreviewFiles.write(resource, title: document.title) }.value
                guard generation == self.accountGeneration, !Task.isCancelled else {
                    DocumentPreviewFiles.remove(file)
                    return
                }
                self.previewFileURL = file
                self.documentPreview = DocumentPreview(url: file, title: document.title)
            } catch {
                guard generation == self.accountGeneration, !Task.isCancelled else { return }
                self.documentOpenError = error.localizedDescription
            }
        }
        documentOpenTask = task
        await task.value
        if documentOpenID == requestID {
            documentOpenTask = nil
            documentOpenID = nil
            documentLoadingID = nil
        }
    }

    func closeDocumentPreview() {
        if let url = previewFileURL { DocumentPreviewFiles.remove(url) }
        previewFileURL = nil
        documentPreview = nil
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

    func refreshFees(force: Bool = false) async {
        guard canShowData, !Task.isCancelled else { return }
        let generation = accountGeneration
        if let task = feesRefreshTask {
            let refreshID = feesRefreshID
            let needsForcedFollowUp = force && !feesRefreshIsForced
            await task.value
            guard generation == accountGeneration, !Task.isCancelled else { return }
            if needsForcedFollowUp {
                if feesRefreshID == refreshID {
                    feesRefreshTask = nil
                    feesRefreshID = nil
                    feesRefreshIsForced = false
                }
                await refreshFees(force: true)
            }
            return
        }
        feesRefreshIsForced = force
        let refreshID = UUID()
        let task = Task { [weak self] in
            guard let self, generation == self.accountGeneration, !Task.isCancelled else { return }
            await self.performRefreshFees(force: force, generation: generation)
        }
        feesRefreshID = refreshID
        feesRefreshTask = task
        await task.value
        if feesRefreshID == refreshID {
            feesRefreshTask = nil
            feesRefreshID = nil
            feesRefreshIsForced = false
        }
    }

    private func performRefreshFees(force: Bool, generation: Int) async {
        guard generation == accountGeneration, !Task.isCancelled else { return }
        feesLoading = true
        feesError = nil
        defer { if generation == accountGeneration { feesLoading = false } }
        #if DEBUG
        if isUsingSampleData {
            if ProcessInfo.processInfo.arguments.contains("-PreviewFeesLoading") {
                try? await Task.sleep(for: .seconds(30))
                guard generation == accountGeneration, !Task.isCancelled else { return }
            }
            if ProcessInfo.processInfo.arguments.contains("-FeesErrorPreview") {
                fees = nil
                feesLastUpdated = nil
                feesError = "Skyward fees are temporarily unavailable."
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-FeesOfflinePreview") {
                fees = SampleData.fees
                feesLastUpdated = Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)
                feesError = "You're offline. Showing saved fees."
                return
            }
            fees = ProcessInfo.processInfo.arguments.contains("-EmptyFees")
                ? FeesData(fees: [], payments: []) : SampleData.fees
            if ProcessInfo.processInfo.arguments.contains("-FeesUnavailablePreview") {
                fees = FeesData(fees: [], payments: [], availability: .unavailable)
            }
            feesLastUpdated = Date()
            return
        }
        #endif
        let saved = DataService.shared.cachedFees()
        do {
            let stale = saved.map { Date().timeIntervalSince($0.updatedAt) >= Self.automaticRefreshInterval } ?? false
            let result = try await DataService.shared.loadFees(forceRefresh: force || stale)
            guard generation == accountGeneration, !Task.isCancelled else { return }
            fees = result
            feesLastUpdated = DataService.shared.cachedFees()?.updatedAt ?? Date()
        } catch {
            guard generation == accountGeneration, !Task.isCancelled else { return }
            if let saved {
                fees = saved.value
                feesLastUpdated = saved.updatedAt
            }
            feesError = error.localizedDescription
        }
    }

    func refreshStudentInfo(force: Bool = false) async {
        guard canShowData, !Task.isCancelled else { return }
        let generation = accountGeneration
        if let task = studentInfoRefreshTask {
            let refreshID = studentInfoRefreshID
            let needsForcedFollowUp = force && !studentInfoRefreshIsForced
            await task.value
            guard generation == accountGeneration, !Task.isCancelled else { return }
            if needsForcedFollowUp {
                if studentInfoRefreshID == refreshID {
                    studentInfoRefreshTask = nil
                    studentInfoRefreshID = nil
                    studentInfoRefreshIsForced = false
                }
                await refreshStudentInfo(force: true)
            }
            return
        }
        studentInfoRefreshIsForced = force
        let refreshID = UUID()
        let task = Task { [weak self] in
            guard let self, generation == self.accountGeneration, !Task.isCancelled else { return }
            await self.performRefreshStudentInfo(force: force, generation: generation)
        }
        studentInfoRefreshID = refreshID
        studentInfoRefreshTask = task
        await task.value
        if studentInfoRefreshID == refreshID {
            studentInfoRefreshTask = nil
            studentInfoRefreshID = nil
            studentInfoRefreshIsForced = false
        }
    }

    private func performRefreshStudentInfo(force: Bool, generation: Int) async {
        guard generation == accountGeneration, !Task.isCancelled else { return }
        studentInfoLoading = true
        studentInfoError = nil
        defer { if generation == accountGeneration { studentInfoLoading = false } }
        #if DEBUG
        if isUsingSampleData {
            if ProcessInfo.processInfo.arguments.contains("-PreviewStudentInfoLoading") {
                try? await Task.sleep(for: .seconds(30))
                guard generation == accountGeneration, !Task.isCancelled else { return }
            }
            if ProcessInfo.processInfo.arguments.contains("-StudentInfoErrorPreview") {
                studentInfo = nil
                studentInfoLastUpdated = nil
                studentInfoError = "Skyward student information is temporarily unavailable."
                return
            }
            var preview = SampleData.studentInfo
            if ProcessInfo.processInfo.arguments.contains("-StudentPhotoMissingPreview") {
                preview.photoData = nil
                preview.photoLoadFailed = false
            }
            if ProcessInfo.processInfo.arguments.contains("-StudentInfoEmptyFieldsPreview") {
                preview.contactFields = []
                preview.studentFields = []
                preview.enrollments = []
                preview.photoData = nil
                preview.photoLoadFailed = false
            }
            studentInfo = preview
            if ProcessInfo.processInfo.arguments.contains("-StudentInfoOfflinePreview") {
                studentInfoLastUpdated = Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)
                studentInfoError = "You're offline. Showing saved student information."
                return
            }
            studentInfoLastUpdated = Date()
            return
        }
        #endif
        let saved = DataService.shared.cachedStudentInfo()
        do {
            let stale = saved.map { Date().timeIntervalSince($0.updatedAt) >= Self.automaticRefreshInterval } ?? false
            let result = try await DataService.shared.loadStudentInfo(forceRefresh: force || stale)
            guard generation == accountGeneration, !Task.isCancelled else { return }
            studentInfo = result
            studentInfoLastUpdated = DataService.shared.cachedStudentInfo()?.updatedAt ?? Date()
        } catch {
            guard generation == accountGeneration, !Task.isCancelled else { return }
            if let saved {
                studentInfo = saved.value
                studentInfoLastUpdated = saved.updatedAt
            }
            studentInfoError = error.localizedDescription
        }
    }

    func refreshDocuments(force: Bool = false) async {
        guard canShowData, !Task.isCancelled else { return }
        let generation = accountGeneration
        if let task = documentsRefreshTask {
            let refreshID = documentsRefreshID
            let needsForcedFollowUp = force && !documentsRefreshIsForced
            await task.value
            guard generation == accountGeneration, !Task.isCancelled else { return }
            if needsForcedFollowUp {
                if documentsRefreshID == refreshID {
                    documentsRefreshTask = nil
                    documentsRefreshID = nil
                    documentsRefreshIsForced = false
                }
                await refreshDocuments(force: true)
            }
            return
        }
        documentsRefreshIsForced = force
        let refreshID = UUID()
        let task = Task { [weak self] in
            guard let self, generation == self.accountGeneration, !Task.isCancelled else { return }
            await self.performRefreshDocuments(force: force, generation: generation)
        }
        documentsRefreshID = refreshID
        documentsRefreshTask = task
        await task.value
        if documentsRefreshID == refreshID {
            documentsRefreshTask = nil
            documentsRefreshID = nil
            documentsRefreshIsForced = false
        }
    }

    private func performRefreshDocuments(force: Bool, generation: Int) async {
        guard generation == accountGeneration, !Task.isCancelled else { return }
        documentsLoading = true
        documentsError = nil
        defer { if generation == accountGeneration { documentsLoading = false } }
        #if DEBUG
        if isUsingSampleData {
            if ProcessInfo.processInfo.arguments.contains("-PreviewDocumentsLoading") {
                try? await Task.sleep(for: .seconds(30))
                guard generation == accountGeneration, !Task.isCancelled else { return }
            }
            if ProcessInfo.processInfo.arguments.contains("-DocumentsErrorPreview") {
                documents = nil
                documentsLastUpdated = nil
                documentsError = "Skyward documents are temporarily unavailable."
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-DocumentsOfflinePreview") {
                documents = SampleData.documents
                documentsLastUpdated = Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)
                documentsError = "You're offline. Showing saved documents."
                return
            }
            documents = ProcessInfo.processInfo.arguments.contains("-EmptyDocuments")
                ? DocumentsData(documents: []) : SampleData.documents
            if ProcessInfo.processInfo.arguments.contains("-DocumentsUnavailablePreview") {
                documents = DocumentsData(documents: [], availability: .unavailable)
            }
            documentsLastUpdated = Date()
            return
        }
        #endif
        let saved = DataService.shared.cachedDocuments()
        do {
            let stale = saved.map { Date().timeIntervalSince($0.updatedAt) >= Self.automaticRefreshInterval } ?? false
            let result = try await DataService.shared.loadDocuments(forceRefresh: force || stale)
            guard generation == accountGeneration, !Task.isCancelled else { return }
            documents = result
            documentsLastUpdated = DataService.shared.cachedDocuments()?.updatedAt ?? Date()
        } catch {
            guard generation == accountGeneration, !Task.isCancelled else { return }
            if let saved {
                documents = saved.value
                documentsLastUpdated = saved.updatedAt
            }
            documentsError = error.localizedDescription
        }
    }

    func refreshAttendance(force: Bool = false) async {
        guard canShowData, !Task.isCancelled else { return }
        let generation = accountGeneration
        if let task = attendanceRefreshTask {
            let refreshID = attendanceRefreshID
            let needsForcedFollowUp = force && !attendanceRefreshIsForced
            await task.value
            guard generation == accountGeneration, !Task.isCancelled else { return }
            if needsForcedFollowUp {
                if attendanceRefreshID == refreshID {
                    attendanceRefreshTask = nil
                    attendanceRefreshID = nil
                    attendanceRefreshIsForced = false
                }
                await refreshAttendance(force: true)
            }
            return
        }
        attendanceLastAttempt = Date()
        attendanceRefreshIsForced = force
        let refreshID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefreshAttendance(force: force)
        }
        attendanceRefreshID = refreshID
        attendanceRefreshTask = task
        await task.value
        if attendanceRefreshID == refreshID {
            attendanceRefreshTask = nil
            attendanceRefreshID = nil
            attendanceRefreshIsForced = false
        }
    }

    private func performRefreshAttendance(force: Bool) async {
        let generation = accountGeneration
        attendanceLoading = true
        attendanceError = nil
        defer { if generation == accountGeneration { attendanceLoading = false } }
        #if DEBUG
        if isUsingSampleData {
            if ProcessInfo.processInfo.arguments.contains("-PreviewAttendanceLoading") {
                try? await Task.sleep(for: .seconds(30))
                guard generation == accountGeneration, !Task.isCancelled else { return }
            }
            if ProcessInfo.processInfo.arguments.contains("-AttendanceErrorPreview") {
                attendanceError = "Skyward attendance is temporarily unavailable."
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-AttendanceOfflinePreview") {
                attendance = SampleData.attendance
                attendanceLastUpdated = Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)
                attendanceError = "You're offline. Showing saved attendance."
                return
            }
            attendance = ProcessInfo.processInfo.arguments.contains("-EmptyAttendance")
                ? AttendanceData(records: []) : SampleData.attendance
            if ProcessInfo.processInfo.arguments.contains("-AttendanceUnavailablePreview") {
                attendance = AttendanceData(records: [], availability: .unavailable)
            }
            attendanceLastUpdated = Date()
            return
        }
        #endif
        let saved = DataService.shared.cachedAttendance()
        do {
            let stale = saved.map { Date().timeIntervalSince($0.updatedAt) >= Self.automaticRefreshInterval } ?? false
            let result = try await DataService.shared.loadAttendance(forceRefresh: force || stale)
            guard generation == accountGeneration, !Task.isCancelled else { return }
            attendance = result
            attendanceLastUpdated = DataService.shared.cachedAttendance()?.updatedAt ?? Date()
        } catch {
            guard generation == accountGeneration, !Task.isCancelled else { return }
            if let saved {
                attendance = saved.value
                attendanceLastUpdated = saved.updatedAt
            }
            attendanceError = error.localizedDescription
        }
    }

    /// The Attendance view owns this loop: hidden tabs don't add network work.
    func runAttendanceRefreshLoop() async {
        while !Task.isCancelled, canShowData {
            if AutomaticRefreshPolicy.isDue(lastUpdated: attendanceLastUpdated, lastAttempt: attendanceLastAttempt,
                                            now: Date(), interval: automaticRefreshInterval) {
                await refreshAttendance(force: attendance != nil)
            }
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }

    /// Idempotent during one foreground viewing session. Starting a session does
    /// not mark any fetched or cached courses as seen.
    func beginCourseGradeViewingSession() {
        guard canShowData, !isAuthenticating else { return }
        let scope = isUsingSampleData ? "sample" : CredentialStore.currentAccountIdentifier
        guard let scope else { return }
        guard courseGradeTracker == nil || courseGradeTrackerScope != scope else { return }
        courseGradeTracker = GradeChangeTracker(scope: scope)
        courseGradeTrackerScope = scope
        courseGradeChanges = [:]
        observedCourseGradeTerm = nil
    }

    /// End on foreground-session exit, not when pushing a class or changing tabs.
    func endCourseGradeViewingSession() {
        courseGradeTracker = nil
        courseGradeTrackerScope = nil
        courseGradeChanges = [:]
        observedCourseGradeTerm = nil
    }

    /// The Courses root calls this only while actually visible and active. A
    /// refresh completion alone must never call it: unseen values are not seen.
    func observeVisibleCourseGrades(displayedCourseIDs: Set<String>) {
        guard canShowData, !isAuthenticating, courses != nil else { return }
        beginCourseGradeViewingSession()
        guard var tracker = courseGradeTracker else { return }
        var scores: [String: Double?] = [:]
        let displayed = visibleCourses.filter { displayedCourseIDs.contains($0.id) }
        for course in displayed {
            scores.updateValue(GradeChangeTracker.officialScore(for: course, term: selectedTerm), forKey: course.id)
        }
        let deltas = tracker.observe(scores, term: selectedTerm)
        if observedCourseGradeTerm != selectedTerm { courseGradeChanges = [:] }
        for id in scores.keys { courseGradeChanges[id] = deltas[id] }
        observedCourseGradeTerm = selectedTerm
        courseGradeTracker = tracker
        if let scope = localAccountScope, let sourceDate = coursesLastUpdated {
            for course in displayed {
                guard let score = GradeChangeTracker.officialScore(for: course, term: selectedTerm) else { continue }
                notifications.markGradeViewed(course: course, term: selectedTerm, score: score,
                    sourceDate: sourceDate, accountScope: scope)
            }
        }
    }

    func courseGradeDelta(for courseID: String) -> Double? {
        guard observedCourseGradeTerm == selectedTerm else { return nil }
        return courseGradeChanges[courseID]
    }

    func saveCredentials(username: String, password: String) async -> Bool {
        let saveID = credentialSaveOwnership.begin()
        isAuthenticating = true
        defer { if credentialSaveOwnership.owns(saveID) { isAuthenticating = false } }
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
            planning.activate(accountScope: newAccount)
            await notifications.activateAccount(scope: newAccount)
            authError = nil
            isAuthenticating = false
            credentialSaveOwnership.finish(saveID)
            Task {
                await refreshCourses(force: true)
                await refreshMessages(force: true)
            }
            return true
        } catch {
            if credentialSaveOwnership.owns(saveID) {
                isAuthenticating = false
                credentialSaveOwnership.finish(saveID)
                authError = error.localizedDescription
                hasCredentials = CredentialStore.hasCredentials
                planning.activate(accountScope: localAccountScope)
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

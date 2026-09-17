import Foundation
import WidgetKit

/// Builds the shared snapshot the widgets render from. Grade info comes from
/// the same 5-minute DataService cache the class detail screen uses, so a
/// refresh that follows a browse session is mostly free.
enum WidgetSnapshotBuilder {
    private static let assignmentWidgetKinds: Set<String> = [
        "SchoolPulseWidget",
        "RecentGradesWidget",
        "MissingAssignmentsWidget",
    ]

    private struct AssignmentFetch {
        var recent: [WidgetSnapshot.AssignmentItem] = []
        var missing: [WidgetSnapshot.AssignmentItem] = []
        var absent: [WidgetSnapshot.AssignmentItem] = []
        var completedCourseCount = 0
        var expectedCourseCount = 0
        var failedCourseNames: Set<String> = []
        var sourceDates: [Date] = []
        var hasUnknownSourceDate = false
        var didTimeOut = false

        var isComplete: Bool { completedCourseCount == expectedCourseCount }
        var updatedAt: Date? { hasUnknownSourceDate ? nil : sourceDates.min() }
    }

    private struct CourseAssignmentFetch {
        var courseName: String
        var recent: [WidgetSnapshot.AssignmentItem] = []
        var missing: [WidgetSnapshot.AssignmentItem] = []
        var absent: [WidgetSnapshot.AssignmentItem] = []
        var updatedAt: Date?
        var succeeded = false
    }

    private struct AssignmentSections {
        var recent: [WidgetSnapshot.AssignmentItem]
        var missing: [WidgetSnapshot.AssignmentItem]
        var absent: [WidgetSnapshot.AssignmentItem]
        var recentTotal: Int?
        var missingTotal: Int?
        var absentTotal: Int?
        var status: WidgetSnapshot.SectionStatus
    }

    private actor AssignmentFetchGate {
        private var result: AssignmentFetch?
        private var continuation: CheckedContinuation<AssignmentFetch, Never>?

        func wait() async -> AssignmentFetch {
            if let result { return result }
            return await withCheckedContinuation { continuation = $0 }
        }

        func resolve(_ result: AssignmentFetch) {
            guard self.result == nil else { return }
            self.result = result
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    static func refresh(
        courses: [UnifiedCourseData]?,
        coursesUpdatedAt: Date?,
        coursesAreComplete: Bool,
        messages: [SkywardMessage]?,
        messagesUpdatedAt: Date?,
        messagesAreComplete: Bool
    ) async {
        let accountScope = CredentialStore.currentAccountIdentifier
        let previous = WidgetSnapshotStore.load()
        guard courses != nil || previous != nil else { return }

        let now = Date()
        let term = AcademicCalendar.currentTerm()
        var weightedGPA = previous?.weightedGPA
        var unweightedGPA = previous?.unweightedGPA
        var courseGrades = previous?.courses ?? []
        var gpaHistory = previous?.gpaHistory ?? []
        var baseStatus = previous?.resolvedBaseStatus
            ?? WidgetSnapshot.SectionStatus(updatedAt: nil, isComplete: false)
        var visible: [UnifiedCourseData] = []

        if let courses {
            // Current grade level, gradebook-capable, filtered to this semester
            // (same filter as AppStore.visibleCourses).
            let current: [UnifiedCourseData]
            if let maxYear = courses.compactMap(\.gradeYear).max() {
                current = courses.filter { $0.gradeYear == maxYear }
            } else {
                current = courses.filter { $0.gradeYear == nil }
            }
            let targets: Set<Semester> = term.isFall ? [.fall, .both] : [.spring, .both]
            visible = current
                .filter(\.hasGradebookParams)
                .filter { $0.semester == .unknown || targets.contains($0.semester) }

            let gpa = currentGPA(courses: current, term: term)
            weightedGPA = gpa?.weighted
            unweightedGPA = gpa?.unweighted
            let gpaTable = GPACalculator.termGPAs(courses: current)
            gpaHistory = GPACalculator.graphTerms.compactMap { key in
                gpaTable[key].flatMap { value in
                    value.weighted.isFinite
                        ? WidgetSnapshot.GPAHistoryPoint(term: key, weighted: value.weighted)
                        : nil
                }
            }
            courseGrades = visible.map { course in
                WidgetSnapshot.CourseGrade(
                    name: displayName(for: course),
                    score: termScore(course, term: term)
                )
            }
            baseStatus = WidgetSnapshot.SectionStatus(
                updatedAt: coursesUpdatedAt,
                isComplete: coursesAreComplete
            )
        } else if !coursesAreComplete {
            baseStatus.isComplete = false
        }

        let needsAssignments = await installedWidgetsNeedAssignments()
        // Never carry a different term's assignments under the new term label.
        let previousAssignments = previous?.termShortName == term.shortName ? previous : nil
        let assignmentsNeedRefresh = WidgetAssignmentRefreshPolicy.isDue(
            term: term,
            previousTerm: previous?.termShortName,
            coursesUpdatedAt: coursesUpdatedAt,
            previousCoursesUpdatedAt: previous?.resolvedBaseStatus.updatedAt,
            assignmentsUpdatedAt: previousAssignments?.resolvedAssignmentStatus.updatedAt,
            assignmentsAreComplete: previousAssignments?.resolvedAssignmentStatus.isComplete ?? false,
            now: now
        )
        let assignmentSections: AssignmentSections
        // Semester buckets contain exam work, not the quarter's assignments.
        // Use Calendar's current-quarter and live-identity rules.
        let assignmentTerm = SchoolCalendar.quarter(for: term)
        let assignmentCourses = SchoolCalendar.eligibleCourses(courses ?? [], term: assignmentTerm)
        if needsAssignments, assignmentsNeedRefresh, coursesAreComplete,
           !assignmentCourses.isEmpty {
            let result = await fetchAssignmentsWithTimeout(courses: assignmentCourses, term: assignmentTerm, accountScope: accountScope)
            guard !Task.isCancelled else { return }
            assignmentSections = mergedAssignmentSections(
                result,
                previous: previousAssignments
            )
        } else if needsAssignments, coursesAreComplete, courses?.isEmpty == true {
            assignmentSections = AssignmentSections(
                recent: [], missing: [], absent: [],
                recentTotal: 0, missingTotal: 0, absentTotal: 0,
                status: WidgetSnapshot.SectionStatus(updatedAt: coursesUpdatedAt, isComplete: true)
            )
        } else {
            let canReusePreviousCompleteness = !needsAssignments
                || (coursesAreComplete && !assignmentsNeedRefresh)
            let preservedCompleteness: Bool? = canReusePreviousCompleteness ? nil : false
            assignmentSections = preservedAssignmentSections(
                previous: previousAssignments,
                isComplete: preservedCompleteness
            )
        }

        let messageItems: [WidgetSnapshot.MessageItem]
        var messageStatus = previous?.resolvedMessageStatus
            ?? WidgetSnapshot.SectionStatus(updatedAt: nil, isComplete: false)
        if let messages {
            messageItems = messages.prefix(6).map {
                WidgetSnapshot.MessageItem(
                    from: $0.from,
                    subject: $0.subject,
                    date: $0.date,
                    isAdministrator: $0.isAdministrator
                )
            }
            messageStatus = WidgetSnapshot.SectionStatus(
                updatedAt: messagesUpdatedAt,
                isComplete: messagesAreComplete
            )
        } else {
            messageItems = previous?.messages ?? []
            if !messagesAreComplete { messageStatus.isComplete = false }
        }

        let snapshot = WidgetSnapshot(
            generatedAt: now,
            termShortName: term.shortName,
            weightedGPA: weightedGPA,
            unweightedGPA: unweightedGPA,
            courses: courseGrades,
            recentGrades: Array(assignmentSections.recent.prefix(8)),
            missingAssignments: Array(assignmentSections.missing.prefix(10)),
            absentAssignments: Array(assignmentSections.absent.prefix(10)),
            gpaHistory: gpaHistory,
            messages: messageItems,
            recentGradesTotal: assignmentSections.recentTotal,
            missingAssignmentsTotal: assignmentSections.missingTotal,
            absentAssignmentsTotal: assignmentSections.absentTotal,
            isComplete: assignmentSections.status.isComplete,
            baseStatus: baseStatus,
            assignmentStatus: assignmentSections.status,
            messageStatus: messageStatus
        )
        guard !Task.isCancelled else { return }
        guard accountScope == CredentialStore.currentAccountIdentifier else { return }
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func installedWidgetsNeedAssignments() async -> Bool {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case .success(let configurations):
                    continuation.resume(
                        returning: configurations.contains {
                            assignmentWidgetKinds.contains($0.kind)
                        }
                    )
                case .failure:
                    // A configuration lookup failure must not silently starve an
                    // installed assignment widget. The successful "no matching widget"
                    // result is the path that intentionally skips detail requests.
                    continuation.resume(returning: true)
                }
            }
        }
    }

    private static func preservedAssignmentSections(
        previous: WidgetSnapshot?,
        isComplete: Bool?
    ) -> AssignmentSections {
        var status = previous?.resolvedAssignmentStatus
            ?? WidgetSnapshot.SectionStatus(updatedAt: nil, isComplete: false)
        if let isComplete { status.isComplete = isComplete }
        return AssignmentSections(
            recent: previous?.recentGrades ?? [],
            missing: previous?.missingAssignments ?? [],
            absent: previous?.absentAssignments ?? [],
            recentTotal: status.isComplete ? previous?.recentGradesTotal : nil,
            missingTotal: status.isComplete ? previous?.missingAssignmentsTotal : nil,
            absentTotal: status.isComplete ? previous?.absentAssignmentsTotal : nil,
            status: status
        )
    }

    private static func mergedAssignmentSections(
        _ fetch: AssignmentFetch,
        previous: WidgetSnapshot?
    ) -> AssignmentSections {
        if fetch.isComplete {
            let recent = sortedUnique(fetch.recent)
            let missing = sortedUnique(fetch.missing)
            let absent = sortedUnique(fetch.absent)
            return AssignmentSections(
                recent: recent,
                missing: missing,
                absent: absent,
                recentTotal: recent.count,
                missingTotal: missing.count,
                absentTotal: absent.count,
                status: WidgetSnapshot.SectionStatus(updatedAt: fetch.updatedAt, isComplete: true)
            )
        }

        guard !fetch.didTimeOut, fetch.completedCourseCount > 0 else {
            return preservedAssignmentSections(previous: previous, isComplete: false)
        }

        let failedNames = fetch.failedCourseNames
        let previousRecent = previous?.recentGrades.filter { failedNames.contains($0.className) } ?? []
        let previousMissing = previous?.missingAssignments.filter { failedNames.contains($0.className) } ?? []
        let previousAbsent = previous?.absentAssignments?.filter { failedNames.contains($0.className) } ?? []
        let preservesPrevious = !previousRecent.isEmpty || !previousMissing.isEmpty || !previousAbsent.isEmpty
        let updatedAt: Date?
        if preservesPrevious {
            // A mixed snapshot is only as fresh as its oldest retained source.
            updatedAt = fetch.updatedAt.flatMap { fetched in
                previous?.resolvedAssignmentStatus.updatedAt.map { min(fetched, $0) }
            }
        } else {
            updatedAt = fetch.updatedAt
        }
        return AssignmentSections(
            recent: sortedUnique(fetch.recent + previousRecent),
            missing: sortedUnique(fetch.missing + previousMissing),
            absent: sortedUnique(fetch.absent + previousAbsent),
            recentTotal: nil,
            missingTotal: nil,
            absentTotal: nil,
            status: WidgetSnapshot.SectionStatus(updatedAt: updatedAt, isComplete: false)
        )
    }

    private static func sortedUnique(
        _ items: [WidgetSnapshot.AssignmentItem]
    ) -> [WidgetSnapshot.AssignmentItem] {
        var seen: Set<WidgetSnapshot.AssignmentItem> = []
        return items
            .sorted { parseDate($0.date) > parseDate($1.date) }
            .filter { seen.insert($0).inserted }
    }

    private static func fetchAssignmentsWithTimeout(
        courses: [UnifiedCourseData],
        term: TermLabel,
        accountScope: String?
    ) async -> AssignmentFetch {
        let gate = AssignmentFetchGate()
        let fetchTask = Task {
            let result = await fetchAssignments(courses: courses, term: term, accountScope: accountScope)
            await gate.resolve(result)
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: .seconds(18))
            } catch {
                return
            }
            await gate.resolve(AssignmentFetch(
                expectedCourseCount: courses.count,
                didTimeOut: true
            ))
        }

        let result = await withTaskCancellationHandler {
            await gate.wait()
        } onCancel: {
            fetchTask.cancel()
            timeoutTask.cancel()
        }
        fetchTask.cancel()
        timeoutTask.cancel()
        return result
    }

    private static func fetchAssignments(
        courses: [UnifiedCourseData],
        term: TermLabel,
        accountScope: String?
    ) async -> AssignmentFetch {
        await withTaskGroup(of: CourseAssignmentFetch.self) { group in
            var iterator = courses.makeIterator()
            for _ in 0..<min(courses.count, 4) {
                if let course = iterator.next() {
                    group.addTask { await fetchAssignments(for: course, term: term, accountScope: accountScope) }
                }
            }

            var combined = AssignmentFetch(expectedCourseCount: courses.count)
            while let result = await group.next() {
                if result.succeeded {
                    combined.completedCourseCount += 1
                    if let date = result.updatedAt {
                        combined.sourceDates.append(date)
                    } else {
                        combined.hasUnknownSourceDate = true
                    }
                } else {
                    combined.failedCourseNames.insert(result.courseName)
                }
                combined.recent.append(contentsOf: result.recent)
                combined.missing.append(contentsOf: result.missing)
                combined.absent.append(contentsOf: result.absent)

                if !Task.isCancelled, let course = iterator.next() {
                    group.addTask { await fetchAssignments(for: course, term: term, accountScope: accountScope) }
                }
            }
            return combined
        }
    }

    private static func fetchAssignments(
        for course: UnifiedCourseData,
        term: TermLabel,
        accountScope: String?
    ) async -> CourseAssignmentFetch {
        let className = displayName(for: course)
        guard !Task.isCancelled else { return CourseAssignmentFetch(courseName: className) }
        let params = SchoolCalendar.params(course: course, term: term)
        guard let info = try? await DataService.shared.gradeInfo(params: params),
              !Task.isCancelled else {
            return CourseAssignmentFetch(courseName: className)
        }

        var result = CourseAssignmentFetch(
            courseName: className,
            updatedAt: DataService.shared.cachedGradeInfo(params: params)?.updatedAt,
            succeeded: true
        )
        // Build identities before excluding any status so occurrence suffixes
        // agree exactly with Calendar and the official class-detail gradebook.
        let sourceAssignments = CalendarAssignment.sourceAssignments(course: course, term: term, gradeInfo: info)
        var sourceIndex = 0
        for category in info.gradebook {
            for assignment in category.assignments {
                let sourceID = sourceAssignments[sourceIndex].routeID
                sourceIndex += 1
                if assignment.meta.contains(where: { $0.type == "noCount" }) { continue }
                let item = WidgetSnapshot.AssignmentItem(
                    className: className,
                    name: assignment.name,
                    gradeText: gradeText(assignment),
                    date: assignment.date,
                    courseID: AssignmentLink.assignmentToken(for: course.id),
                    termRawValue: term.rawValue,
                    assignmentID: sourceID,
                    accountScope: accountScope
                )
                if assignment.meta.contains(where: { $0.type == "missing" }) {
                    result.missing.append(item)
                } else if assignment.meta.contains(where: { $0.type == "absent" }) {
                    result.absent.append(item)
                } else if assignment.pointsEarned != nil || assignment.grade != nil {
                    result.recent.append(item)
                }
            }
        }
        return result
    }

    /// GPA for the displayed term. Older terms remain available in the trend widget,
    /// but must not be presented under the current term's label.
    private static func currentGPA(courses: [UnifiedCourseData], term: TermLabel) -> GPAData? {
        let table = GPACalculator.termGPAs(courses: courses)
        return table[term.historicalKey.uppercased()]
    }

    private static func displayName(for course: UnifiedCourseData) -> String {
        ClassNameFormatter.format(course.courseName.replacingOccurrences(of: " ", with: "_"))
    }

    /// Same lookup as ClassCardView: live bucket score, then history.
    private static func termScore(_ course: UnifiedCourseData, term: TermLabel) -> Double? {
        let bucket: String
        switch term {
        case .q1: bucket = "Q1"; case .q2: bucket = "Q2"; case .sm1: bucket = "S1"
        case .q3: bucket = "Q3"; case .q4: bucket = "Q4"; case .sm2: bucket = "S2"
        }
        return course.currentScores.first { $0.bucket == bucket }?.score
            ?? AcademicScoreValue.finiteDouble(course.historicalGrades[term.historicalKey])
    }

    private static func gradeText(_ a: GradeInfoAssignment) -> String {
        if let grade = a.grade { return "\(grade)" }
        if let earned = a.pointsEarned, let total = a.pointsTotal {
            return "\(trim(earned))/\(trim(total))"
        }
        return ""
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private static func parseDate(_ string: String) -> Date {
        let parts = string.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantPast }
        var components = DateComponents()
        components.month = parts[0]
        components.day = parts[1]
        components.year = parts[2] < 100 ? 2000 + parts[2] : parts[2]
        return Calendar.current.date(from: components) ?? .distantPast
    }
}

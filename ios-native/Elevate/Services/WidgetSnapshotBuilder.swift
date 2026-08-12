import Foundation
import WidgetKit

/// Builds the shared snapshot the widgets render from. Grade info comes from
/// the same 5-minute DataService cache the class detail screen uses, so a
/// refresh that follows a browse session is mostly free.
enum WidgetSnapshotBuilder {
    private struct AssignmentFetch {
        var recent: [WidgetSnapshot.AssignmentItem] = []
        var missing: [WidgetSnapshot.AssignmentItem] = []
        var absent: [WidgetSnapshot.AssignmentItem] = []
        var completedCourseCount = 0
        var expectedCourseCount = 0

        var isComplete: Bool { completedCourseCount == expectedCourseCount }
    }

    private struct CourseAssignmentFetch {
        var recent: [WidgetSnapshot.AssignmentItem] = []
        var missing: [WidgetSnapshot.AssignmentItem] = []
        var absent: [WidgetSnapshot.AssignmentItem] = []
        var succeeded = false
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

    static func refresh(courses: [UnifiedCourseData], messages: [SkywardMessage]) async {
        let term = AcademicCalendar.currentTerm()

        // Current grade level, gradebook-capable, filtered to this semester
        // (same filter as AppStore.visibleCourses).
        let current: [UnifiedCourseData]
        if let maxYear = courses.compactMap(\.gradeYear).max() {
            current = courses.filter { $0.gradeYear == maxYear }
        } else {
            current = courses.filter { $0.gradeYear == nil }
        }
        guard !current.isEmpty else {
            WidgetSnapshotStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let targets: Set<Semester> = term.isFall ? [.fall, .both] : [.spring, .both]
        let visible = current
            .filter(\.hasGradebookParams)
            .filter { $0.semester == .unknown || targets.contains($0.semester) }

        let gpa = currentGPA(courses: current, term: term)
        let gpaTable = GPACalculator.termGPAs(courses: current)
        let gpaHistory = GPACalculator.graphTerms.compactMap { key in
            gpaTable[key].flatMap { value in
                value.weighted.isFinite
                    ? WidgetSnapshot.GPAHistoryPoint(term: key, weighted: value.weighted)
                    : nil
            }
        }

        let courseGrades = visible.map { course in
            WidgetSnapshot.CourseGrade(
                name: ClassNameFormatter.format(course.courseName.replacingOccurrences(of: " ", with: "_")),
                score: termScore(course, term: term)
            )
        }

        let assignmentFetch: AssignmentFetch
        if visible.isEmpty {
            // No gradebook-capable course was inspected, so zero is not authoritative.
            assignmentFetch = AssignmentFetch(expectedCourseCount: 1)
        } else {
            assignmentFetch = await fetchAssignmentsWithTimeout(courses: visible, term: term)
        }
        if !assignmentFetch.isComplete, WidgetSnapshotStore.load() != nil {
            // Preserve the last known-complete snapshot instead of publishing false zeroes.
            return
        }

        var recent = assignmentFetch.recent
        var missing = assignmentFetch.missing
        var absent = assignmentFetch.absent
        recent.sort { parseDate($0.date) > parseDate($1.date) }
        missing.sort { parseDate($0.date) > parseDate($1.date) }
        absent.sort { parseDate($0.date) > parseDate($1.date) }

        let snapshot = WidgetSnapshot(
            generatedAt: Date(),
            termShortName: term.shortName,
            weightedGPA: gpa?.weighted,
            unweightedGPA: gpa?.unweighted,
            courses: courseGrades,
            recentGrades: Array(recent.prefix(8)),
            missingAssignments: Array(missing.prefix(10)),
            absentAssignments: Array(absent.prefix(10)),
            gpaHistory: gpaHistory,
            messages: messages.prefix(6).map {
                WidgetSnapshot.MessageItem(from: $0.from, subject: $0.subject,
                                           date: $0.date, isAdministrator: $0.isAdministrator)
            },
            recentGradesTotal: assignmentFetch.isComplete ? recent.count : nil,
            missingAssignmentsTotal: assignmentFetch.isComplete ? missing.count : nil,
            absentAssignmentsTotal: assignmentFetch.isComplete ? absent.count : nil,
            isComplete: assignmentFetch.isComplete
        )
        guard !Task.isCancelled else { return }
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func fetchAssignmentsWithTimeout(
        courses: [UnifiedCourseData],
        term: TermLabel
    ) async -> AssignmentFetch {
        let gate = AssignmentFetchGate()
        let fetchTask = Task {
            let result = await fetchAssignments(courses: courses, term: term)
            await gate.resolve(result)
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: .seconds(18))
            } catch {
                return
            }
            await gate.resolve(AssignmentFetch(expectedCourseCount: courses.count))
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
        term: TermLabel
    ) async -> AssignmentFetch {
        await withTaskGroup(of: CourseAssignmentFetch.self) { group in
            var iterator = courses.makeIterator()
            for _ in 0..<min(courses.count, 4) {
                if let course = iterator.next() {
                    group.addTask { await fetchAssignments(for: course, term: term) }
                }
            }

            var combined = AssignmentFetch(expectedCourseCount: courses.count)
            while let result = await group.next() {
                if result.succeeded { combined.completedCourseCount += 1 }
                combined.recent.append(contentsOf: result.recent)
                combined.missing.append(contentsOf: result.missing)
                combined.absent.append(contentsOf: result.absent)

                if let course = iterator.next() {
                    group.addTask { await fetchAssignments(for: course, term: term) }
                }
            }
            return combined
        }
    }

    private static func fetchAssignments(
        for course: UnifiedCourseData,
        term: TermLabel
    ) async -> CourseAssignmentFetch {
        guard !Task.isCancelled else { return CourseAssignmentFetch() }
        let params = GradeInfoParams(
            stuId: course.stuId,
            corNumId: course.corNumId,
            gbId: course.gbId,
            section: course.section,
            bucket: term.bucket
        )
        guard let info = try? await DataService.shared.gradeInfo(params: params),
              !Task.isCancelled else {
            return CourseAssignmentFetch()
        }

        let className = ClassNameFormatter.format(
            course.courseName.replacingOccurrences(of: " ", with: "_")
        )
        var result = CourseAssignmentFetch(succeeded: true)
        for category in info.gradebook {
            for assignment in category.assignments {
                if assignment.meta.contains(where: { $0.type == "noCount" }) { continue }
                let item = WidgetSnapshot.AssignmentItem(
                    className: className,
                    name: assignment.name,
                    gradeText: gradeText(assignment),
                    date: assignment.date
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

    /// Same lookup as ClassCardView: live bucket score, then history.
    private static func termScore(_ course: UnifiedCourseData, term: TermLabel) -> Double? {
        let bucket: String
        switch term {
        case .q1: bucket = "Q1"; case .q2: bucket = "Q2"; case .sm1: bucket = "S1"
        case .q3: bucket = "Q3"; case .q4: bucket = "Q4"; case .sm2: bucket = "S2"
        }
        return course.currentScores.first { $0.bucket == bucket }?.score
            ?? course.historicalGrades[term.historicalKey].flatMap { Double($0) }
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

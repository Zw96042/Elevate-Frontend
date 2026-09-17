import Foundation

/// Loads one selected quarter with at most three course requests in progress.
enum SchoolCalendarService {
    static func load(courses: [UnifiedCourseData], term: TermLabel, force: Bool,
                     previous: SchoolCalendarData?) async throws -> SchoolCalendarData {
        let eligible = SchoolCalendar.eligibleCourses(courses, term: term)
        var snapshots: [(Int, SchoolCalendarCourseSnapshot)] = []
        try await withThrowingTaskGroup(of: (Int, SchoolCalendarCourseSnapshot).self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                let course = eligible[index]
                group.addTask {
                    try Task.checkCancellation()
                    let params = SchoolCalendar.params(course: course, term: term)
                    let cached = DataService.shared.cachedGradeInfo(params: params)
                    do {
                        let result = try await DataService.shared.gradeInfo(params: params, forceRefresh: force)
                        try Task.checkCancellation()
                        let timestamp = DataService.shared.cachedGradeInfo(params: params)?.updatedAt
                        return (index, SchoolCalendarCourseSnapshot(course: course,
                            assignments: CalendarAssignment.sourceAssignments(course: course, term: term, gradeInfo: result),
                            updatedAt: timestamp, isResolved: true, didFail: false))
                    } catch {
                        try Task.checkCancellation()
                        if let cached {
                            return (index, SchoolCalendarCourseSnapshot(course: course,
                                assignments: CalendarAssignment.sourceAssignments(course: course, term: term, gradeInfo: cached.value),
                                updatedAt: cached.updatedAt, isResolved: true, didFail: true))
                        }
                        let old = previous?.term == term ? previous : nil
                        return (index, SchoolCalendarCourseSnapshot(course: course,
                            assignments: old?.assignments.filter { $0.course.id == course.id }.map {
                                var assignment = $0
                                assignment.course = course
                                return assignment
                            } ?? [],
                            updatedAt: old?.courseUpdatedAt[course.id],
                            isResolved: old?.resolvedCourseIDs.contains(course.id) == true, didFail: true))
                    }
                }
            }
            while next < min(3, eligible.count) { enqueue(next); next += 1 }
            while let result = try await group.next() {
                try Task.checkCancellation()
                snapshots.append(result)
                if next < eligible.count { enqueue(next); next += 1 }
            }
        }
        return SchoolCalendarData(term: term, snapshots: snapshots.sorted { $0.0 < $1.0 }.map(\.1))
    }
}

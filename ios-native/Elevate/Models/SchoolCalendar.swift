import Foundation
import CryptoKit

struct CalendarAssignment: Hashable, Identifiable {
    var id: String
    var routeID: String { AssignmentLink.assignmentToken(for: id) }
    var course: UnifiedCourseData
    var term: TermLabel
    /// A school day, never a timestamp. Nil retains an unreadable source date.
    var date: String?
    var sourceDate: String
    var title: String
    var category: String
    var meta: [AssignmentMeta]
    /// Skyward posted a score, grade or points for it. A graded assignment
    /// counts as done unless Skyward also marks it missing.
    var isGraded = false

    var isMarkedMissing: Bool { meta.contains { $0.type.lowercased() == "missing" } }
    /// Done because Skyward graded it; a personal mark is separate.
    var isDoneByGrade: Bool { isGraded && !isMarkedMissing }

    static func sourceAssignments(course: UnifiedCourseData, term: TermLabel,
                                  gradeInfo: GradeInfoResult) -> [CalendarAssignment] {
        var occurrences: [String: Int] = [:]
        return gradeInfo.gradebook.flatMap { category in
            category.assignments.map { assignment in
                // Length prefixes prevent source delimiters from aliasing an ID.
                let key = [course.id, term.rawValue, category.category, assignment.name, assignment.date]
                    .map { "\($0.utf8.count):\($0)" }.joined()
                let occurrence = occurrences[key, default: 0]
                occurrences[key] = occurrence + 1
                return CalendarAssignment(
                    id: "\(key):\(occurrence)", course: course, term: term,
                    date: SchoolCalendarDate.normalize(assignment.date), sourceDate: assignment.date,
                    title: assignment.name, category: category.category, meta: assignment.meta,
                    isGraded: assignment.score != nil || assignment.grade != nil || assignment.pointsEarned != nil
                )
            }
        }
    }
}

struct SchoolCalendarData: Equatable {
    var term: TermLabel
    var assignments: [CalendarAssignment]
    var updatedAt: Date?
    var failedCourseNames: [String]
    var eligibleCourseCount: Int
    /// Includes verified empty gradebooks, which have no assignment IDs.
    var resolvedCourseIDs: Set<String> = []
    var courseUpdatedAt: [String: Date] = [:]

    var undatedCount: Int { assignments.filter { $0.date == nil }.count }
    var resolvedCourseCount: Int { resolvedCourseIDs.count }

    init(term: TermLabel, assignments: [CalendarAssignment], updatedAt: Date?,
         failedCourseNames: [String] = [], eligibleCourseCount: Int = 0,
         resolvedCourseIDs: Set<String> = [], courseUpdatedAt: [String: Date] = [:]) {
        self.term = term
        self.assignments = assignments
        self.updatedAt = updatedAt
        self.failedCourseNames = failedCourseNames
        self.eligibleCourseCount = eligibleCourseCount
        self.resolvedCourseIDs = resolvedCourseIDs
        self.courseUpdatedAt = courseUpdatedAt
    }

    init(term: TermLabel, snapshots: [SchoolCalendarCourseSnapshot]) {
        self.init(term: term, assignments: snapshots.flatMap(\.assignments),
                  updatedAt: snapshots.contains { $0.isResolved && $0.updatedAt == nil }
                    ? nil : snapshots.filter(\.isResolved).compactMap(\.updatedAt).min(),
                  failedCourseNames: snapshots.filter(\.didFail).map { $0.course.courseName },
                  eligibleCourseCount: snapshots.count,
                  resolvedCourseIDs: Set(snapshots.filter(\.isResolved).map { $0.course.id }),
                  courseUpdatedAt: Dictionary(snapshots.compactMap { snapshot in
                      snapshot.updatedAt.map { (snapshot.course.id, $0) }
                  }, uniquingKeysWith: min))
    }
}

/// One quarter's saved assignments and the state of its latest load. A
/// quarter with no entry has never been asked for; nothing is claimed
/// about its days.
struct CalendarQuarterState: Equatable {
    var data: SchoolCalendarData?
    var isLoading = false
    var error: String?
    /// The oldest resolved course timestamp in `data`, never fresher.
    var lastUpdated: Date?
    var lastAttempt: Date?


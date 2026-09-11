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

    /// Data in which no class resolved shows nothing, so it is a failure
    /// rather than an empty quarter.
    var loadedData: SchoolCalendarData? {
        guard let data, data.resolvedCourseCount > 0 || data.failedCourseNames.isEmpty else { return nil }
        return data
    }

    /// Failed with nothing usable saved, once the attempt has ended.
    var failure: String? {
        guard loadedData == nil, !isLoading else { return nil }
        return error
    }
}

struct SchoolCalendarCourseSnapshot {
    var course: UnifiedCourseData
    var assignments: [CalendarAssignment]
    var updatedAt: Date?
    var isResolved: Bool
    var didFail: Bool
}

enum SchoolCalendar {
    static let quarters: [TermLabel] = [.q1, .q2, .q3, .q4]

    static func quarter(for term: TermLabel) -> TermLabel {
        switch term {
        case .sm1: return .q2
        case .sm2: return .q4
        default: return term
        }
    }

    /// The verified district schedule covers only 2026–27. Nil never claims
    /// another year's quarter dates or treats a past quarter as upcoming.
    static func upcomingQuarterStart(term: TermLabel, now: Date = Date()) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let day = calendar.startOfDay(for: now)
        guard let scheduleStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)),
              let scheduleEnd = calendar.date(from: DateComponents(year: 2027, month: 8, day: 1)),
              day >= scheduleStart, day < scheduleEnd else { return nil }
        let components: DateComponents
        switch term {
        case .q1: components = DateComponents(year: 2026, month: 8, day: 13)
        case .q2: components = DateComponents(year: 2026, month: 10, day: 13)
        case .q3: components = DateComponents(year: 2027, month: 1, day: 5)
        case .q4: components = DateComponents(year: 2027, month: 3, day: 22)
        case .sm1, .sm2: return nil
        }
        guard let start = calendar.date(from: components), start > day else { return nil }
        return start
    }

    static func eligibleCourses(_ courses: [UnifiedCourseData], term: TermLabel) -> [UnifiedCourseData] {
        guard quarters.contains(term) else { return [] }
        // Match the Courses page's current-grade scope. This is a display scope,
        // not evidence for an inferred school year or transcript classification.
        let gradeYear = courses.compactMap(\.gradeYear).max().map { GradeLevel.from(gradeYear: $0).gradeYear } ?? nil
        var seen: Set<String> = []
        return courses.filter { $0.gradeYear == gradeYear && $0.hasGradebookParams &&
            $0.availableTerms.contains(term) && seen.insert($0.id).inserted }
    }

    static func params(course: UnifiedCourseData, term: TermLabel) -> GradeInfoParams {
        GradeInfoParams(stuId: course.stuId, corNumId: course.corNumId,
                        gbId: course.gbId, section: course.section, bucket: term.bucket)
    }
}

enum SchoolCalendarDate {
    static func normalize(_ source: String) -> String? {
        if let date = AttendanceSchoolDate.normalize(source) { return date }
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, (1...2).contains(parts[0].count), (1...2).contains(parts[1].count),
              parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let month = Int(parts[0]), let day = Int(parts[1]), let year = Int(parts[2]) else { return nil }
        let iso = String(format: "%04d-%02d-%02d", 2000 + year, month, day)
        return AttendanceSchoolDate.components(iso) == nil ? nil : iso
    }
}


/// All fields are required: an old snapshot cannot guess an assignment from
/// a displayed name. These are account/course hashes and source identities,
/// never credentials or session values.
struct AssignmentLink: Equatable {
    var scope: String
    var courseID: String
    var term: TermLabel
    var assignmentID: String


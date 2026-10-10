import Foundation

/// Local search over the supplied official Calendar assignment snapshot.
/// Coverage and freshness stay with that snapshot's caller.
enum AssignmentSearch {
    static func results(in assignments: [CalendarAssignment], query: String) -> [CalendarAssignment] {
        let tokens = normalize(String(query.prefix(256))).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        struct Match {
            var assignment: CalendarAssignment
            var title: String
            var courseName: String
            var identifier: String
            var sourceIndex: Int
        }
        let matches = assignments.enumerated().compactMap { index, assignment -> Match? in
            let title = normalize(assignment.title)
            let courseName = normalize(assignment.course.courseName)
            let category = normalize(assignment.category)
            let fields = [title, courseName, category]
            guard tokens.allSatisfy({ token in fields.contains { $0.contains(token) } }) else { return nil }
            return Match(assignment: assignment, title: title, courseName: courseName,
                         identifier: normalize(assignment.id), sourceIndex: index)
        }
        return matches.sorted { lhs, rhs in
            // CalendarAssignment.date is the normalized source school day,
            // never an inferred date or a timestamp derived from fetch time.
            if lhs.assignment.date != rhs.assignment.date {
                switch (lhs.assignment.date, rhs.assignment.date) {
                case let (a?, b?): return a < b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): break
                }
            }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            if lhs.courseName != rhs.courseName { return lhs.courseName < rhs.courseName }
            if lhs.identifier != rhs.identifier { return lhs.identifier < rhs.identifier }
            if lhs.assignment.id != rhs.assignment.id { return lhs.assignment.id < rhs.assignment.id }
            return lhs.sourceIndex < rhs.sourceIndex
        }.map(\.assignment)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

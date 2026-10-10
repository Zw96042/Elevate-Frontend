import Foundation

struct NotificationPreferences: Codable, Equatable, Sendable {
    var gradeChanges: Bool
    var reminders: Bool

    init(gradeChanges: Bool = false, reminders: Bool = true) {
        self.gradeChanges = gradeChanges
        self.reminders = reminders
    }

    private enum CodingKeys: String, CodingKey {
        case gradeChanges, reminders
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gradeChanges = try values.decodeIfPresent(Bool.self, forKey: .gradeChanges) ?? false
        reminders = try values.decodeIfPresent(Bool.self, forKey: .reminders) ?? true
        // Retired preview/name flags are ignored; alerts always contain names, never scores.
    }
}

/// Notification bodies receive names only; grade values have no input path.
enum NotificationText {
    static let contentVersion = 3
    static func gradeChanges(courseNames: [String]) -> String {
        let generic = "Your grades changed. Open Elevate to review them."
        var seen = Set<String>()
        let names = courseNames.compactMap { raw -> String? in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && seen.insert(name).inserted ? name : nil
        }
        guard !names.isEmpty else { return generic }
        let visible = Array(names.prefix(3))
        let remaining = names.count - visible.count
        let listed: String
        if remaining > 0 {
            listed = visible.joined(separator: ", ") + ", and \(remaining) other \(remaining == 1 ? "class" : "classes")"
        } else if visible.count > 1, let last = visible.last {
            let separator = visible.count == 2 ? " and " : ", and "
            listed = visible.dropLast().joined(separator: ", ") + separator + last
        } else {
            listed = visible[0]
        }
        return "Grades updated in \(listed). Open Elevate to review them."
    }

    static func reminder(courseName: String, title: String) -> String {
        let generic = "You have a school reminder. Open Elevate to view it."
        let course = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !course.isEmpty, !title.isEmpty { return "\(course): \(title)" }
        if !title.isEmpty { return title }
        if !course.isEmpty { return "\(course): School reminder" }
        return generic
    }
}

/// Account-scoped storage and validation belong to the caller.
struct LocalReminder: Codable, Equatable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var courseID: String
    var term: TermLabel
    var assignmentID: String?
    var title: String
    var courseName: String
    var fireDate: Date
    var createdAt: Date = Date()
}

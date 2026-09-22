import SwiftUI

// Rows and sheets shared by the Calendar month page and its day view.

/// Course names through the shared class-name formatter.
enum CourseTitle {
    static func display(_ raw: String) -> String {
        ClassNameFormatter.format(
            raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
        )
    }
}

// MARK: - Rows

/// A source assignment as an open row: a Done ring, title, class, then
/// category and any Skyward status. Opens the assignment when it has a
/// gradebook. Graded work is done by itself, with a fixed check; otherwise
/// Done is a personal mark. Either way the title goes quiet and Skyward's
/// own words stay.
struct CalendarAssignmentRow: View {
    var assignment: CalendarAssignment
    /// Undated rows show Skyward's unreadable date text, when there is any.
    var showsSourceDate = false
    /// Lists spanning days say when each row is due.
    var showsDueDay = false
    var isDone = false
    var onToggleDone: (() -> Void)? = nil
    var onOpen: (() -> Void)?
    /// A personal reminder for this assignment.
    var onRemind: (() -> Void)? = nil
    var identifier: String
    var doneIdentifier: String = "calendar.done"
    /// Keeps the done column even when this row can't be marked, so titles
    /// line up down a list.
    var reservesDoneLane = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The same width as `PersonalEventRow`'s time column.
    @ScaledMetric(relativeTo: .subheadline) private var laneWidth: CGFloat = 66

    /// The lane's width after the page margin: the events' time column, or
    /// just the ring at accessibility sizes.
    private var leadLane: CGFloat { dynamicTypeSize.isAccessibilitySize ? 34 : laneWidth }

    private struct Status: Hashable {
        var text: String
        var isMissing = false
        var isAbsent = false
    }

    private var title: String {
        let text = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Untitled assignment" : text
    }

    private var courseName: String { CourseTitle.display(assignment.course.courseName) }

    private var category: String? {
        let text = assignment.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Only Skyward's own flags; nothing is inferred from attendance.
    private var statuses: [Status] {
        let types = Set(assignment.meta.map { $0.type.lowercased() })
        var result: [Status] = []
        if types.contains("missing") { result.append(Status(text: "Missing", isMissing: true)) }
        if types.contains("absent") { result.append(Status(text: "Absent", isAbsent: true)) }
        if types.contains("nocount") { result.append(Status(text: "No count")) }
        return result
    }

    private var sourceDate: String? {
        guard showsSourceDate else { return nil }
        let text = assignment.sourceDate.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No date in Skyward" : "Date in Skyward: \(text)"
    }

    private var dueDay: String? {
        guard showsDueDay else { return nil }
        guard let day = CalendarDay(iso: assignment.date) else { return "No school date" }
        return "Due \(day.date(calendar: CalendarAgenda.calendar).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }

    /// Skyward posted a grade and doesn't mark it missing.
    private var isGraded: Bool { assignment.isDoneByGrade }
    private var showsDone: Bool { isDone || isGraded }

    private var spokenLabel: String {
        var parts = [title, courseName]
        if isGraded { parts.append("graded") } else if isDone { parts.append("marked done") }
        parts += [category, dueDay, sourceDate].compactMap { $0 }
        parts += statuses.map(\.text)
        return parts.joined(separator: ", ")
    }


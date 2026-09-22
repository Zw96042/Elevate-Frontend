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

    private var hasLane: Bool { onToggleDone != nil || isGraded || reservesDoneLane }

    var body: some View {
        // The ring is a sibling of the row's button, not layered over it,
        // so a tap on it reaches it on every iOS version. Its lane matches
        // the events' time column, so titles align.
        HStack(spacing: 0) {
            if hasLane {
                ZStack(alignment: .leading) {
                    if isGraded {
                        gradedMark
                    } else if let onToggleDone {
                        doneButton(onToggleDone)
                    }
                }
                .padding(.leading, Metrics.page - 10)
                // Page margin plus the time column: the bar then sits where
                // event rows put theirs.
                .frame(width: Metrics.page + leadLane, alignment: .leading)
                .frame(maxHeight: .infinity)
            }
            mainElement
        }
        .fixedSize(horizontal: false, vertical: true)
            .accessibilityActions {
                if let onToggleDone, !isGraded {
                    Button(isDone ? "Mark not done" : "Mark done", action: onToggleDone)
                }
                if let onRemind {
                    Button("Remind me", action: onRemind)
                }
            }
            // Reminders live in the row's menu, keeping a row to one control.
            .contextMenu {
                if let onToggleDone, !isGraded {
                    Button(isDone ? "Mark Not Done" : "Mark Done",
                           systemImage: isDone ? "circle" : "checkmark.circle", action: onToggleDone)
                }
                if let onRemind {
                    Button("Remind Me", systemImage: "bell", action: onRemind)
                }
                if let onOpen {
                    Button("Open in Courses", systemImage: "arrow.forward", action: onOpen)
                }
            }
    }

    @ViewBuilder
    private var mainElement: some View {
        if let onOpen {
            Button(action: onOpen) {
                content(showsChevron: true)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(spokenLabel)
            .accessibilityHint("Opens this assignment in Courses")
            .accessibilityIdentifier(identifier)
        } else {
            content(showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
                .accessibilityIdentifier(identifier)
        }
    }

    private func doneButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isDone ? Color.themeAccent : Color.muted)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScopePressStyle())
        .accessibilityLabel("Done, \(title)")
        .accessibilityValue(isDone ? "Checked" : "Not checked")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier(doneIdentifier)
    }

    /// Graded work can't be un-done here; the check is a fact, not a control.
    private var gradedMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title2)
            .foregroundStyle(Color.themeAccent)
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.faint)
            .accessibilityHidden(true)
    }

    /// The class, category, due day and Skyward's own status words on one
    /// quiet line; only Missing and Absent take a color.
    private var detailText: Text {
        var parts = [courseName]
        if let category { parts.append(category) }
        if let dueDay { parts.append(dueDay) }
        var text = Text(parts.joined(separator: " · ")).foregroundStyle(Color.muted)
        if isGraded {
            text = text + Text("  Graded").fontWeight(.semibold).foregroundStyle(Color.themeAccent)
        }
        for status in statuses {
            let color = status.isMissing ? Color.gradeAttention : (status.isAbsent ? Color.gradeWarning : Color.ink)
            text = text + Text("  \(status.text)").fontWeight(.semibold).foregroundStyle(color)
        }
        return text
    }

    private func content(showsChevron: Bool) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        return HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if !stacked {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(showsDone ? Color.faint : Color.themeAccent)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(showsDone ? Color.muted : Color.ink)
                        .strikethrough(showsDone, color: Color.muted)
                    detailText
                        .font(.subheadline)
                    if let sourceDate {
                        Text(sourceDate)
                            .font(.footnote)
                            .foregroundStyle(Color.muted)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            if showsChevron { chevron }
        }
        .padding(.leading, hasLane ? 12 : Metrics.page)
        .padding(.trailing, Metrics.page)
        .padding(.vertical, Metrics.rowPadding)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

}

// MARK: - List sheets

/// Assignments grouped by quarter in a sheet: work without a date, or
/// work Skyward marks missing. Rows keep their Done ring and open the
/// assignment in Courses.
struct AssignmentListSheet: View {
    struct RowGroup: Identifiable {
        var title: String
        /// A short token for identifiers, such as `Q1`.
        var key: String
        var rows: [CalendarAssignment]
        var id: String { key }
    }

    var title: String
    var identifier: String
    var groups: [RowGroup]
    var attendance: [AttendanceRecord]
    var showsSourceDate = false
    var showsDueDay = false
    var isDone: (CalendarAssignment) -> Bool
    var canToggleDone: (CalendarAssignment) -> Bool
    var onToggleDone: (CalendarAssignment) -> Void
    var onOpen: (CalendarAssignment) -> Void
    var onRemind: (CalendarAssignment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var themeManager = ThemeManager.shared


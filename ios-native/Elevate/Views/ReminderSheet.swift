import SwiftUI
import UIKit

/// What a personal reminder is about. `dueDay` is a valid Skyward school
/// date (yyyy-MM-dd) or nil; a reminder never invents a due date.
struct ReminderRequest: Identifiable {
    var accountScope: String
    var course: UnifiedCourseData
    var term: TermLabel
    var assignmentID: String?
    var title: String
    var dueDay: String?

    var id: String { "\(accountScope)|\(course.id)|\(term.rawValue)|\(assignmentID ?? title)" }

    /// The school day at local noon, so it names the same day anywhere.
    var dueDate: Date? {
        guard let dueDay, let parts = AttendanceSchoolDate.components(dueDay) else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
    }

    /// The evening before a verified due day when that is still ahead;
    /// otherwise tomorrow at 6:00 PM.
    static func defaultFireDate(dueDate: Date?, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        if let dueDate,
           let dayBefore = calendar.date(byAdding: .day, value: -1, to: dueDate),
           let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayBefore),
           evening > now.addingTimeInterval(60) {
            return evening
        }
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow) else {
            return now.addingTimeInterval(24 * 60 * 60)
        }
        return evening
    }
}

/// A personal reminder: a title and a time chosen here, saved on this
/// iPhone for the current account. Skyward's due date appears only when it
/// is a valid school date, and the reminder time is never presented as one.
/// Permission is requested only when Save is tapped.
struct ReminderSheet: View {
    var request: ReminderRequest

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var title: String
    @State private var fireDate: Date
    @State private var isSaving = false
    @State private var savedWithoutAlert = false
    @State private var saveMessage: String?
    @State private var saveRevision = 0
    @FocusState private var titleFocused: Bool

    init(request: ReminderRequest) {
        self.request = request
        let trimmed = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        _title = State(initialValue: trimmed.isEmpty ? "Assignment" : trimmed)
        _fireDate = State(initialValue: ReminderRequest.defaultFireDate(dueDate: request.dueDate))
    }

    private var notifications: SchoolNotifications { store.notifications }

    private var courseName: String {
        ClassNameFormatter.format(request.course.courseName.replacingOccurrences(of: " ", with: "_"))
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && trimmedTitle.count <= 250 && fireDate > Date() && !isSaving
            && notifications.accountScope == request.accountScope
    }

    /// Reminders already saved for this assignment, soonest first.
    private var existing: [LocalReminder] {
        let courseID = SchoolNotifications.notificationCourseID(for: request.course)
        return notifications.reminders.filter {
            $0.courseID == courseID && $0.term == request.term
                && $0.assignmentID == request.assignmentID && $0.fireDate > Date()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GroupLabel("Reminder")
                        .frame(minHeight: 32, alignment: .bottomLeading)
                        .padding(.bottom, 4)
                    titleRow
                    InsetDivider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(courseName)
                            .font(.body)
                            .foregroundStyle(Color.ink)
                        Text(request.term.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Color.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    GroupLabel("When")
                        .frame(minHeight: 32, alignment: .bottomLeading)
                        .padding(.top, Metrics.sectionGap - 8)
                        .padding(.bottom, 4)
                    DatePicker(
                        "Remind me",
                        selection: $fireDate,
                        in: Date().addingTimeInterval(60)...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(.body)
                    .padding(.vertical, 6)
                    .frame(minHeight: 52)
                    .disabled(savedWithoutAlert)
                    .accessibilityIdentifier("reminder.date")
                    footnote(dueDateNote)

                    if !existing.isEmpty {
                        existingSection
                    }

                    statusSection
                        .padding(.top, 16)
                }
                .padding(.horizontal, Metrics.page)
                .padding(.bottom, 24)
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { titleFocused = false }
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .softScrollEdges()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Remind Me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !savedWithoutAlert {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if savedWithoutAlert {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    } else if isSaving {
                        ProgressView()
                            .accessibilityLabel("Saving reminder")
                    } else {
                        Button("Save", action: save)
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                            .accessibilityIdentifier("reminder.save")
                    }
                }
            }
            .task { await notifications.refreshAuthorization() }
            .onChange(of: notifications.accountScope) { _, scope in
                if scope != request.accountScope { dismiss() }
            }
            .sensoryFeedback(.success, trigger: saveRevision)
        }
        .tint(Color.themeAccent)
        .foregroundStyle(Color.ink)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: Rows

    private var titleRow: some View {
        HStack(spacing: 12) {
            Text("Title")
                .font(.body.weight(titleFocused ? .semibold : .regular))
                .foregroundStyle(titleFocused ? Color.themeAccent : Color.ink)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            TextField("Assignment", text: $title)
                .font(.body)
                .multilineTextAlignment(.trailing)
                .submitLabel(.done)
                .focused($titleFocused)
                .disabled(savedWithoutAlert)
                .accessibilityLabel("Reminder title")
                .accessibilityIdentifier("reminder.title")
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture { titleFocused = true }
    }


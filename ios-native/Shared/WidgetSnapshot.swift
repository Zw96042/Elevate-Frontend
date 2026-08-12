import Foundation

/// Data the main app writes for the widget extension to render.
/// Lives in the app-group UserDefaults so both processes can see it.
struct WidgetSnapshot: Codable {
    var generatedAt: Date
    var termShortName: String            // "Q1", "SM1", ...
    var weightedGPA: Double?
    var unweightedGPA: Double?
    var courses: [CourseGrade]           // current-term courses, schedule order
    var recentGrades: [AssignmentItem]   // newest graded work first
    var missingAssignments: [AssignmentItem]
    var absentAssignments: [AssignmentItem]? = nil
    var gpaHistory: [GPAHistoryPoint]? = nil
    var messages: [MessageItem]          // newest first
    var recentGradesTotal: Int? = nil
    var missingAssignmentsTotal: Int? = nil
    var absentAssignmentsTotal: Int? = nil
    var isComplete: Bool? = nil

    struct CourseGrade: Codable, Hashable {
        var name: String
        var score: Double?
    }

    struct AssignmentItem: Codable, Hashable {
        var className: String
        var name: String
        var gradeText: String            // "94" or "18/20"; empty for missing work
        var date: String                 // "M/d/yy" as Skyward reports it
    }

    struct MessageItem: Codable, Hashable {
        var from: String
        var subject: String
        var date: String
        var isAdministrator: Bool
    }

    struct GPAHistoryPoint: Codable, Hashable {
        var term: String
        var weighted: Double
    }

    /// Sample data for widget placeholders and the gallery.
    static let placeholder = WidgetSnapshot(
        generatedAt: Date(),
        termShortName: "Q4",
        weightedGPA: 102.47,
        unweightedGPA: 95.12,
        courses: [
            CourseGrade(name: "AP Calculus BC", score: 96),
            CourseGrade(name: "AP Physics", score: 93),
            CourseGrade(name: "English 4", score: 98),
            CourseGrade(name: "Economics", score: 95),
            CourseGrade(name: "Computer Science 3", score: 100),
        ],
        recentGrades: [
            AssignmentItem(className: "AP Calculus BC", name: "Series Quiz", gradeText: "95", date: "6/10/26"),
            AssignmentItem(className: "English 4", name: "Final Essay", gradeText: "98", date: "6/9/26"),
            AssignmentItem(className: "AP Physics", name: "Lab Report 12", gradeText: "47/50", date: "6/8/26"),
        ],
        missingAssignments: [
            AssignmentItem(className: "Economics", name: "Ch. 14 Worksheet", gradeText: "", date: "6/5/26"),
        ],
        absentAssignments: [
            AssignmentItem(className: "AP Physics", name: "Momentum Lab", gradeText: "", date: "6/4/26"),
        ],
        gpaHistory: [
            GPAHistoryPoint(term: "Q1", weighted: 99.2),
            GPAHistoryPoint(term: "Q2", weighted: 100.1),
            GPAHistoryPoint(term: "Q3", weighted: 101.6),
            GPAHistoryPoint(term: "Q4", weighted: 102.47),
        ],
        messages: [
            MessageItem(from: "J. Smith", subject: "Final exam review posted", date: "6/11/26", isAdministrator: false),
            MessageItem(from: "Administrator", subject: "Schedule for finals week", date: "6/10/26", isAdministrator: true),
        ]
    )
}

enum WidgetSnapshotStore {
    private static let key = "widgetSnapshot"

    static func save(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }

    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
    }
}

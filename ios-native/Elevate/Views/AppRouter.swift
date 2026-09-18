import SwiftUI

/// Screens pushed inside the Courses tab.
enum CoursesRoute: Hashable {
    case course(UnifiedCourseData)
    /// An official source assignment, focused only after the quarter loads.
    case assignment(UnifiedCourseData, TermLabel, String, UUID)
    case gpa
    /// Planning for one class in the term its detail screen showed.
    case gradeGoal(UnifiedCourseData, TermLabel)
    /// Skyward's missing flags for one quarter, opened below the GPA line.
    case missingWork
    case gpaConverter
    /// One high-school year's completed semesters on the chosen scale.
    case gpaConverterYear(Int, GPAConversionPolicy)
    case collegeProfiles
    /// One `CollegeProfileCatalog` profile, by its ID.
    case collegeProfile(String)
    /// Official changes Elevate found, newest first.
    case gradeChanges
}

/// Screens pushed inside the Calendar tab.
enum CalendarRoute: Hashable {
    /// Today plus the next six school-calendar days for Calendar's quarter.
    case thisWeek
    /// One day opened from the month grid, by its yyyy-MM-dd school date.
    case day(String)
}

/// School records pushed inside Settings.
enum RecordsRoute: Hashable {
    case pastCourses
    case pastCourse(UnifiedCourseData)
    case documents
    case studentInfo
    case fees
}

/// Tab selection, each stack's navigation path, the shared Settings sheet and
/// the search queries. Lives with the views; it holds no account data, and the
/// root clears it when the account changes. Nothing here is persisted.
@Observable
@MainActor
final class AppRouter {
    enum Tab: Hashable {
        case courses
        case calendar
        case inbox
        case search
    }

    /// What the one Search tab searches. Chosen as Search is entered, from
    /// the screen it was entered from, and kept until Search is entered again.
    enum SearchDomain: Hashable {
        case assignments
        case colleges
    }

    var selectedTab: Tab = .courses {
        didSet {
            if selectedTab != .courses { pendingAssignment = nil }
        }
    }
    struct AssignmentNavigation: Identifiable, Hashable {
        let id: UUID
        let route: CoursesRoute
    }
    private(set) var pendingAssignment: AssignmentNavigation?
    var coursesPath: [CoursesRoute] = []
    var calendarPath: [CalendarRoute] = []
    /// The path inside Settings, where school records live.
    var recordsPath: [RecordsRoute] = []
    /// One Settings sheet for every root screen, presented by the root.
    var isShowingSettings = false
    /// Assignments typed in Search; kept in memory only while the account
    /// stays the same.
    var searchQuery = ""
    /// Colleges typed in Search, kept apart from the assignment query.
    var collegeQuery = ""
    /// Set only by `select(_:)` and account changes. Read it through
    /// `activeSearchDomain` anywhere other than the Search tab's content.
    private(set) var searchDomain: SearchDomain = .assignments
    /// Whether iOS 26's system search field is active. The system sets it
    /// when Search is tapped; the app only ever lowers it.
    var isSearchPresented = false
    var collegeFocusRequest = 0

    /// The longest query kept; longer text is cut, not rejected.
    static let searchQueryLimit = 256


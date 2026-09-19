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

    /// The domain the shared search field edits: Search's chosen domain while
    /// Search is selected, assignments everywhere else.
    var activeSearchDomain: SearchDomain {
        selectedTab == .search ? searchDomain : .assignments
    }

    /// The query for `activeSearchDomain`.
    var activeSearchQuery: String {
        activeSearchDomain == .colleges ? collegeQuery : searchQuery
    }

    /// Whether the Courses stack currently shows College profiles or one
    /// college, as its last screen.
    var isShowingCollegeProfiles: Bool {
        guard selectedTab == .courses else { return false }
        switch coursesPath.last {
        case .collegeProfiles?, .collegeProfile?: return true
        default: return false
        }
    }

    /// The tab bar's selection setter. Entering Search chooses its domain
    /// from the screen being left, before the selection hides that screen;
    /// reselecting Search keeps the domain it has.
    func select(_ tab: Tab) {
        if tab == .search, selectedTab != .search {
            let domain: SearchDomain = isShowingCollegeProfiles ? .colleges : .assignments
            if searchDomain != domain { searchDomain = domain }
        }
        if selectedTab != tab { selectedTab = tab }
    }

    /// Edits the active domain's query, cut to the limit. The other
    /// domain's query is untouched.
    func setActiveSearchQuery(_ text: String) {
        let clamped = String(text.prefix(Self.searchQueryLimit))
        switch activeSearchDomain {
        case .assignments:
            if searchQuery != clamped { searchQuery = clamped }
        case .colleges:
            if collegeQuery != clamped { collegeQuery = clamped }
        }
    }

    /// Lowers the system search field. The query is kept.
    func dismissSearch() {
        if isSearchPresented { isSearchPresented = false }
    }

    /// Explicit entry points open the same bottom search field as the tab.
    func openCollegeSearch() {
        searchDomain = .colleges
        selectedTab = .search
        collegeFocusRequest += 1
        isSearchPresented = true
    }

    /// Opens a college from Search in Courses, above College profiles, so
    /// Back returns to the catalog. A college already on top is replaced
    /// rather than stacked. Search keeps the college query, and choosing
    /// Search from this screen searches colleges again.
    func showCollege(_ id: String) {
        pendingAssignment = nil
        var path = coursesPath
        if case .collegeProfile? = path.last { path.removeLast() }
        if path.last != .collegeProfiles { path.append(.collegeProfiles) }
        path.append(.collegeProfile(id))
        coursesPath = path
        select(.courses)
    }

    /// Handles `com.zacharywilson.elevate://` links from the widgets.
    /// `gpa` replaces the Courses path rather than adding to it, so a link
    /// that arrives while a class is open lands on GPA with one step back.
    /// `history` opens Settings on Past courses with School records one step back.
    /// Returns whether the link opened GPA.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard url.scheme == "com.zacharywilson.elevate" else { return false }
        pendingAssignment = nil
        if url.host != "history" {
            isShowingSettings = false
            recordsPath = []
        }
        switch url.host {
        case "gpa":
            selectedTab = .courses
            coursesPath = [.gpa]
            return true
        case "inbox":
            selectedTab = .inbox
        case "attendance", "calendar":
            // Attendance lives on Calendar's first page.
            selectedTab = .calendar
            calendarPath = []
        case "history":
            selectedTab = .courses
            recordsPath = [.pastCourses]
            isShowingSettings = true
        default:
            selectedTab = .courses
            coursesPath = []
        }
        return false
    }


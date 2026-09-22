import SwiftUI
import UIKit

/// The school year as scrolling months, as in Calendar. Each day's number
/// is shaded by how much Skyward work is due; a dot marks an attendance
/// record; events from the person's own calendars run beneath the numbers.
/// Pinching shows more or less of those events. Tapping a day opens it.
/// A quarter's assignments are requested only once its days are on screen.
/// Attendance marks a recorded exception only: a day without one is never
/// called present, and an absence never makes an assignment missing. Only
/// Skyward's own descriptions, titles, categories and statuses are shown.
struct CalendarView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CalendarDensity.storageKey) private var densityValue = CalendarDensity.bars.rawValue
    @State private var showingConnect = false
    @State private var today = CalendarDay.today()
    /// The grid's rows, zoom and scroll position. Only the month list
    /// reads the zoom, so a pinch never re-renders the rest of the page.
    @State private var grid = CalendarGridModel(
        level: CalendarDensity(rawValue: UserDefaults.standard.object(forKey: CalendarDensity.storageKey) as? Int
                               ?? CalendarDensity.bars.rawValue) ?? .bars
    )
    /// The list scrolls to this month once; Back and tab switches keep
    /// the person's place.
    @State private var didPositionList = false
    /// The day an open day view shows, so its data keeps loading.
    @State private var focusDay: CalendarDay?
    @State private var snapshot = CalendarSnapshot.empty
    @State private var scrollRequest: CalendarMonth?
    @State private var reminder: ReminderRequest?
    @State private var personal = PersonalCalendarStore.shared
    @State private var showingCalendars = false
    @State private var eventDetail: PersonalEventDetails?
    @State private var showingUndated = false
    @State private var showingMissing = false
    @State private var doneRevision = 0
    @State private var doneError: String?

    private var calendar: Calendar { CalendarAgenda.calendar }

    /// The saved level, so the page itself doesn't follow a pinch frame by frame.
    private var density: CalendarDensity { CalendarDensity(rawValue: densityValue) ?? .bars }

    // MARK: - Loading

    /// Changes whenever loading should start over or stop: another account,
    /// sign-in state, this tab leaving view, the app backgrounding, or a
    /// page other than a day view pushed over the month.
    private struct LoadIdentity: Hashable {
        var accountRevision: Int
        var coursesRevision: Int
        var canShowData: Bool
        var isSelected: Bool
        var isActive: Bool
        var isOnCalendar: Bool

        var isLive: Bool { isSelected && isActive && canShowData && isOnCalendar }
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(
            accountRevision: store.accountRevision,
            coursesRevision: store.coursesRefreshRevision,
            canShowData: store.canShowData,
            isSelected: router.selectedTab == .calendar,
            // Not background, rather than active: pulling down Notification
            // Center or a Face ID prompt shouldn't restart loading or drop
            // events, which would shift the page twice.
            isActive: scenePhase != .background,
            isOnCalendar: router.calendarPath.allSatisfy {
                if case .day = $0 { return true } else { return false }
            }
        )
    }

    private struct PersonalLoad: Hashable {
        var base: LoadIdentity
        var months: [CalendarMonth]
    }

    /// Every month in the grid. Calendar loads all of it when it opens, so
    /// nothing arrives or shifts while scrolling.
    private var gridMonths: [CalendarMonth] {
        guard let first = grid.items.first?.month, let last = grid.items.last?.month else { return [] }
        return CalendarMonth.months(in: first...last)
    }


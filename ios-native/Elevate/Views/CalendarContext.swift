import SwiftUI

/// One quarter as the Calendar pages can show it: its saved assignments,
/// whether it is loading or failed, and which classes it does not cover.
struct CalendarQuarterStatus {
    var term: TermLabel
    var state: CalendarQuarterState
    /// Eligible classes with nothing saved.
    var missing: [String]
    /// Classes shown from saved data after a failed refresh.
    var saved: [String]
    var hasEligibleCourses: Bool

    var data: SchoolCalendarData? { state.loadedData }
    var isFailed: Bool { state.failure != nil }
    /// Loading, or about to: nothing saved and no failure yet.
    var isUnknown: Bool { data == nil && !isFailed }
    var isComplete: Bool {
        data != nil && missing.isEmpty && saved.isEmpty && state.error == nil && hasEligibleCourses
    }
    /// Verified empty by every class, with its start still ahead.
    var upcomingStart: Date? {
        guard let data, data.assignments.isEmpty, isComplete else { return nil }
        return SchoolCalendar.upcomingQuarterStart(term: term)
    }
}

/// What the month page and the day view share: the data snapshot, each
/// quarter's status, the done rules and the row actions. Rebuilt with the
/// page's body; it holds references and values, never copies of state.
@MainActor
struct CalendarContext {
    var store: AppStore
    var personal: PersonalCalendarStore
    var snapshot: CalendarSnapshot
    var today: CalendarDay
    /// Identical source rows can't own independent personal marks.
    var ambiguousIDs: Set<String>
    var onOpen: (CalendarAssignment) -> Void
    var onRemind: (CalendarAssignment) -> Void
    var onOpenEvent: (PersonalEvent) -> Void
    var onToggleDone: (CalendarAssignment) -> Void

    var calendar: Calendar { CalendarAgenda.calendar }

    func quarterStatus(_ term: TermLabel) -> CalendarQuarterStatus {
        let state = store.calendarQuarter(term)
        let eligible = SchoolCalendar.eligibleCourses(store.courses ?? [], term: term)
        var missing: [String] = []
        var saved: [String] = []
        if let data = state.loadedData {
            missing = eligible.filter { !data.resolvedCourseIDs.contains($0.id) }.map(\.courseName)
            let missingNames = Set(missing)
            saved = data.failedCourseNames.filter { !missingNames.contains($0) }
        }
        return CalendarQuarterStatus(term: term, state: state, missing: missing, saved: saved,
                                     hasEligibleCourses: !eligible.isEmpty)
    }

    func quarterStatus(for day: CalendarDay) -> CalendarQuarterStatus {
        quarterStatus(CalendarQuarterMap.quarter(for: day))
    }

    /// Personal marks need the current account's own planning store.
    var showsDone: Bool {
        guard let scope = store.localAccountScope else { return false }
        return store.planning.accountScope == scope && !store.planning.completionUnavailable
    }

    /// Graded work is done; otherwise the person's own mark decides.
    func isDone(_ assignment: CalendarAssignment) -> Bool {
        if assignment.isDoneByGrade { return true }
        return showsDone && !ambiguousIDs.contains(assignment.id) && store.planning.completedIDs.contains(assignment.id)
    }

    func canToggleDone(_ assignment: CalendarAssignment) -> Bool {
        !assignment.isDoneByGrade && showsDone && !ambiguousIDs.contains(assignment.id)
    }

    var showsPersonalEvents: Bool { !personal.shownCalendars.isEmpty }

    func events(on day: CalendarDay) -> [PersonalEvent] {
        showsPersonalEvents ? snapshot.events(on: day) : []
    }

    /// A quiet note above a day's rows when its quarter isn't fully covered:
    /// classes that didn't load, classes shown from saved data, or a failed
    /// refresh showing saved work. Nil when everything loaded.
    func coverageNote(for day: CalendarDay) -> String? {
        let status = quarterStatus(for: day)
        guard status.data != nil else { return nil }
        if !status.missing.isEmpty {
            return status.missing.count == 1
                ? "\(CourseTitle.display(status.missing[0])) didn't load"
                : "\(status.missing.count) classes didn't load"
        }
        let asOf = status.state.lastUpdated.map { " as of \(UpdatedText.short($0))" } ?? ""
        if !status.saved.isEmpty {
            return status.saved.count == 1
                ? "\(CourseTitle.display(status.saved[0])) shown\(asOf)"
                : "\(status.saved.count) classes shown\(asOf)"
        }
        if status.state.error != nil { return "Saved assignments\(asOf)" }
        return nil
    }

    /// The line a day shows when it has no assignments. Stated plainly only
    /// when every class loaded and the latest refresh succeeded; otherwise it
    /// says what it covers.
    func emptyDueText(for day: CalendarDay) -> String {
        let status = quarterStatus(for: day)
        if status.isFailed { return "\(status.term.displayName) assignments didn't load" }
        if status.isUnknown { return "Loading \(status.term.displayName)" }
        if !status.hasEligibleCourses { return "No classes this quarter" }
        if !status.missing.isEmpty { return "Nothing due from the classes that loaded" }
        if status.state.error != nil {
            if let updated = status.state.lastUpdated { return "Nothing due as of \(UpdatedText.short(updated))" }
            return "Nothing due in saved assignments"
        }
        return "Nothing due"
    }
}

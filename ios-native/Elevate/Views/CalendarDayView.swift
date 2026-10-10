import SwiftUI

/// One day, opened from the month: what's due, events from the person's
/// own calendars, and attendance records. Days page sideways like Photos,
/// following the finger; the week strip above follows and also picks a day.
/// Missing, Absent and No count come only from Skyward; graded work shows
/// as done.
struct CalendarDayView: View {
    var context: CalendarContext
    /// The day on screen, so the month page keeps its quarter and events loaded.
    @Binding var focusDay: CalendarDay?
    @State private var day: CalendarDay
    /// The page on screen, by day id.
    @State private var page: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(context: CalendarContext, day: CalendarDay, focusDay: Binding<CalendarDay?>) {
        self.context = context
        _focusDay = focusDay
        _day = State(initialValue: day)
        _page = State(initialValue: day.id)
    }

    /// Every day the month page can show, as pages.
    private var days: [CalendarDay] {
        let range = CalendarMonth.browseRange(today: context.today, entryMonths: context.snapshot.index.months)
        return CalendarMonth.days(in: range)
    }

    private var calendar: Calendar { CalendarAgenda.calendar }
    private var week: CalendarWeek { CalendarWeek.containing(day, calendar: calendar) }

    var body: some View {
        VStack(spacing: 0) {
            weekStrip
                .padding(.horizontal, Metrics.page)
                .padding(.bottom, 6)
            Rule()
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(days) { item in
                            ScrollView {
                                dayContent(item)
                                    .padding(.bottom, 32)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .softScrollEdges()
                            .containerRelativeFrame(.horizontal)
                            .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)
                .onAppear {
                    // A lazy pager's first position only lands near its
                    // target; settle it on the opened day, captured now so an
                    // in-between page reported meanwhile can't redirect it.
                    let target = day.id
                    proxy.scrollTo(target)
                    DispatchQueue.main.async { proxy.scrollTo(target) }
                }
                .onChange(of: page) { _, id in
                    guard let id, let shown = CalendarDay(iso: id), shown != day else { return }
                    day = shown
                    UIAccessibility.post(notification: .announcement, argument: shown.title(today: context.today, calendar: calendar))
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(day.calendarMonth.title(calendar: calendar))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { show(context.today) }
                    .disabled(day == context.today)
                    .accessibilityIdentifier("day.today")
            }
        }
        .onAppear { focusDay = day }
        .onChange(of: day) { _, new in focusDay = new }
        .onDisappear { if focusDay == day { focusDay = nil } }
        .accessibilityAction(named: "Next day") { move(by: 1) }
        .accessibilityAction(named: "Previous day") { move(by: -1) }
        // A container, so its identifier doesn't replace its controls'.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("day.screen")
    }

    // MARK: - Moving between days

    private func move(by days: Int) {
        show(day.adding(days, calendar: calendar))
    }

    private func show(_ target: CalendarDay) {
        guard target != day, days.contains(target) else { return }
        day = target
        Motion.perform(reduceMotion ? nil : .smooth(duration: 0.32)) { page = target.id }
        UIAccessibility.post(notification: .announcement, argument: target.title(today: context.today, calendar: calendar))
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(CalendarAgenda.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(week.days) { item in
                    stripDay(item)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.top, 6)
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                guard abs(value.translation.width) > 50 else { return }
                move(by: value.translation.width < 0 ? 7 : -7)
            }
        )
    }

    private func stripDay(_ item: CalendarDay) -> some View {
        let level = context.snapshot.level(item)
        let selected = item == day
        let isToday = item == context.today
        let due = context.snapshot.assignments(on: item).count
        return Button { show(item) } label: {
            Text("\(item.day)")
                .font(.figure(.body, weight: selected || isToday ? .semibold : .regular))
                .foregroundStyle(isToday && level <= 1 ? Color.themeAccent : Color.dayLoadInk(level: level))
                .frame(width: 34, height: 34)
                .background { Circle().fill(Color.dayLoad(level: level)) }
                .overlay {
                    if selected {
                        Circle().strokeBorder(Color.ink, lineWidth: 2).padding(-4)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if context.snapshot.hasAttendance(item) {
                        Circle().fill(Color.gradeWarning).frame(width: 7, height: 7)
                            .overlay { Circle().stroke(Color.appBackground, lineWidth: 1.5) }
                            .offset(x: 3, y: -2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScopePressStyle())
        .accessibilityLabel(item.title(today: context.today, calendar: calendar))
        .accessibilityValue([isToday ? "Today" : nil, due > 0 ? "\(due) due" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("day.strip.\(item.iso)")
    }

    // MARK: - The day

    private func dayContent(_ day: CalendarDay) -> some View {
        // Skyward's order. Checking a row off never moves it out from
        // under the finger.
        let assignments = context.snapshot.assignments(on: day)
        let events = context.events(on: day)
        let records = context.snapshot.attendance(on: day)
        let isToday = day == context.today
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date(calendar: calendar).formatted(.dateTime.weekday(.wide)))
                    .font(.title.weight(.bold))
                    .foregroundStyle(isToday ? Color.themeAccent : Color.ink)
                Text(day.date(calendar: calendar).formatted(.dateTime.month(.wide).day().year()))
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
            }
            .padding(.horizontal, Metrics.page)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("day.title.\(day.iso)")

            GroupLabel("Due")
                .padding(.horizontal, Metrics.page)
                .padding(.top, 12)
            if assignments.isEmpty {
                Text(context.emptyDueText(for: day))
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metrics.page)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("day.due.none.\(day.iso)")
            } else {
                if let note = context.coverageNote(for: day) {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Metrics.page)
                        .padding(.bottom, 2)
                        .accessibilityIdentifier("day.coverage.\(day.iso)")
                }
                ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                    if index > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                    CalendarAssignmentRow(
                        assignment: assignment,
                        isDone: context.isDone(assignment),
                        onToggleDone: context.canToggleDone(assignment) ? { context.onToggleDone(assignment) } : nil,
                        onOpen: assignment.course.hasGradebookParams ? { context.onOpen(assignment) } : nil,
                        onRemind: { context.onRemind(assignment) },
                        identifier: "day.\(day.iso).assignment.\(index)",
                        doneIdentifier: "day.\(day.iso).done.\(index)",
                        reservesDoneLane: true
                    )
                }
            }

            if !events.isEmpty {
                GroupLabel("Events")
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 16)
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                    PersonalEventRow(
                        event: event, day: day.iso, calendar: context.personal.calendar(id: event.calendarID),
                        onOpen: { context.onOpenEvent(event) },
                        identifier: "day.\(day.iso).event.\(index)"
                    )
                }
            }

            if !records.isEmpty {
                GroupLabel("Attendance")
                    .padding(.horizontal, Metrics.page)
                    .padding(.top, 16)
                ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                    if index > 0 { InsetDivider().padding(.horizontal, Metrics.page) }
                    AttendanceRow(record: record, dateTitle: day.title(today: context.today, calendar: calendar))
                        .accessibilityIdentifier("day.\(day.iso).attendance.\(index)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

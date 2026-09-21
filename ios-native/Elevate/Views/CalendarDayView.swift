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


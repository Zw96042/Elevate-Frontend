import Foundation
import Testing
@testable import ElevateCore

@Suite struct CalendarZoomTests {
    @Test func bracketsAndSettlesOnLevels() {
        let mid = CalendarZoom.bracket(1.25)
        #expect(mid.lower == .bars && mid.upper == .titles)
        #expect(abs(mid.fraction - 0.25) < 0.0001)
        #expect(CalendarZoom.bracket(3).lower == .details)
        #expect(CalendarZoom.settle(1.4) == .bars)
        #expect(CalendarZoom.settle(1.6) == .titles)
        // A quick outward pinch carries to the next level.
        #expect(CalendarZoom.settle(1.4, velocity: 2) == .titles)
        #expect(CalendarZoom.settle(-0.2) == .compact)
    }

    @Test func pinchMovesSmoothlyAndGivesAtTheEnds() {
        #expect(CalendarZoom.zoom(start: 1, magnification: 1) == 1)
        let out = CalendarZoom.zoom(start: 1, magnification: 1.5)
        #expect(out > 1.9 && out < 2.1)
        let inward = CalendarZoom.zoom(start: 1, magnification: 0.7)
        #expect(inward < 1 && inward > 0)
        let past = CalendarZoom.zoom(start: 3, magnification: 4)
        #expect(past > 3 && past < 3.25)
        let below = CalendarZoom.zoom(start: 0, magnification: 0.2)
        #expect(below < 0 && below > -0.25)
    }

    @Test func heightsAreContinuousAcrossLevels() {
        let none: (CalendarDensity) -> Bool = { _ in false }
        let atBars = CalendarZoom.eventsHeight(at: 1, depth: 2, hidden: none)
        #expect(atBars == CalendarZoom.eventsHeight(.bars, depth: 2, hasHidden: false))
        let justAbove = CalendarZoom.eventsHeight(at: 1.001, depth: 2, hidden: none)
        #expect(abs(justAbove - atBars) < 0.1)
        let half = CalendarZoom.eventsHeight(at: 2.5, depth: 2, hidden: none)
        let titles = CalendarZoom.eventsHeight(.titles, depth: 2, hasHidden: false)
        let details = CalendarZoom.eventsHeight(.details, depth: 2, hasHidden: false)
        #expect(abs(half - (titles + details) / 2) < 0.0001)
        // A week without events keeps a small, steady gap.
        #expect(CalendarZoom.eventsHeight(.details, depth: 0, hasHidden: false) == CalendarZoom.minimumEventsHeight)
    }

    @Test func lanesFadeInWhereTheirLevelStartsShowingThem() {
        #expect(CalendarZoom.laneOpacity(lane: 0, at: 0) == 0)
        #expect(CalendarZoom.laneOpacity(lane: 0, at: 1) == 1)
        #expect(CalendarZoom.laneOpacity(lane: 3, at: 2) == 0)
        #expect(abs(CalendarZoom.laneOpacity(lane: 3, at: 2.5) - 0.5) < 0.0001)
        #expect(CalendarZoom.laneOpacity(lane: 3, at: 3) == 1)
        #expect(CalendarZoom.lanes(.titles, depth: 7) == CalendarDensity.titles.laneCount)
        #expect(CalendarZoom.lanes(.compact, depth: 7) == 0)
    }
}

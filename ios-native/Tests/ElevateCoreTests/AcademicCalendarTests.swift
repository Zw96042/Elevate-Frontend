import Foundation
import Testing
@testable import ElevateCore

@Suite("Eanes dated academic calendar")
struct AcademicCalendarTests {
    @Test("Official quarter starts and final school days remain inclusive")
    func officialSchoolDays() {
        let days: [(Int, Int, Int, TermLabel)] = [
            (2026, 8, 13, .q1), (2026, 10, 8, .q1),
            (2026, 10, 13, .q2), (2026, 12, 18, .q2),
            (2027, 1, 5, .q3), (2027, 3, 12, .q3),
            (2027, 3, 22, .q4), (2027, 5, 21, .q4),
        ]
        for (year, month, day, term) in days {
            #expect(AcademicCalendar.currentTerm(for: date(year, month, day)) == term)
            #expect(AcademicCalendar.currentTerm(for: date(year, month, day, hour: 23, minute: 59, second: 59)) == term)
        }
    }

    @Test("Adjacent transition instants change exactly at district midnight")
    func transitionInstants() {
        let transitions: [(Int, Int, Int, TermLabel, TermLabel)] = [
            (2026, 8, 1, .sm2, .q1),
            (2026, 10, 13, .q1, .q2),
            (2026, 12, 19, .q2, .sm1),
            (2027, 1, 5, .sm1, .q3),
            (2027, 3, 22, .q3, .q4),
            (2027, 5, 22, .q4, .sm2),
            (2027, 8, 1, .sm2, .q1),
        ]
        for (year, month, day, before, after) in transitions {
            let midnight = date(year, month, day)
            #expect(AcademicCalendar.currentTerm(for: midnight.addingTimeInterval(-1)) == before)
            #expect(AcademicCalendar.currentTerm(for: midnight) == after)
        }
    }

    @Test("Inter-quarter holidays keep the previous quarter until instruction resumes")
    func breaks() {
        for day in 9...12 {
            #expect(AcademicCalendar.currentTerm(for: date(2026, 10, day, hour: 12)) == .q1)
        }
        for day in 13...21 {
            #expect(AcademicCalendar.currentTerm(for: date(2027, 3, day, hour: 12)) == .q3)
        }
    }

    @Test("Preseason and semester review fill the school year's non-instructional periods")
    func semesterReviewAndPreseason() {
        for day in [1, 12] {
            #expect(AcademicCalendar.currentTerm(for: date(2026, 8, day)) == .q1)
        }
        for (year, month, day) in [(2026, 12, 19), (2026, 12, 31), (2027, 1, 1), (2027, 1, 4)] {
            #expect(AcademicCalendar.currentTerm(for: date(year, month, day, hour: 12)) == .sm1)
        }
        for (month, day) in [(5, 22), (6, 1), (7, 31)] {
            #expect(AcademicCalendar.currentTerm(for: date(2027, month, day, hour: 12)) == .sm2)
        }
    }

    @Test("The official dated schedule does not recur in other school years")
    func legacyYearScope() {
        let legacy: [(Int, Int, Int, TermLabel)] = [
            (2025, 10, 13, .q1), (2025, 10, 26, .q2),
            (2025, 12, 19, .q2), (2025, 12, 23, .sm1),
            (2026, 1, 5, .sm1), (2026, 1, 9, .q3),
            (2026, 3, 16, .q4), (2026, 5, 22, .q4),
            (2026, 5, 31, .q4), (2026, 6, 1, .sm2),
            (2027, 10, 13, .q1), (2028, 1, 5, .sm1),
            (2028, 2, 29, .q3), (2028, 3, 16, .q4),
        ]
        for (year, month, day, term) in legacy {
            #expect(AcademicCalendar.currentTerm(for: date(year, month, day, hour: 12)) == term)
        }
    }

    @Test("UTC and traveling phone dates cannot advance the district quarter early")
    func districtTimezone() {
        // Chicago uses UTC-5 in October/March/May and UTC-6 in December/January.
        let transitions: [(Int, Int, Int, Int, TermLabel, TermLabel)] = [
            (2026, 10, 13, 5, .q1, .q2), (2026, 12, 19, 6, .q2, .sm1),
            (2027, 1, 5, 6, .sm1, .q3), (2027, 3, 22, 5, .q3, .q4),
            (2027, 5, 22, 5, .q4, .sm2),
        ]
        for (year, month, day, utcHour, before, after) in transitions {
            let midnight = date(year, month, day, hour: utcHour, zone: "UTC")
            #expect(AcademicCalendar.currentTerm(for: midnight.addingTimeInterval(-1)) == before)
            #expect(AcademicCalendar.currentTerm(for: midnight) == after)
        }
        // Two travelers' local dates straddle Oct 13 while Chicago is still Oct 12.
        let tokyoMorning = date(2026, 10, 13, hour: 9, zone: "Asia/Tokyo")
        let honoluluAfternoon = date(2026, 10, 12, hour: 14, zone: "Pacific/Honolulu")
        #expect(tokyoMorning == honoluluAfternoon)
        #expect(AcademicCalendar.currentTerm(for: tokyoMorning) == .q1)
        #expect(AcademicCalendar.currentTerm(for: honoluluAfternoon) == .q1)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0,
                      minute: Int = 0, second: Int = 0, zone: String = "America/Chicago") -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                  hour: hour, minute: minute, second: second))!
    }
}

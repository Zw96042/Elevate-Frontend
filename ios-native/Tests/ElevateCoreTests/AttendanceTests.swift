import Foundation
import Testing
@testable import ElevateCore

@Suite("Attendance source records")
struct AttendanceTests {
    @Test("Verified four-column history preserves source descriptions and course text")
    func populatedHistory() throws {
        let html = page(rows: row(date: "Thu Sep 3, 2026", attendance: "Excused &amp; funded absence", period: "1", course: "<a href='javascript:classInfo()'>Physics &amp; Lab</a>"))
        let data = try SkywardAttendanceAPI.parse(html)
        #expect(data.availability == .available)
        let record = try #require(data.records.first)
        #expect(record.date == "2026-09-03")
        #expect(record.attendance == "Excused & funded absence")
        #expect(record.period == "1")
        #expect(record.courseName == "Physics & Lab")
        #expect(record.rawCode == nil)
        #expect(record.granularity == .period)
    }

    @Test("Daily and unknown granularity follow explicit source fields only")
    func sourceGranularity() throws {
        let rows = row(date: "09/03/2026", attendance: "Unknown source description", period: "All Day", course: "")
            + row(date: "09/04/2026", attendance: "Source text", period: "Full Day", course: "")
            + row(date: "09/05/2026", attendance: "Absent", period: "", course: "")
            + row(date: "09/06/2026", attendance: "Unrecognized Z", period: "Advisory", course: "Example course")
        let records = try SkywardAttendanceAPI.parse(page(rows: rows)).records
        #expect(records.map(\.granularity) == [.daily, .daily, .unknown, .unknown])
        #expect(records[0].attendance == "Unknown source description")
        #expect(records[2].period == nil)
        #expect(records.allSatisfy { $0.rawCode == nil })
    }

    @Test("Complete recognized zero-row bodies and unlinked empty markers are verified empty")
    func verifiedEmpty() throws {
        for rows in ["", "<tr><td colspan='4'>No attendance records</td></tr>", "<tr><td colspan='4'>No records to display</td></tr>"] {
            let data = try SkywardAttendanceAPI.parse(page(rows: rows))
            #expect(data.records.isEmpty)
            #expect(data.availability == .available)
        }
        for rows in [
            "<tr></tr>", "<tr><td colspan='4'></td></tr>",
            "<tr><td colspan='4'><a>No attendance records</a></td></tr>",
            "<tr><td>No attendance records</td></tr>",
            "<tr><td colspan='4'>No attendance records</td></tr>" + row(),
        ] {
            #expect(throws: SkywardError.self) { _ = try SkywardAttendanceAPI.parse(page(rows: rows)) }
        }
    }

    @Test("Unavailable requires an explicit source message on the Attendance page")
    func unavailable() throws {
        let data = try SkywardAttendanceAPI.parse("<html><head><title>Attendance</title></head><body>Attendance information is not available.</body></html>")
        #expect(data.availability == .unavailable)
        #expect(data.records.isEmpty)
        for html in [
            "<title>Maintenance</title><body>Attendance unavailable</body>",
            "<title>Attendance</title><body>Maintenance in progress</body>",
            "<title>Attendance</title><body>No records to display</body>",
            "<title>Attendance</title><body>Attendance unavailable",
        ] {
            #expect(throws: SkywardError.self) { _ = try SkywardAttendanceAPI.parse(html) }
        }
    }

    @Test("Portal's no-absences-or-tardies row is a verified empty history")
    func noAbsencesOrTardies() throws {
        let marker = "<tr><td colspan='4'>No absences or tardies were found.</td></tr>"
        let data = try SkywardAttendanceAPI.parse(page(rows: marker))
        #expect(data.records.isEmpty)
        #expect(data.availability == .available)
        for rows in [
            marker + row(), marker + marker,
            marker.replacingOccurrences(of: "colspan='4'", with: "colspan='3'"),
            marker.replacingOccurrences(of: "No absences or tardies were found.", with: "<a>No absences or tardies were found.</a>"),
        ] {
            #expect(throws: SkywardError.self) { _ = try SkywardAttendanceAPI.parse(page(rows: rows)) }
        }
    }

    @Test("Separate current-day tables do not duplicate attendance-history records")
    func ignoresTodayTables() throws {
        let today = "<table id='grid_todaysattendance'><tbody><tr><td>Today</td></tr></tbody></table><table id='grid_todaysAttendanceDetail'><tbody><tr><td>Today detail</td></tr></tbody></table>"
        let data = try SkywardAttendanceAPI.parse(page(rows: row()) + today)
        #expect(data.records.count == 1)
    }

    @Test("Portal's omitted tbody close remains valid only with complete rows and table")
    func omittedBodyClose() throws {
        let html = page(rows: row(date: "Wed Sep 16, 2026")).replacingOccurrences(of: "</tbody>", with: "")
        #expect(try SkywardAttendanceAPI.parse(html).records.count == 1)
        #expect(throws: SkywardError.self) {
            _ = try SkywardAttendanceAPI.parse(html.replacingOccurrences(of: "</table>", with: ""))
        }
        let quotedMarkup = page(rows: row(course: "<a onclick=\"show('<table>'); return false\">Physics</a>"))
        #expect(try SkywardAttendanceAPI.parse(quotedMarkup).records.count == 1)
    }


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

    @Test("Duplicate rows retain distinct IDs while distinct-row IDs survive reordering")
    func stableIdentity() throws {
        let first = row(date: "09/03/2026", attendance: "Absent", period: "1", course: "Physics")
        let second = row(date: "09/03/2026", attendance: "Tardy", period: "2", course: "English")
        let original = try SkywardAttendanceAPI.parse(page(rows: first + first + second)).records
        let reordered = try SkywardAttendanceAPI.parse(page(rows: second + first + first)).records
        #expect(Set(original.map(\.id)).count == 3)
        #expect(Set(original.map(\.id)) == Set(reordered.map(\.id)))
        #expect(original.count == 3)
    }

    @Test("School dates normalize deterministically and reject impossible calendar dates")
    func dates() {
        for (source, expected) in [
            ("9/3/2026", "2026-09-03"), ("Thursday, 09/03/2026", "2026-09-03"),
            ("Thu 9/3/2026", "2026-09-03"), ("02/29/2024", "2024-02-29"),
            ("2026-09-03", "2026-09-03"),
            ("Wed Sep 16, 2026", "2026-09-16"), ("Thu Sep 3, 2026", "2026-09-03"),
            ("Thu Feb 29, 2024", "2024-02-29"),
        ] {
            #expect(AttendanceSchoolDate.normalize(source) == expected)
        }
        for source in ["02/29/2026", "02/29/1900", "04/31/2026", "13/01/2026", "00/01/2026", "01/00/2026", "9/3/26", "September 3", "2026-2-03", "9/3/2026 extra", "Wed Feb 29, 2026", "Thu Apr 31, 2026", "Wed Xxx 16, 2026"] {
            #expect(AttendanceSchoolDate.normalize(source) == nil)
        }
    }

    @Test("Display dates preserve the school date at local noon and models round trip")
    func displayDateAndCache() throws {
        let data = try SkywardAttendanceAPI.parse(page(rows: row()))
        let record = try #require(data.records.first)
        let date = try #require(record.displayDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 3)
        #expect(components.hour == 12)
        #expect(try JSONDecoder().decode(AttendanceData.self, from: JSONEncoder().encode(data)) == data)
        var invalid = record
        invalid.date = "2026-02-29"
        #expect(invalid.displayDate == nil)
    }

    @Test("Layout-table ancestors and nested-table rows cannot change history ownership")
    func rowOwnership() throws {
        let wrapped = "<table><tbody><tr><td>" + page(rows: row()) + "</td></tr></tbody></table>"
        #expect(try SkywardAttendanceAPI.parse(wrapped).records.count == 1)
        let nested = row(course: "<table><tbody>" + row() + "</tbody></table>")
        #expect(throws: SkywardError.self) { _ = try SkywardAttendanceAPI.parse(page(rows: nested)) }
    }

    @Test("Malformed and truncated history never becomes an empty or partial response")
    func malformed() {
        let complete = page(rows: row())
        let variants = [
            complete.replacingOccurrences(of: "</table>", with: ""),
            complete.replacingOccurrences(of: "</td>", with: ""),
            complete.replacingOccurrences(of: "</tr>", with: ""),
            complete.replacingOccurrences(of: "<th>Class</th>", with: "<th>Reason</th>"),
            complete.replacingOccurrences(of: "<td scope='row'>09/03/2026</td>", with: "<td scope='row'>02/29/2026</td>"),
            page(rows: "<tr><td>09/03/2026</td><td>Absent</td></tr>"),
            page(rows: row(attendance: "")),
            page(rows: "Unexpected content"),
            page(rows: "<div>Unexpected content</div>"),
            page(rows: row(attendance: "<script>hidden text</script>")),
            page(rows: row()).replacingOccurrences(of: "<tbody>", with: "").replacingOccurrences(of: "</tbody>", with: ""),
            "<title>Attendance</title><body>Service temporarily unavailable</body>",
        ]
        for html in variants {
            #expect(throws: SkywardError.self) { _ = try SkywardAttendanceAPI.parse(html) }
        }
    }

    @Test("Expired and login responses remain authentication errors")
    func expired() {
        for html in ["Your session has expired", "<title>Family Access</title><form id='detailform'><input type='password'></form>"] {
            do {
                _ = try SkywardAttendanceAPI.parse(html)
                Issue.record("Expected an expired-session error")
            } catch SkywardError.sessionExpired {
                // Expected.
            } catch {
                Issue.record("Unexpected error category")
            }
        }
    }

    @Test("Multiple student-history tables and oversized responses are rejected")
    func boundedAndScoped() {
        let multiple = page(rows: row()) + page(rows: row(), tableID: "grid_attendanceHistory2_2")
        #expect(throws: SkywardError.self) { _ = try SkywardAttendanceAPI.parse(multiple) }
        #expect(throws: SkywardError.self) {
            _ = try SkywardAttendanceAPI.parse(String(repeating: "x", count: SkywardAttendanceAPI.maximumHTMLBytes + 1))
        }
        let manyRows = String(repeating: "<tr><td colspan='4'>No records to display</td></tr>", count: SkywardAttendanceAPI.maximumRows + 1)
        #expect(throws: SkywardError.self) { _ = try SkywardAttendanceAPI.parse(page(rows: manyRows)) }
    }

    private func row(date: String = "09/03/2026", attendance: String = "Absent", period: String = "1", course: String = "<a>Physics</a>") -> String {
        "<tr><td scope='row'>\(date)</td><td>\(attendance)</td><td>\(period)</td><td>\(course)</td></tr>"
    }

    private func page(rows: String, tableID: String = "grid_attendanceHistory1_1") -> String {
        "<html><head><title>Attendance</title></head><body><table id='\(tableID)'><thead><tr><th>Date</th><th>Attendance</th><th>Period</th><th>Class</th></tr></thead><tbody>\(rows)</tbody></table></body></html>"
    }
}

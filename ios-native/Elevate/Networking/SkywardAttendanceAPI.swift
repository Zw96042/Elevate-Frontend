import Foundation

/// The verified Student Access attendance-history HTML endpoint.
enum SkywardAttendanceAPI {
    static let maximumHTMLBytes = 4_000_000
    static let maximumRows = 10_000

    static func fetch(baseUrl: String, sessionCodes: SkywardSessionCodes) async throws -> AttendanceData {
        guard let url = URL(string: baseUrl + "sfattendance001.w") else {
            throw SkywardError.invalidResponse("invalid base URL")
        }
        let html = try await SkywardHTTP.post(url: url, fields: SkywardHTTP.sessionFields(sessionCodes))
        return try parse(html)
    }

    static func parse(_ html: String) throws -> AttendanceData {
        try SkywardHTTP.checkSessionExpired(html)
        guard html.utf8.count <= maximumHTMLBytes else {
            throw SkywardError.invalidResponse("attendance response exceeds size limit")
        }
        let root = MiniHTML.parse(html)
        let tables = root.querySelectorAll("table").filter {
            $0.id.range(of: #"^grid_attendanceHistory\d+_\d+$"#, options: .regularExpression) != nil
        }
        guard tables.count <= 1 else {
            throw SkywardError.invalidResponse("attendance history has ambiguous student scope")
        }
        guard let table = tables.first else {
            let title = clean(root.querySelector("title")?.text ?? "")
            let bodyText = clean(root.querySelector("body")?.text ?? "")
            if title.localizedCaseInsensitiveContains("Attendance"),
               html.range(of: #"</title\s*>"#, options: [.regularExpression, .caseInsensitive]) != nil,
               html.range(of: #"</body\s*>"#, options: [.regularExpression, .caseInsensitive]) != nil,
               bodyText.range(of: #"\battendance (?:information |records |history )?(?:is |are )?(?:not available|unavailable|disabled)\b"#,
                              options: [.regularExpression, .caseInsensitive]) != nil {
                return AttendanceData(records: [], availability: .unavailable)
            }
            throw SkywardError.invalidResponse("attendance history table not found")
        }
        try requireCompleteTable(html, tableID: table.id)
        guard table.elements.contains(where: { $0.tagName == "tbody" }) else {
            throw SkywardError.invalidResponse("attendance history body is missing")
        }
        for section in table.elements where ["thead", "tbody", "tfoot"].contains(section.tagName) {
            guard section.elements.allSatisfy({ $0.tagName == "tr" }),
                  section.children.filter(\.isText).allSatisfy({ clean($0.text).isEmpty }) else {
                throw SkywardError.invalidResponse("attendance history section is unrecognized")
            }
        }
        let rows = table.querySelectorAll("tr").filter { nearestTable($0) === table }
        guard rows.count <= maximumRows + 1 else {
            throw SkywardError.invalidResponse("attendance history exceeds row limit")
        }
        let headers = rows.filter { $0.elements.contains { $0.tagName == "th" } }
        guard headers.count == 1, let header = headers.first,
              header.elements.count == 4,
              header.elements.allSatisfy({ $0.tagName == "th" && $0.querySelector("table") == nil }),
              header.elements.map({ clean($0.text).lowercased() }) == ["date", "attendance", "period", "class"] else {
            throw SkywardError.invalidResponse("attendance history columns are unrecognized")
        }

        var records: [AttendanceRecord] = []
        var occurrences: [String: Int] = [:]
        var hasEmptyMarker = false
        for row in rows where row !== header {
            let cells = row.elements
            guard cells.allSatisfy({ $0.tagName == "td" && $0.querySelector("table") == nil
                && $0.querySelector("script") == nil && $0.querySelector("style") == nil }),
                  row.children.filter(\.isText).allSatisfy({ clean($0.text).isEmpty }) else {
                throw SkywardError.invalidResponse("attendance history row is incomplete")
            }
            if isEmptyMarker(row, cells: cells) {
                guard !hasEmptyMarker else { throw SkywardError.invalidResponse("attendance history has repeated empty markers") }
                hasEmptyMarker = true
                continue
            }
            guard cells.count == 4,
                  cells.allSatisfy({ ($0.attribute("colspan") ?? "1") == "1" && ($0.attribute("rowspan") ?? "1") == "1" }),
                  let date = AttendanceSchoolDate.normalize(clean(cells[0].text)) else {
                throw SkywardError.invalidResponse("attendance history row has invalid fields")
            }
            let attendance = clean(cells[1].text)
            guard !attendance.isEmpty else {
                throw SkywardError.invalidResponse("attendance history description is missing")
            }
            let period = optionalText(cells[2].text)
            let course = optionalText(cells[3].text)
            // No raw-code column is present in the verified source contract.
            let fields = [table.id, date, attendance, period ?? "", course ?? ""]
            let identity = fields.map { "\($0.utf8.count):\($0)" }.joined()
            let occurrence = occurrences[identity, default: 0]
            occurrences[identity] = occurrence + 1
            let granularity: AttendanceGranularity
            if ["all day", "full day"].contains(period?.lowercased() ?? "") {
                granularity = .daily
            } else if let period, let periodNumber = Int(period), periodNumber > 0 {
                granularity = .period
            } else {
                granularity = .unknown
            }
            records.append(AttendanceRecord(
                id: "attendance:\(identity):\(occurrence)", date: date, attendance: attendance,
                period: period, courseName: course, granularity: granularity
            ))
        }
        guard !hasEmptyMarker || records.isEmpty else {
            throw SkywardError.invalidResponse("attendance history mixes records and an empty marker")
        }
        return AttendanceData(records: records)
    }

    private static func nearestTable(_ node: HTMLNode) -> HTMLNode? {
        var ancestor = node.parent
        while let current = ancestor {
            if current.tagName == "table" { return current }
            ancestor = current.parent
        }
        return nil
    }

    private static func isEmptyMarker(_ row: HTMLNode, cells: [HTMLNode]) -> Bool {
        guard cells.count == 1, cells[0].attribute("colspan") == "4",
              row.querySelector("a") == nil else { return false }
        return ["no attendance records", "no records to display", "no absences or tardies were found."].contains(clean(cells[0].text).lowercased())
    }

    private static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func optionalText(_ text: String) -> String? {
        let value = clean(text)
        return value.isEmpty ? nil : value
    }

    /// MiniHTML is intentionally tolerant. Check explicit structural closing
    /// tags so a truncated response cannot be accepted as an empty/partial feed.
    private static func requireCompleteTable(_ html: String, tableID: String) throws {
        let noise = #"<!--[\s\S]*?-->|<script\b[^>]*>[\s\S]*?</script\s*>|<style\b[^>]*>[\s\S]*?</style\s*>"#
        let source = html.replacingOccurrences(of: noise, with: "", options: [.regularExpression, .caseInsensitive])
        // Consume every tag so table-like strings inside a link's quoted
        // attributes cannot be mistaken for structural tags.
        let pattern = #"<\s*(/?)\s*([a-z][a-z0-9:-]*)\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>"#
        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        var stack: [String] = []
        var found = false
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let tagRange = Range(match.range, in: source),
                  let nameRange = Range(match.range(at: 2), in: source) else { continue }
            let name = source[nameRange].lowercased()
            let closing = match.range(at: 1).length > 0
            guard ["table", "thead", "tbody", "tfoot", "tr", "td", "th"].contains(name) else { continue }
            if !found {
                guard name == "table", !closing,
                      MiniHTML.parse(String(source[tagRange]) + "</table>").querySelector("table")?.id == tableID else { continue }
                found = true
                stack.append(name)
                continue
            }
            if closing {
                // The verified portal omits </tbody> immediately before
                // </table>, a valid HTML omission. Rows and cells still need
                // explicit closure, and the table itself must be complete.
                if name == "table", stack.last == "tbody" { stack.removeLast() }
                guard stack.last == name else {
                    throw SkywardError.invalidResponse("attendance history structure is incomplete")
                }
                stack.removeLast()
                if stack.isEmpty { return }
            } else {
                guard !source[tagRange].hasSuffix("/>") else {
                    throw SkywardError.invalidResponse("attendance history structure is incomplete")
                }
                stack.append(name)
            }
        }
        throw SkywardError.invalidResponse("attendance history table is truncated")
    }
}

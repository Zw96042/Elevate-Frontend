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


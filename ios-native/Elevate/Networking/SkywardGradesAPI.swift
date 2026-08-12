import Foundation

/// Per-class grade-info dialog: categories, weights, and assignments for one bucket (term).
enum SkywardGradesAPI {
    static func fetchGradeInfo(params: GradeInfoParams, baseUrl: String, sessionCodes: SkywardSessionCodes) async throws -> GradeInfoResult {
        guard let url = URL(string: baseUrl + "httploader.p?file=sfgradebook001.w") else {
            throw SkywardError.invalidResponse("invalid base URL")
        }
        let fields: [(String, String)] = [
            ("action", "viewGradeInfoDialog"),
            ("gridCount", "1"),
            ("fromHttp", "yes"),
            ("stuId", params.stuId),
            ("entityId", params.entityId),
            ("corNumId", params.corNumId),
            ("track", params.track),
            ("section", params.section),
            ("gbId", params.gbId),
            ("bucket", params.bucket),
            ("subjectId", params.subjectId),
            ("dialogLevel", params.dialogLevel),
            ("isEoc", params.isEoc),
            ("ishttp", "true"),
            ("sessionid", sessionCodes.sessionid),
            ("javascript", "filesAdded=jquery.1.8.2.js,qsfmain001.css,sfgradebook.css,qsfmain001.min.js,sfgradebook.js,sfprint001.js"),
            ("encses", sessionCodes.encses),
            ("dwd", sessionCodes.dwd),
            ("wfaacl", sessionCodes.wfaacl),
            ("requestId", String(Int(Date().timeIntervalSince1970 * 1000))),
        ]
        let raw = try await SkywardHTTP.post(url: url, fields: fields, extraHeaders: [
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ])
        try SkywardHTTP.checkSessionExpired(raw)

        // Extract HTML from the CDATA <output> section.
        let html = extractCDATA(raw, tag: "output") ?? raw
        try SkywardHTTP.checkSessionExpired(html)
        return try parseGradeInfoHTML(html, rawResponse: raw)
    }

    static func extractCDATA(_ raw: String, tag: String) -> String? {
        guard let openRange = raw.range(of: "<\(tag)><![CDATA["),
              let closeRange = raw.range(of: "]]></\(tag)>", range: openRange.upperBound..<raw.endIndex) else {
            return nil
        }
        return String(raw[openRange.upperBound..<closeRange.lowerBound])
    }

    // MARK: - Parsing

    static func parseGradeInfoHTML(_ html: String, rawResponse: String) throws -> GradeInfoResult {
        // Empty <data> CDATA means the session died.
        if rawResponse.range(of: #"<data><!\[CDATA\[\s*\]\]></data>"#, options: .regularExpression) != nil {
            throw SkywardError.sessionExpired
        }

        let root = MiniHTML.parse(html)

        // Course / instructor / period from the heading.
        let headingLinks = root.querySelectorAll("h2.gb_heading a")
        let course = clean(headingLinks.first?.text ?? "")
        let instructor = headingLinks.count > 1 ? clean(headingLinks[1].text) : ""
        let period = toInt(root.querySelector("h2.gb_heading span.fXs b")?.text ?? "")

        // Term ("lit") header.
        var litHeader = root.querySelector("table[id^='grid_stuTermSummaryGrid'] thead th")
        if litHeader == nil, let termGrid = root.querySelector("div[id*='stuTermSummaryGrid']") {
            litHeader = termGrid.querySelector("thead th") ?? termGrid.querySelector("th")
        }
        let litHeaderFirstText = litHeader?.children.first(where: { $0.isText })?.text ?? litHeader?.text ?? ""
        let litName = clean(litHeaderFirstText).replacingOccurrences(of: #"Grade\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var litBegin: String? = nil
        var litEnd: String? = nil
        if let spanText = litHeader?.querySelector("span")?.text,
           let match = firstMatch(in: spanText, pattern: #"(\d{2}/\d{2}/\d{4})\s*-\s*(\d{2}/\d{2}/\d{4})"#) {
            litBegin = match[1]
            litEnd = match[2]
        }

        // Summary score.
        var summaryRow = root.querySelector("table[id^='grid_stuTermSummaryGrid'] tbody tr[class]:not(.sf_Section)")
        if summaryRow == nil, let termGrid = root.querySelector("div[id*='stuTermSummaryGrid']") {
            summaryRow = termGrid.querySelector("tbody tr[class]:not(.sf_Section)") ?? termGrid.querySelector("tbody tr")
        }
        let topScore = toDouble(summaryRow?.querySelector("td:last-child")?.text ?? "")
        let topGrade = topScore.map { Int($0.rounded()) }

        let gradebook = parseGradebook(root)

        return GradeInfoResult(
            course: course, instructor: instructor, period: period,
            litName: litName, litBegin: litBegin, litEnd: litEnd,
            gradebook: gradebook, score: topScore, grade: topGrade
        )
    }

    private static func parseGradebook(_ root: HTMLNode) -> [GradeCategory] {
        var rows = root.querySelectorAll("table[id^='grid_stuAssignmentSummaryGrid'] tbody tr")
        if rows.isEmpty, let grid = root.querySelector("div[id*='stuAssignmentSummaryGrid']") {
            rows = grid.querySelectorAll("tr")
        }
        if rows.isEmpty {
            rows = root.querySelectorAll("tr").filter { tr in
                tr.querySelector("a[id='showAssignmentInfo']") != nil
                    || (tr.hasClass("sf_Section") && tr.hasClass("cat"))
            }
        }

        var gradebook: [GradeCategory] = []
        var currentCategoryIndex: Int? = nil
        var lastMainCategoryIndex: Int? = nil
        var afterBoldCategory = false

        for row in rows {
            if row.hasClass("sf_Section") && row.hasClass("cat") {
                let cells = row.querySelectorAll("td")
                guard cells.count > 1 else { continue }
                let nameCell = cells[1]
                let firstTextChild = nameCell.children.first(where: { $0.isText })?.text
                let rawName = clean(firstTextChild ?? nameCell.text)

                let styleAttr = nameCell.attribute("style") ?? ""
                let isBold = styleAttr.range(of: #"font-weight:\s*bold"#, options: [.regularExpression, .caseInsensitive]) != nil

                var weight: Double? = nil
                var adjustedWeight: Double? = nil
                for span in nameCell.querySelectorAll("span") {
                    if let m = firstMatch(in: clean(span.text),
                                          pattern: #"weighted at ([\d.]+)%(?:, adjusted to ([\d.]+)%)?"#,
                                          caseInsensitive: true) {
                        weight = Double(m[1])
                        adjustedWeight = m.count > 2 && !m[2].isEmpty ? Double(m[2]) : nil
                        break
                    }
                }

                if isBold {
                    gradebook.append(GradeCategory(category: rawName, weight: weight, adjustedWeight: adjustedWeight, assignments: []))
                    lastMainCategoryIndex = gradebook.count - 1
                    currentCategoryIndex = lastMainCategoryIndex
                    afterBoldCategory = true
                    continue
                }

                if rawName.range(of: #"RC\d"#, options: [.regularExpression, .caseInsensitive]) != nil, afterBoldCategory {
                    if rawName.range(of: "RC1", options: .caseInsensitive) != nil,
                       let weight, let idx = lastMainCategoryIndex, gradebook[idx].weight == nil {
                        gradebook[idx].weight = weight
                        gradebook[idx].adjustedWeight = adjustedWeight
                    }
                    continue
                }

                gradebook.append(GradeCategory(category: rawName, weight: weight, adjustedWeight: adjustedWeight, assignments: []))
                currentCategoryIndex = gradebook.count - 1
                afterBoldCategory = false
                continue
            }

            guard let link = row.querySelectorAll("a").first(where: { $0.id == "showAssignmentInfo" }),
                  let catIndex = currentCategoryIndex else { continue }
            let cells = row.querySelectorAll("td")
            func cell(_ i: Int) -> HTMLNode? { cells.indices.contains(i) ? cells[i] : nil }

            let date = clean(cell(0)?.text ?? "")
            let name = clean(link.text)
            let grade = toInt(cell(2)?.text ?? "")
            let score = toDouble(cell(3)?.text ?? "")
            let pointsText = clean(cell(4)?.text ?? "")

            var earned: Double? = nil
            var total: Double? = nil
            if let m = firstMatch(in: pointsText, pattern: #"(-?\d+(?:\.\d+)?)\s*out of\s*(-?\d+(?:\.\d+)?)"#, caseInsensitive: true) {
                earned = Double(m[1])
                total = Double(m[2])
            }

            var meta: [AssignmentMeta] = []
            if let tooltip = cell(5)?.attribute("tooltip") {
                meta.append(AssignmentMeta(type: "missing", note: tooltip))
            }
            if let tooltip = cell(6)?.attribute("tooltip") {
                meta.append(AssignmentMeta(type: "noCount", note: tooltip))
            }
            if let tooltip = cell(7)?.attribute("tooltip") {
                meta.append(AssignmentMeta(type: "absent", note: tooltip))
            } else {
                let absentText = (cell(7)?.text ?? "").trimmingCharacters(in: .whitespaces)
                if !absentText.isEmpty, absentText != "\u{00a0}", !absentText.contains("out of") {
                    meta.append(AssignmentMeta(type: "absent", note: absentText))
                }
            }

            gradebook[catIndex].assignments.append(GradeInfoAssignment(
                date: date, name: name, grade: grade, score: score,
                pointsEarned: earned, pointsTotal: total, meta: meta
            ))
        }

        return gradebook.filter { !($0.weight == 0 && $0.assignments.isEmpty) }
    }

    // MARK: - Text helpers

    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func toInt(_ text: String) -> Int? {
        firstMatch(in: clean(text), pattern: #"^-?\d+"#).flatMap { Int($0[0]) }
    }

    static func toDouble(_ text: String) -> Double? {
        firstMatch(in: clean(text), pattern: #"-?\d+(?:\.\d+)?"#).flatMap { Double($0[0]) }
    }

    /// Returns the full match at index 0 followed by capture groups (empty string for non-participating groups).
    static func firstMatch(in text: String, pattern: String, caseInsensitive: Bool = false) -> [String]? {
        var options: NSRegularExpression.Options = [.dotMatchesLineSeparators]
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { i in
            guard let r = Range(match.range(at: i), in: text) else { return "" }
            return String(text[r])
        }
    }
}

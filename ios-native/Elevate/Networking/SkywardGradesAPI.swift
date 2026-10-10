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

        // Loader responses must contain a complete output envelope. Direct HTML is
        // still accepted for district variants that do not use httploader XML.
        let html = try extractGradeInfoHTML(from: raw)
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

    static func extractGradeInfoHTML(from raw: String) throws -> String {
        if raw.range(of: "<output", options: [.caseInsensitive]) != nil {
            guard let output = extractCDATA(raw, tag: "output") else {
                throw SkywardError.invalidResponse("incomplete grade-info output envelope")
            }
            return output
        }
        return raw
    }

    // MARK: - Parsing

    static func parseGradeInfoHTML(_ html: String, rawResponse: String) throws -> GradeInfoResult {
        try SkywardHTTP.checkSessionExpired(rawResponse)
        try SkywardHTTP.checkSessionExpired(html)

        // Empty <data> CDATA means the session died.
        if rawResponse.range(of: #"<data><!\[CDATA\[\s*\]\]></data>"#, options: .regularExpression) != nil {
            throw SkywardError.sessionExpired
        }

        let root = MiniHTML.parse(html)

        // Validate course and term identity before an empty parse can become
        // cacheable data. Skyward omits the assignment grid for ungraded terms;
        // that specific response shape is checked after the summary below.
        guard root.querySelector("h2.gb_heading") != nil else {
            throw SkywardError.invalidResponse("grade-info heading not found")
        }
        guard root.querySelector("table[id^='grid_stuTermSummaryGrid']") != nil
                || root.querySelector("div[id*='stuTermSummaryGrid']") != nil else {
            throw SkywardError.invalidResponse("grade-info term grid not found")
        }
        let hasAssignmentGrid = root.querySelector("table[id^='grid_stuAssignmentSummaryGrid']") != nil
            || root.querySelector("div[id*='stuAssignmentSummaryGrid']") != nil

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
        guard !course.isEmpty, !litName.isEmpty else {
            throw SkywardError.invalidResponse("grade-info identity fields are missing")
        }
        var litBegin: String? = nil
        var litEnd: String? = nil
        if let spanText = litHeader?.querySelector("span")?.text,
           let match = firstMatch(in: spanText, pattern: #"(\d{2}/\d{2}/\d{4})\s*-\s*(\d{2}/\d{2}/\d{4})"#) {
            litBegin = match[1]
            litEnd = match[2]
        }

        // Summary score.
        let summaryGrid = root.querySelector("table[id^='grid_stuTermSummaryGrid']")
            ?? root.querySelector("div[id*='stuTermSummaryGrid']")
        let summaryRows = summaryGrid.map { bodyRows(in: $0).filter { !$0.hasClass("sf_Section") } } ?? []
        let summaryRow = summaryRows.first { $0.attribute("class") != nil } ?? summaryRows.first
        let topScore = toDouble(summaryRow?.elements.last(where: { $0.tagName == "td" })?.text ?? "")
        let topGrade = topScore.map { Int($0.rounded()) }

        if !hasAssignmentGrid {
            guard isCompleteUngradedTerm(root, html: html, rawResponse: rawResponse) else {
                throw SkywardError.invalidResponse("grade-info assignment grid not found")
            }
        }

        let gradebook = try parseGradebook(root)

        return GradeInfoResult(
            course: course, instructor: instructor, period: period,
            litName: litName, litBegin: litBegin, litEnd: litEnd,
            gradebook: gradebook, score: topScore, grade: topGrade
        )
    }

    /// The verified ungraded-term loader response has one summary row with two
    /// blank cells and no assignment markup. Missing grids in scored, partial,
    /// or unknown responses must still fail instead of clearing cached grades.
    private static func isCompleteUngradedTerm(_ root: HTMLNode, html: String, rawResponse: String) -> Bool {
        guard extractCDATA(rawResponse, tag: "output") == html,
              let termGrid = root.querySelector("table[id^='grid_stuTermSummaryGrid']"),
              let termLabel = termGrid.querySelector("thead th")?.children.first(where: { $0.isText })?.text,
              !clean(termLabel).isEmpty,
              root.querySelector("#showAssignmentInfo") == nil,
              root.querySelector(".sf_Section.cat") == nil else { return false }
        // Walk direct children: descendant-selector ancestor matching can find
        // an outer layout tbody and accidentally count this table's header row.
        let bodies = termGrid.elements.filter { $0.tagName == "tbody" }
        guard bodies.count == 1 else { return false }
        let rows = bodies[0].elements
        guard rows.count == 1, rows[0].tagName == "tr" else { return false }
        let cells = rows[0].elements
        return cells.count == 2 && cells.allSatisfy { $0.tagName == "td" && clean($0.text).isEmpty }
    }

    /// Select rows owned by the grid table, not rows in its headers, layout
    /// ancestors, or nested tables inside assignment cells. Descendant CSS
    /// matching can otherwise use an ancestor outside a div-based grid.
    private static func bodyRows(in grid: HTMLNode) -> [HTMLNode] {
        let table = grid.tagName == "table" ? grid : grid.querySelector("table")
        if let table {
            return table.elements.flatMap { child -> [HTMLNode] in
                if child.tagName == "tbody" { return child.elements.filter { $0.tagName == "tr" } }
                return child.tagName == "tr" ? [child] : []
            }
        }
        // Some grid fragments have body rows without a wrapping table.
        return grid.elements.flatMap { child -> [HTMLNode] in
            if child.tagName == "tbody" { return child.elements.filter { $0.tagName == "tr" } }
            return child.tagName == "tr" ? [child] : []
        }
    }

    private static func parseGradebook(_ root: HTMLNode) throws -> [GradeCategory] {
        let grid = root.querySelector("table[id^='grid_stuAssignmentSummaryGrid']")
            ?? root.querySelector("div[id*='stuAssignmentSummaryGrid']")
        let rows = grid.map { bodyRows(in: $0) } ?? []

        var gradebook: [GradeCategory] = []
        var currentCategoryIndex: Int? = nil
        var lastMainCategoryIndex: Int? = nil
        var afterBoldCategory = false

        for row in rows {
            if row.hasClass("sf_Section") && row.hasClass("cat") {
                let cells = row.elements.filter { $0.tagName == "td" }
                guard cells.count > 1 else {
                    throw SkywardError.invalidResponse("grade category row is malformed")
                }
                let nameCell = cells[1]
                let firstTextChild = nameCell.children.first(where: { $0.isText })?.text
                let rawName = clean(firstTextChild ?? nameCell.text)
                guard !rawName.isEmpty else {
                    throw SkywardError.invalidResponse("grade category name is missing")
                }

                let styleAttr = nameCell.attribute("style") ?? ""
                let isBold = styleAttr.range(of: #"font-weight:\s*bold"#, options: [.regularExpression, .caseInsensitive]) != nil

                var weight: Double? = nil
                var adjustedWeight: Double? = nil
                for span in nameCell.querySelectorAll("span") {
                    if let m = firstMatch(in: clean(span.text),
                                          pattern: #"weighted at ([\d.]+)%(?:, adjusted to ([\d.]+)%)?"#,
                                          caseInsensitive: true) {
                        weight = toDouble(m[1])
                        adjustedWeight = m.count > 2 && !m[2].isEmpty ? toDouble(m[2]) : nil
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

            guard let link = row.querySelectorAll("a").first(where: { $0.id == "showAssignmentInfo" }) else {
                let rowText = clean(row.text).lowercased()
                let cells = row.elements
                // Skyward uses one spanning cell for an empty assignment grid.
                // Allow its assignment qualifier (for example, "daily"), but
                // never accept an empty-looking phrase inside a broken data row.
                let isEmptyMessage = firstMatch(in: rowText,
                    pattern: #"^(?:there (?:are|is) )?no (?:[a-z]+ ){0,2}assignments?(?:\s|[.!]|$)"#) != nil
                    || rowText == "no records"
                    || rowText == "nothing to display"
                let isFullWidthEmptyMessage = cells.count == 1 && cells[0].tagName == "td"
                    && (cells[0].attribute("colspan").flatMap(Int.init) ?? 0) >= 5
                    && row.querySelectorAll("a").isEmpty && isEmptyMessage
                guard rowText.isEmpty || isFullWidthEmptyMessage else {
                    throw SkywardError.invalidResponse("unrecognized gradebook row")
                }
                continue
            }
            guard let catIndex = currentCategoryIndex else {
                throw SkywardError.invalidResponse("assignment row has no category")
            }
            let cells = row.elements.filter { $0.tagName == "td" }
            guard cells.count >= 5 else {
                throw SkywardError.invalidResponse("assignment row is malformed")
            }
            func cell(_ i: Int) -> HTMLNode? { cells.indices.contains(i) ? cells[i] : nil }

            let date = clean(cell(0)?.text ?? "")
            let name = clean(link.text)
            guard !name.isEmpty else {
                throw SkywardError.invalidResponse("assignment name is missing")
            }
            let grade = toInt(cell(2)?.text ?? "")
            let score = toDouble(cell(3)?.text ?? "")
            let pointsText = clean(cell(4)?.text ?? "")

            var earned: Double? = nil
            var total: Double? = nil
            if let m = firstMatch(in: pointsText, pattern: #"^([+-]?\d+(?:\.\d+)?)\s*out of\s*([+-]?\d+(?:\.\d+)?)$"#, caseInsensitive: true) {
                earned = toDouble(m[1])
                total = toDouble(m[2])
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
        firstMatch(in: clean(text), pattern: #"^([+-]?\d+)(?:\s*%)?$"#).flatMap { Int($0[1]) }
    }

    static func toDouble(_ text: String) -> Double? {
        firstMatch(in: clean(text), pattern: #"^([+-]?\d+(?:\.\d+)?)(?:\s*%)?$"#)
            .flatMap { AcademicScoreValue.finiteDouble($0[1]) }
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

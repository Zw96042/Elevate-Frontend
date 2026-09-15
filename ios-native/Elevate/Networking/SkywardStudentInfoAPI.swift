import Foundation

/// Parses only the selected student's profile, never family/sidebar tables.
enum SkywardStudentInfoAPI {
    static let maximumHTMLBytes = 4_000_000
    static let maximumRows = 1_000

    struct ParsedPage {
        var data: StudentInfoData
        // Session-bearing source stays transient and is never cached in the model.
        var photoPath: String?
    }

    static func fetch(baseUrl: String, sessionCodes: SkywardSessionCodes) async throws -> StudentInfoData {
        guard let url = URL(string: baseUrl + "sfstudentinfo001.w") else {
            throw SkywardError.invalidResponse("invalid base URL")
        }
        let html = try await SkywardHTTP.post(url: url, fields: SkywardHTTP.sessionFields(sessionCodes))
        var page = try parsePage(html)
        if let path = page.photoPath {
            do {
                page.data.photoData = try await SkywardBinaryHTTP.loadPhoto(relativePath: path, baseUrl: baseUrl)
            } catch SkywardError.sessionExpired {
                throw SkywardError.sessionExpired
            } catch {
                page.data.photoLoadFailed = true
            }
        }
        return page.data
    }

    static func parse(_ html: String) throws -> StudentInfoData { try parsePage(html).data }

    static func parsePage(_ html: String) throws -> ParsedPage {
        guard html.utf8.count <= maximumHTMLBytes else { throw invalid("response exceeds size limit") }
        try SkywardHTTP.checkSessionExpired(html)
        let root = MiniHTML.parse(html)
        let scopes = root.querySelectorAll("table").filter { matches($0.id, #"^grid_student\d+$"#) }
        guard scopes.count == 1, let scope = scopes.first else { throw invalid("student scope missing or ambiguous") }
        try requireCompleteTable(html, tableID: scope.id)
        guard scope.querySelectorAll("tr").count <= maximumRows else { throw invalid("response exceeds row limit") }
        guard let wrap = scope.parent?.parent,
              scope.parent?.hasClass("sf_gridTableWrap") == true,
              let header = wrap.elements.first(where: { $0.hasClass("sfTag") }),
              let nameSpan = header.querySelector("span") else { throw invalid("student name missing") }
        let name = clean(nameSpan.text)
        guard !name.isEmpty, !["student info", "student information"].contains(name.lowercased()) else {
            throw invalid("student name missing")
        }
        let tables = scope.querySelectorAll("table")
        func single(_ pattern: String) throws -> HTMLNode? {
            let found = tables.filter { matches($0.id, pattern) }
            guard found.count <= 1 else { throw invalid("duplicate profile section") }
            return found.first
        }
        let contactTable = try single(#"^grid_studentContactInfo\d+$"#)
        let contactDetails = try single(#"^grid_stuGridInsideGrid\d+$"#)
        guard contactDetails == nil || contactDetails.map({ nearestTable($0) === contactTable }) == true else {
            throw invalid("contact section has invalid scope")
        }
        let contact = try contactDetails.map { try fields($0, allowed: ["School:", "Call:", "Address:"], cellCount: 2) } ?? []
        let student = try single(#"^grid_studentInfo\d+$"#).map {
            try fields($0, allowed: ["Gender:", "Age (Birthday):", "Language:", "Graduation Year:", "Other ID:", "Community Service:"], cellCount: 4)
        } ?? []
        let enrollmentTables = tables.filter { matches($0.id, #"^grid_studentEntity\d+_\d+$"#) }
        guard Set(enrollmentTables.map(\.id)).count == enrollmentTables.count else { throw invalid("duplicate enrollment") }
        let enrollments = try enrollmentTables.map { table in
            let rows = table.querySelectorAll("tr").filter { nearestTable($0) === table }
            guard let headerRow = rows.first, headerRow.elements.count == 1,
                  let header = headerRow.elements.first, header.tagName == "th",
                  header.attribute("colspan") == "4",
                  (header.attribute("rowspan") ?? "1") == "1",
                  header.querySelector("table") == nil, header.querySelector("script") == nil,
                  header.querySelector("style") == nil,
                  header.elements.allSatisfy({ ["br", "label", "span"].contains($0.tagName) }) else { throw invalid("enrollment header is unrecognized") }
            var values = try fields(table, allowed: ["Grade:", "Status:", "Discipline Officer:", "Counselor:"],
                                    cellCount: 4, skipping: headerRow)
            let school = clean(header.children.prefix { $0.tagName != "br" }.map(\.text).joined())
            let schoolName = school.isEmpty ? nil : school
            var pendingLabel: String?
            for child in header.children {
                let text = clean(child.text)
                if child.tagName == "label" {
                    guard ["Phone:", "Principal:"].contains(text), pendingLabel == nil else { throw invalid("enrollment header is incomplete") }
                    pendingLabel = text
                } else if child.tagName == "span" {
                    guard let label = pendingLabel else { throw invalid("enrollment header is unrecognized") }
                    guard !values.contains(where: { $0.label == label }) else { throw invalid("duplicate enrollment field") }
                    values.append(StudentInfoField(label: label, value: text))
                    pendingLabel = nil
                }
            }
            guard pendingLabel == nil else { throw invalid("enrollment header is incomplete") }
            return StudentEnrollment(id: table.id, schoolName: schoolName, fields: values)
        }
        // Contact tables also contain icons. Only the verified StuPic resource
        // identifies a student photo; repeated markup for one source is safe.
        let photoPaths = Set((contactTable?.querySelectorAll("img") ?? []).compactMap { image -> String? in
            guard let path = image.attribute("src"), let url = URL(string: path),
                  matches(url.lastPathComponent, #"^qdirconfig\d+\.p$"#),
                  URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "StuPic" }) == true else { return nil }
            return path
        })
        guard photoPaths.count <= 1 else { throw invalid("student photo ambiguous") }
        let photoPath = photoPaths.first
        return ParsedPage(data: StudentInfoData(name: name, contactFields: contact, studentFields: student,
                                               enrollments: enrollments), photoPath: photoPath?.isEmpty == false ? photoPath : nil)
    }

    private static func fields(_ table: HTMLNode, allowed: Set<String>, cellCount: Int, skipping headerRow: HTMLNode? = nil) throws -> [StudentInfoField] {
        let rows = table.querySelectorAll("tr").filter { nearestTable($0) === table }
        guard rows.contains(where: { $0 !== headerRow }) else { throw invalid("profile section is empty") }
        var result: [StudentInfoField] = []
        for row in rows where row !== headerRow {
            let cells = row.elements
            guard cells.count == cellCount, cells.allSatisfy({ $0.tagName == "td" && $0.querySelector("table") == nil
                && $0.querySelector("script") == nil && $0.querySelector("style") == nil }) else {
                throw invalid("profile row is unrecognized")
            }
            for index in stride(from: 0, to: cells.count, by: 2) {
                let label = clean(cells[index].text)
                let value = readable(cells[index + 1])
                if label.isEmpty && value.isEmpty { continue }
                guard allowed.contains(label), !result.contains(where: { $0.label == label }) else {
                    throw invalid("profile field is unrecognized")
                }
                result.append(StudentInfoField(label: label, value: value))
            }
        }
        return result
    }

    private static func readable(_ node: HTMLNode) -> String {
        if node.isText { return node.text }
        if node.tagName == "br" { return "\n" }
        let text = node.children.map(readable).joined()
        return node.tagName == "td" ? text.components(separatedBy: "\n").map(clean).filter { !$0.isEmpty }.joined(separator: "\n") : text
    }
    private static func clean(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    private static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    private static func invalid(_ detail: String) -> SkywardError { .invalidResponse("student information \(detail)") }
    private static func nearestTable(_ node: HTMLNode) -> HTMLNode? {
        var parent = node.parent
        while let current = parent {
            if current.tagName == "table" { return current }
            parent = current.parent
        }
        return nil
    }

    private static func requireCompleteTable(_ html: String, tableID: String) throws {
        let noise = #"<!--[\s\S]*?-->|<script\b[^>]*>[\s\S]*?</script\s*>|<style\b[^>]*>[\s\S]*?</style\s*>"#
        let source = html.replacingOccurrences(of: noise, with: "", options: [.regularExpression, .caseInsensitive])
        let regex = try NSRegularExpression(pattern: #"<\s*(/?)\s*([a-z][a-z0-9:-]*)\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>"#, options: .caseInsensitive)
        var stack: [String] = []
        var found = false
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range, in: source), let nameRange = Range(match.range(at: 2), in: source) else { continue }
            let name = source[nameRange].lowercased()
            let closing = match.range(at: 1).length > 0
            guard ["table", "thead", "tbody", "tfoot", "tr", "td", "th"].contains(name) else { continue }
            if !found {
                guard name == "table", !closing,
                      MiniHTML.parse(String(source[range]) + "</table>").querySelector("table")?.id == tableID else { continue }
                found = true
                stack.append(name)
                continue
            }
            if closing {
                if name == "table", stack.last == "tbody" { stack.removeLast() }
                guard stack.last == name else { throw invalid("table structure is incomplete") }
                stack.removeLast()
                if stack.isEmpty { return }
            } else {
                let parent = stack.last ?? ""
                let valid = name == "table" ? ["td", "th"].contains(parent)
                    : ["thead", "tbody", "tfoot"].contains(name) ? parent == "table"
                    : name == "tr" ? ["table", "thead", "tbody", "tfoot"].contains(parent)
                    : parent == "tr"
                guard valid, !source[range].hasSuffix("/>") else { throw invalid("table structure is incomplete") }
                stack.append(name)
            }
        }
        throw invalid("table is truncated")
    }
}

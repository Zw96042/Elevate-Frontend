import Foundation

/// Catalog identity for an incomplete gradebook title. Never executes the
/// popup's handler or changes the source name used by saved course identities.
enum SkywardCourseInfoAPI {
    static func needsCatalogCode(_ name: String) -> Bool {
        let value = name.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["INDEPENDENT STUDY IN ENGLISH (", "ENGLISH INDEPENDENT STUDY ("].contains(value)
    }

    static func fetchCatalogCode(
        course: GradebookCourse, gradebookHTML: String,
        baseURL: String, sessionCodes: SkywardSessionCodes
    ) async throws -> String {
        let parameters = try requestFields(html: gradebookHTML, course: course)
        guard let url = URL(string: baseURL + "httploader.p?file=sfdialogs.w") else {
            throw SkywardError.invalidResponse("invalid course-information URL")
        }
        let raw = try await SkywardHTTP.post(url: url, fields: parameters
            + SkywardHTTP.sessionFields(sessionCodes) + [("fromHttp", "yes"), ("ishttp", "true")])
        let html = try SkywardGradesAPI.extractGradeInfoHTML(from: raw)
        return try parseCatalogCode(html)
    }

    static func requestFields(html: String, course: GradebookCourse) throws -> [(String, String)] {
        try SkywardHTTP.checkSessionExpired(html)
        guard html.utf8.count <= 2_000_000,
              let student = course.stuId, let number = course.corNumId,
              let section = course.section else { throw invalid() }
        let root = MiniHTML.parse(html)
        let tableID = "classDesc_\(student)_\(number)_0_\(section)"
        let links = root.querySelectorAll("table[id*=classDesc_]" )
            .filter { $0.id == tableID }.flatMap { $0.querySelectorAll("span.bld.classDesc a") }
        guard links.count == 1, let name = links[0].attribute("name"),
              name.range(of: #"^[A-Za-z_]{1,64}$"#, options: .regularExpression) != nil else { throw invalid() }

        // Skyward binds this link using its CSS ID selector. Accept the
        // plain-name form too, while retaining exact quoted identity matching.
        let bindingName = #"['"]#?"# + NSRegularExpression.escapedPattern(for: name) + #"['"]"#
        var requests: [[String: String]] = []
        for script in root.querySelectorAll("script") {
            let code = script.children.map(\.textContentRaw).joined()
            for line in code.components(separatedBy: "\n") where line.contains("sfdialogs.w")
                && line.range(of: bindingName, options: .regularExpression) != nil {
                guard line.utf8.count <= 8192,
                      let captured = SkywardGradesAPI.firstMatch(in: line,
                        pattern: #"sfdialogs\.w['"]\s*,\s*(\{[^\n]*?\})\s*,\s*function"#)?.last else { throw invalid() }
                // Only section is a known DOM lookup in this handler. Supply
                // the section already validated by the enclosing course table;
                // every other expression must pass the bounded literal parser.
                let sectionPattern = #"(['"]section['"]\s*:\s*)[A-Za-z_$][A-Za-z_0-9$]*\.[A-Za-z_$][A-Za-z_0-9$]*\(\s*['"][A-Za-z_0-9-]+['"]\s*\)"#
                let regex = try NSRegularExpression(pattern: sectionPattern)
                let encodedSection = String(decoding: try JSONEncoder().encode(section), as: UTF8.self)
                let literal = regex.stringByReplacingMatches(in: captured,
                    range: NSRange(captured.startIndex..<captured.endIndex, in: captured),
                    withTemplate: "$1" + NSRegularExpression.escapedTemplate(for: encodedSection))
                guard let object = try JavaScriptLiteralParser.parse(literal) as? [String: Any] else { throw invalid() }
                let allowed: Set<String> = ["action", "type", "student", "eid", "cornumid", "track", "section", "id", "dialogOptions"]
                var fields: [String: String] = [:]
                for (key, value) in object {
                    guard allowed.contains(key), let text = value as? String, text.utf8.count <= 128 else { throw invalid() }
                    fields[key] = text
                }
                guard fields["action"] == "dialog", fields["type"] == "class",
                      fields["student"] == student, fields["cornumid"] == String(number),
                      fields["section"] == section, fields["eid"] != nil, fields["track"] != nil else { throw invalid() }
                requests.append(fields)
            }
        }
        guard let request = requests.first, requests.allSatisfy({ $0 == request }) else { throw invalid() }
        return request.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) }
    }

    static func parseCatalogCode(_ html: String) throws -> String {
        try SkywardHTTP.checkSessionExpired(html)
        guard html.utf8.count <= 256_000 else { throw invalid() }
        let root = MiniHTML.parse(html)
        let codes = Set(root.querySelectorAll("td").filter { $0.querySelector("table") == nil }.compactMap { cell in
            SkywardGradesAPI.firstMatch(in: cell.text.trimmingCharacters(in: .whitespacesAndNewlines),
                pattern: #"^([A-Z]{2,5}\d{2,5})(?:\s*[-/]\s*\d+)?$"#)?[1]
        })
        guard codes.count == 1, let code = codes.first else { throw invalid() }
        return code
    }

    private static func invalid() -> SkywardError {
        .invalidResponse("course information catalog identity is missing or ambiguous")
    }
}

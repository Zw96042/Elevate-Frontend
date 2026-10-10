import CryptoKit
import Foundation

/// Portfolio metadata is cached; authenticated download locations are resolved
/// again when opened and are never saved or evaluated as JavaScript.
enum SkywardDocumentsAPI {
    enum DownloadAction {
        case blob(String)
        case report(description: String, program: String, parameters: String)
    }
    struct ParsedPage {
        var data: DocumentsData
        var locations: [String: String]
        var actions: [String: DownloadAction]
    }
    private static let quoted = #"(?:'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")"#

    static func fetch(baseUrl: String, sessionCodes: SkywardSessionCodes) async throws -> DocumentsData {
        try parsePage(await page(baseUrl: baseUrl, sessionCodes: sessionCodes), baseUrl: baseUrl).data
    }

    private static func page(baseUrl: String, sessionCodes: SkywardSessionCodes) async throws -> String {
        guard let url = URL(string: baseUrl + "sfportfolio.w") else { throw invalid("invalid base URL") }
        return try await SkywardHTTP.post(url: url, fields: SkywardHTTP.sessionFields(sessionCodes))
    }

    static func parse(_ html: String) throws -> DocumentsData { try parsePage(html).data }

    static func parsePage(_ html: String, baseUrl: String? = nil) throws -> ParsedPage {
        try SkywardHTTP.checkSessionExpired(html)
        guard html.utf8.count <= 4_000_000 else { throw invalid("response exceeds size limit") }
        let root = MiniHTML.parse(html)
        let tables = root.querySelectorAll("table").filter { $0.id.range(of: #"^grid_attachments\d+\*\d+$"#, options: .regularExpression) != nil }
        guard tables.count == 1, let table = tables.first else { throw invalid("table is missing or ambiguous") }
        try requireCompleteTable(html, id: table.id)
        guard table.elements.contains(where: { $0.tagName == "tbody" }),
              table.elements.allSatisfy({ ["thead", "tbody", "tfoot", "colgroup"].contains($0.tagName) }),
              table.children.filter(\.isText).allSatisfy({ clean($0.text).isEmpty }) else { throw invalid("table body is unrecognized") }
        for section in table.elements where ["thead", "tbody", "tfoot"].contains(section.tagName) {
            guard section.elements.allSatisfy({ $0.tagName == "tr" }),
                  section.children.filter(\.isText).allSatisfy({ clean($0.text).isEmpty }) else { throw invalid("table section is unrecognized") }
        }
        let rows = table.querySelectorAll("tr").filter { nearestTable($0) === table }
        guard rows.count <= 10_001, let header = rows.first,
              header.elements.count == 3, header.elements.allSatisfy({ $0.tagName == "th" && $0.querySelector("table") == nil }),
              header.elements.map({ clean($0.text).lowercased() }) == ["description", "type", "created"] else { throw invalid("columns are unrecognized") }
        guard rows.filter({ $0.elements.contains(where: { $0.tagName == "th" }) }).count == 1 else { throw invalid("header is ambiguous") }
        let handlers = try downloadHandlers(root)
        var records: [SkywardDocument] = []
        var locations: [String: String] = [:]
        var actions: [String: DownloadAction] = [:]
        var occurrences: [String: Int] = [:]
        var emptyMarker = false
        var anchorIDs: Set<String> = []
        for row in rows.dropFirst() {
            let cells = row.elements
            guard row.children.filter(\.isText).allSatisfy({ clean($0.text).isEmpty }),
                  cells.allSatisfy({ $0.tagName == "td" && $0.querySelector("table") == nil && $0.querySelector("script") == nil && $0.querySelector("style") == nil }) else { throw invalid("row is unrecognized") }
            if cells.count == 1, cells[0].attribute("colspan") == "3", cells[0].querySelector("a") == nil,
               ["no records to display", "no records found", "no attachments", "no documents"].contains(clean(cells[0].text).lowercased()) {
                guard !emptyMarker else { throw invalid("empty marker is repeated") }
                emptyMarker = true
                continue
            }
            guard cells.count == 3, cells.allSatisfy({ ($0.attribute("colspan") ?? "1") == "1" && ($0.attribute("rowspan") ?? "1") == "1" }),
                  cells[0].querySelectorAll("a").count == 1, let anchor = cells[0].querySelector("a"), !anchor.id.isEmpty,
                  !clean(anchor.text).isEmpty else { throw invalid("row is incomplete") }
            guard anchorIDs.insert(anchor.id).inserted else { throw invalid("document anchor scope is ambiguous") }
            let title = clean(anchor.text), kind = clean(cells[1].text), created = clean(cells[2].text)
            let identity = [title, kind, created].map { "\($0.utf8.count):\($0)" }.joined()
            let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            let occurrence = occurrences[digest, default: 0]
            occurrences[digest] = occurrence + 1
            let id = "document:\(digest):\(occurrence)"
            var action = handlers[anchor.id]
            if case let .blob(candidate) = action {
                if !isBlobLocation(candidate) || (baseUrl != nil && (try? SkywardBinaryHTTP.resourceURL(relativePath: candidate, baseUrl: baseUrl!)) == nil) {
                    action = nil
                } else { locations[id] = candidate }
            }
            records.append(SkywardDocument(id: id, title: title, kind: kind.isEmpty ? nil : kind,
                                           created: created.isEmpty ? nil : created, canOpen: action != nil))
            if let action { actions[id] = action }

        }
        guard !emptyMarker || records.isEmpty else { throw invalid("records conflict with empty marker") }
        return ParsedPage(data: DocumentsData(documents: records), locations: locations, actions: actions)
    }

    static func open(documentID: String, baseUrl: String, sessionCodes: SkywardSessionCodes) async throws -> SkywardBinaryHTTP.Resource {
        let parsed = try parsePage(await page(baseUrl: baseUrl, sessionCodes: sessionCodes), baseUrl: baseUrl)
        guard let action = parsed.actions[documentID] else { throw invalid("document is no longer available for preview") }
        let url: URL
        switch action {
        case let .blob(path): url = try SkywardBinaryHTTP.resourceURL(relativePath: path, baseUrl: baseUrl)
        case let .report(description, program, parameters):
            url = try await SkywardReportQueueAPI.generate(baseUrl: baseUrl, sessionCodes: sessionCodes,
                description: description, program: program, parameters: parameters)
        }
        return try await SkywardBinaryHTTP.fetch(url: url, maximumBytes: 20_000_000,
            allowedMIMETypes: ["application/pdf", "application/octet-stream", "image/jpeg", "image/png", "image/gif"])
    }

    /// Both verified download forms require no signature. Server-supplied queue
    /// arguments remain transient and are sent only after a document is opened.
    private static func downloadHandlers(_ root: HTMLNode) throws -> [String: DownloadAction] {
        let scalar = "(?:" + quoted + "|true|false|[0-9]+)"
        let arguments = "((?:false|true)\\s*,\\s*(?:false|true)\\s*,\\s*" + quoted + "(?:\\s*,\\s*" + quoted + "){2,4})"
        let pattern = "sff\\.aee\\(\\s*" + scalar + "\\s*,\\s*" + scalar + "\\s*,\\s*function\\s*\\([^)]*\\)\\s*\\{\\s*sfportfolio\\.eSignCheck\\(" + arguments + "\\)\\s*;?\\s*\\}\\s*,\\s*(" + quoted + ")\\s*\\)\\s*;"
        let regex = try NSRegularExpression(pattern: pattern)
        var handlers: [String: DownloadAction] = [:]
        var registered: Set<String> = []
        for script in root.querySelectorAll("script") where script.attribute("src") == nil {
            let text = script.text
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            guard matches.count <= 10_000 else { throw invalid("handler limit exceeded") }
            for match in matches {
                guard let argRange = Range(match.range(at: 1), in: text), let idRange = Range(match.range(at: 2), in: text),
                      let values = try? JavaScriptLiteralParser.parse("[" + text[argRange] + "]") as? [Any],
                      let selector = try? JavaScriptLiteralParser.parse(String(text[idRange])) as? String else { throw invalid("handler data is malformed") }
                // aee's final argument is a delegated CSS selector, not an ID.
                guard selector.range(of: #"^#[A-Za-z_][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else { continue }
                let anchorID = String(selector.dropFirst())
                guard registered.insert(anchorID).inserted else { throw invalid("handler scope is ambiguous") }
                guard (values[0] as? Bool) == false, (values[1] as? Bool) == false,
                      let type = values[3] as? String, let location = values[4] as? String else { continue }
                if values.count == 5, type == "blobLink" {
                    handlers[anchorID] = .blob(location)
                } else if values.count == 7, type == "addToQueue",
                          let program = values[5] as? String, let parameters = values[6] as? String,
                          !location.isEmpty, location.utf8.count <= 16_000,
                          program.utf8.count <= 4_000,
                          program.range(of: #"^[A-Za-z0-9_./-]+$"#, options: .regularExpression) != nil,
                          !program.contains(".."), !parameters.isEmpty, parameters.utf8.count <= 512_000 {
                    handlers[anchorID] = .report(description: location, program: program, parameters: parameters)
                }

            }
        }
        return handlers
    }

    private static func isBlobLocation(_ path: String) -> Bool {
        guard let url = URL(string: path), url.lastPathComponent.range(of: #"^qdirconfig\d+\.p$"#, options: .regularExpression) != nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.contains(where: { $0.name == "blobid" && !($0.value ?? "").isEmpty }),
              !items.contains(where: { $0.name == "StuPic" }) else { return false }
        return true
    }

    private static func nearestTable(_ node: HTMLNode) -> HTMLNode? {
        var parent = node.parent
        while let value = parent { if value.tagName == "table" { return value }; parent = value.parent }
        return nil
    }

    /// MiniHTML tolerates incomplete HTML; source validation prevents caching a
    /// malformed response as a valid partial or empty document list.
    private static func requireCompleteTable(_ html: String, id: String) throws {
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
                      MiniHTML.parse(String(source[range]) + "</table>").querySelector("table")?.id == id else { continue }
                guard !source[range].hasSuffix("/>") else { throw invalid("table is incomplete") }
                found = true
                stack.append(name)
                continue
            }
            if closing {
                // Skyward legally omits </tbody> immediately before </table>.
                // All row/cell closures must still be explicit and in order.
                if name == "table", stack.last == "tbody" { stack.removeLast() }
                guard stack.last == name else { throw invalid("table structure is incomplete") }
                stack.removeLast()
                if stack.isEmpty { return }
            } else {
                let parent = stack.last ?? ""
                let valid = ["thead", "tbody", "tfoot"].contains(name) ? parent == "table"
                    : name == "tr" ? ["thead", "tbody", "tfoot"].contains(parent)
                    : ["td", "th"].contains(name) ? parent == "tr" : false
                guard valid, !source[range].hasSuffix("/>") else { throw invalid("table structure is incomplete") }
                stack.append(name)
            }
        }
        throw invalid("table is truncated")
    }

    private static func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func invalid(_ reason: String) -> SkywardError { .invalidResponse("documents " + reason) }
}

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


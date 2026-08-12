import Foundation

/// Inbox messages: scraped from sfhome01.w, paginated via "moreMessages".
enum SkywardMessagesAPI {
    static func fetchMessages(sessionCodes: SkywardSessionCodes, baseUrl: String) async throws -> [SkywardMessage] {
        guard let initialUrl = URL(string: baseUrl + "sfhome01.w") else {
            throw SkywardError.invalidResponse("invalid base URL")
        }
        let initial = try await SkywardHTTP.post(url: initialUrl, fields: SkywardHTTP.sessionFields(sessionCodes))
        try SkywardHTTP.checkSessionExpired(initial)
        return parseMessages(initial)
    }

    static func fetchMoreMessages(sessionCodes: SkywardSessionCodes, baseUrl: String,
                                  lastMessageId: String, limit: Int = 10) async throws -> [SkywardMessage] {
        var allHTML: [String] = []
        var currentLastId: String? = lastMessageId
        var totalLoaded = 0

        while let lastId = currentLastId, totalLoaded < limit {
            let batch = try await fetchBatch(sessionCodes: sessionCodes, baseUrl: baseUrl, lastMessageRowId: lastId)
            if batch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
            try SkywardHTTP.checkSessionExpired(batch)
            let fragment = SkywardGradesAPI.extractCDATA(batch, tag: "output") ?? batch
            allHTML.append(fragment)
            let newLastId = extractLastMessageId(batch)
            if newLastId == nil || newLastId == lastId { break }
            currentLastId = newLastId
            totalLoaded += parseMessages(fragment).count
        }

        return parseMessages(allHTML.joined())
    }

    private static func fetchBatch(sessionCodes: SkywardSessionCodes, baseUrl: String, lastMessageRowId: String) async throws -> String {
        guard let url = URL(string: baseUrl + "httploader.p?file=sfhome01.w") else {
            throw SkywardError.invalidResponse("invalid base URL")
        }
        let fields: [(String, String)] = [
            ("action", "moreMessages"),
            ("lastMessageRowId", lastMessageRowId),
            ("ishttp", "true"),
            ("sessionid", sessionCodes.sessionid),
            ("encses", sessionCodes.encses),
            ("dwd", sessionCodes.dwd),
            ("wfaacl", sessionCodes.wfaacl),
            ("javascript.filesAdded", "jquery.1.8.2.js,qsfmain001.css,sfhome001.css,qsfmain001.min.js,sfhome001.js"),
            ("requestId", String(Int(Date().timeIntervalSince1970 * 1000))),
        ]
        return try await SkywardHTTP.post(url: url, fields: fields, extraHeaders: [
            "X-Requested-With": "XMLHttpRequest",
        ])
    }

    // MARK: - Parsing

    static func extractLastMessageId(_ raw: String) -> String? {
        let fragment = SkywardGradesAPI.extractCDATA(raw, tag: "output") ?? raw
        let root = MiniHTML.parse(fragment)
        let items = root.querySelectorAll("li.feedItem.allowRemove")
        guard let last = items.last, let wrap = last.querySelector(".messageWrap") else { return nil }
        return wrap.attribute("data-wall-id")
    }

    static func parseMessages(_ html: String) -> [SkywardMessage] {
        let root = MiniHTML.parse(html)

        // Message bodies arrive inside JS: $('<var>…</var>').appendTo('#messageText_…');
        var contentMap: [String: [(content: String, index: Int)]] = [:]
        let pattern = #"\$\('<var>(?:<div class=\\?'msgDetail\\?'[^>]*>)?([\s\S]*?)(?:</div></div>)?</var>'\)\.appendTo\('#(messageText_[^']+)'\);"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsRange = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: nsRange) {
                guard let bodyRange = Range(match.range(at: 1), in: html),
                      let idRange = Range(match.range(at: 2), in: html) else { continue }
                let body = String(html[bodyRange])
                let spanId = String(html[idRange])
                let rendered = renderMessageBody(body)
                contentMap[spanId, default: []].append((rendered, match.range.location))
            }
        }

        var messages: [SkywardMessage] = []
        for li in root.querySelectorAll("li.feedItem.allowRemove") {
            guard let wrap = li.querySelector(".messageWrap") else { continue }
            let rawClassAttr = wrap.attribute("class") ?? ""

            var className = "Administrator"
            if let classLink = wrap.querySelector(".messageHead > .text > a[data-type=\"class\"]") {
                if let m = SkywardGradesAPI.firstMatch(in: classLink.text, pattern: #"\(([^/]+)/"#) {
                    className = m[1].trimmingCharacters(in: .whitespaces)
                }
            } else if rawClassAttr.contains("message_general") {
                className = "Administrator"
            }

            let fromLink = wrap.querySelector(".messageHead > .text > a[data-type=\"teacher\"]")
            let from = fromLink?.text.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (className == "Administrator" ? "Administrator" : "")

            let date = wrap.querySelector(".messageBody > .date")?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            var subject = wrap.querySelector(".messageBody > .text > .Subject")?.text
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if subject.isEmpty {
                if className == "Administrator" {
                    subject = "Administrator Message"
                } else if let fallback = wrap.querySelector(".messageBody > .text > .NoHeader") {
                    subject = fallback.text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            var content = ""
            if let span = wrap.querySelector(".messageBody > .text > span[id^=\"messageText_\"]"),
               let pieces = contentMap[span.id] {
                content = pieces.sorted { $0.index < $1.index }.map(\.content).joined(separator: "\n\n")
            }

            let messageRowId = wrap.attribute("data-wall-id") ?? ""
            messages.append(SkywardMessage(
                className: className, content: content, date: date,
                from: from, messageRowId: messageRowId, subject: subject
            ))
        }
        return messages
    }

    /// Renders a message-body HTML fragment to lightweight markdown
    /// (links as [text](url), bold as **text**, bullets, line breaks).
    static func renderMessageBody(_ fragment: String) -> String {
        let root = MiniHTML.parse("<div class='msgDetail'>\(fragment)</div>")
        var out = ""
        render(node: root, into: &out)
        let collapsed = out
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func render(node: HTMLNode, into out: inout String) {
        if node.isText {
            out += HTMLEntities.decode(node.textContentRaw)
            return
        }
        switch node.tagName {
        case "a":
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let href = node.attribute("href"), !href.isEmpty {
                out += "[\(text)](\(href))"
            } else {
                out += text
            }
        case "b", "strong":
            out += "**"
            for child in node.children { render(node: child, into: &out) }
            out += "**"
        case "li":
            out += "\t• "
            for child in node.children { render(node: child, into: &out) }
            out += "\n"
        case "br":
            out += "\n"
        case "div", "p":
            let inner = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.isEmpty || inner == "\u{00a0}" {
                out += "\n"
            } else {
                for child in node.children { render(node: child, into: &out) }
                out += "\n"
            }
        case "script", "style":
            break
        default:
            for child in node.children { render(node: child, into: &out) }
        }
    }
}

import Foundation

/// Inbox messages: scraped from sfhome01.w, paginated via "moreMessages".
enum SkywardMessagesAPI {
    static func fetchMessages(sessionCodes: SkywardSessionCodes, baseUrl: String) async throws -> [SkywardMessage] {
        guard let initialUrl = URL(string: baseUrl + "sfhome01.w") else {
            throw SkywardError.invalidResponse("invalid base URL")
        }
        let initial = try await SkywardHTTP.post(url: initialUrl, fields: SkywardHTTP.sessionFields(sessionCodes))
        try SkywardHTTP.checkSessionExpired(initial)
        return try parseMessages(initial, context: .initialPage)
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
            let fragment = try extractMessageFragment(from: batch)
            let parsedBatch = try parseMessages(fragment, context: .paginationFragment)
            allHTML.append(fragment)
            let newLastId = extractLastMessageId(batch)
            if newLastId == nil || newLastId == lastId { break }
            currentLastId = newLastId
            totalLoaded += parsedBatch.count
        }

        guard !allHTML.isEmpty else { return [] }
        return try parseMessages(allHTML.joined(), context: .paginationFragment)
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

    static func extractMessageFragment(from raw: String) throws -> String {
        if raw.range(of: "<output", options: [.caseInsensitive]) != nil {
            guard let output = SkywardGradesAPI.extractCDATA(raw, tag: "output") else {
                throw SkywardError.invalidResponse("incomplete message output envelope")
            }
            return output
        }
        return raw
    }

    enum ParseContext {
        case initialPage
        case paginationFragment
    }

    static func parseMessages(
        _ html: String,
        context: ParseContext = .initialPage
    ) throws -> [SkywardMessage] {
        try SkywardHTTP.checkSessionExpired(html)
        let root = MiniHTML.parse(html)
        let messageItems = root.querySelectorAll("li.feedItem.allowRemove")

        if messageItems.isEmpty {
            switch context {
            case .initialPage:
                let hasFeedAnchor = root.querySelector("#messageFeed") != nil
                    || root.querySelector("#messageWall") != nil
                    || root.querySelector("#messageCenter") != nil
                    || root.querySelector(".messageFeed") != nil
                    || root.querySelector(".messageList") != nil
                guard hasFeedAnchor else {
                    throw SkywardError.invalidResponse("message feed not found")
                }
            case .paginationFragment:
                guard html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SkywardError.invalidResponse("message fragment has no feed items")
                }
            }
            return []
        }

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
        for li in messageItems {
            guard let wrap = li.querySelector(".messageWrap"),
                  let messageRowId = wrap.attribute("data-wall-id"),
                  !messageRowId.isEmpty else {
                throw SkywardError.invalidResponse("message item is missing its identity")
            }
            guard wrap.querySelector(".messageHead") != nil,
                  let messageBody = wrap.querySelector(".messageBody"),
                  messageBody.querySelector(".text") != nil else {
                throw SkywardError.invalidResponse("message item is structurally incomplete")
            }
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

            messages.append(SkywardMessage(
                className: className, content: content, date: date,
                from: from, messageRowId: messageRowId, subject: subject
            ))
        }
        guard messages.count == messageItems.count else {
            throw SkywardError.invalidResponse("message feed could not be parsed completely")
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
            out += markdownEscapedText(HTMLEntities.decode(node.textContentRaw))
            return
        }
        switch node.tagName {
        case "a":
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let href = node.attribute("href"), let url = safeMessageURL(href) {
                out += "[\(markdownEscapedLabel(text))](\(url.absoluteString))"
            } else {
                out += markdownEscapedText(text)
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

    static func safeMessageURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false else { return nil }
        components.scheme = "https"
        return components.url
    }

    private static func markdownEscapedLabel(_ value: String) -> String {
        markdownEscapedText(value)
    }

    private static func markdownEscapedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

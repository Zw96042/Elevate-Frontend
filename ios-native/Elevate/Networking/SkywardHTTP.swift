import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import OSLog

/// Form-encoded POST helper shared by all Skyward endpoints.
enum SkywardHTTP {
    private static let logger = Logger(subsystem: "com.zacharywilson.elevate", category: "SkywardHTTP")

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
        ]
        return URLSession(configuration: config)
    }()

    /// Milliseconds to wait before retrying a transient connection failure,
    /// or nil to give up: two retries. Failures before a connection exists
    /// never reached Skyward, so any request retries them. A lost connection
    /// may have delivered the request, so only a repeatable one (anything
    /// but sign-in or queuing a report) retries it. Timeouts and being
    /// offline are not retried.
    static func retryDelay(for code: URLError.Code, attempt: Int, repeatable: Bool) -> Int? {
        let beforeConnecting: Set<URLError.Code> = [
            .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost, .secureConnectionFailed,
        ]
        let retries = beforeConnecting.contains(code) || (repeatable && code == .networkConnectionLost)
        guard retries, attempt < 2 else { return nil }
        return attempt == 0 ? 350 : 1_200
    }

    /// What to tell the person when a request fails before Skyward answers.
    /// iOS's own wording ("The network connection was lost.") blames their
    /// connection even when Skyward itself is closing every connection, as
    /// it does during maintenance, so say which side is the likely problem.
    static func connectionMessage(for code: URLError.Code) -> String? {
        switch code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return "You're offline. Check your connection and try again."
        case .networkConnectionLost, .cannotConnectToHost, .secureConnectionFailed,
             .badServerResponse, .zeroByteResource:
            return "Skyward isn't responding right now. It may be down for maintenance; try again in a little while."
        case .timedOut:
            return "Skyward is taking too long to respond. Try again in a little while."
        case .dnsLookupFailed, .cannotFindHost:
            return "Couldn't reach Skyward. Check your connection and try again."
        default:
            return nil
        }
    }

    /// Requests that change something on Skyward, so a retry could repeat
    /// it: signing in (attempts count toward a lockout) and queuing a report.
    static func isRepeatable(_ fields: [(String, String)]) -> Bool {
        !fields.contains { key, value in
            key.lowercased() == "password" || (key == "action" && value == "addToPrintQueue")
        }
    }

    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func clearCookies() {
        guard let storage = session.configuration.httpCookieStorage else { return }
        for cookie in storage.cookies ?? [] {
            storage.deleteCookie(cookie)
        }
    }

    static func formEncode(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        let body = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    static func post(url: URL, fields: [(String, String)], extraHeaders: [String: String] = [:]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = formEncode(fields)

        let sensitiveFieldNames: Set<String> = ["password", "dwd", "wfaacl", "encses", "sessionid"]
        let lowercasedFieldNames = Set(fields.map { $0.0.lowercased() })
        let isAuthenticationRequest = lowercasedFieldNames.contains("password")
        let validatesSession = !isAuthenticationRequest
            && !lowercasedFieldNames.isDisjoint(with: ["dwd", "wfaacl", "encses", "sessionid"])
        return try await perform(
            request,
            fieldNames: fields.map(\.0),
            redacting: fields.map(\.1),
            suppressResponsePreview: fields.contains { sensitiveFieldNames.contains($0.0.lowercased()) },
            validatesSession: validatesSession,
            isAuthenticationRequest: isAuthenticationRequest,
            repeatable: isRepeatable(fields)
        )
    }

    static func get(url: URL, extraHeaders: [String: String] = [:]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await perform(
            request,
            fieldNames: [],
            redacting: [],
            suppressResponsePreview: false,
            validatesSession: false,
            isAuthenticationRequest: false,
            repeatable: true
        )
    }

    private static func perform(
        _ request: URLRequest,
        fieldNames: [String],
        redacting sensitiveValues: [String],
        suppressResponsePreview: Bool,
        validatesSession: Bool,
        isAuthenticationRequest: Bool,
        repeatable: Bool
    ) async throws -> String {
        guard let url = request.url else {
            throw SkywardError.invalidResponse("invalid request URL")
        }
        let method = request.httpMethod ?? "REQUEST"

        #if DEBUG
        let startedAt = Date()
        let fieldNameList = fieldNames.joined(separator: ",")
        logger.debug("\(method, privacy: .public) started host=\(url.host ?? "unknown", privacy: .public) path=\(url.path, privacy: .public) fields=\(fieldNameList, privacy: .public)")
        #endif

        let (data, response): (Data, URLResponse)
        var attempt = 0
        while true {
            do {
                (data, response) = try await session.data(for: request)
                break
            } catch {
                #if DEBUG
                logger.error("\(method, privacy: .public) failed host=\(url.host ?? "unknown", privacy: .public) path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) attempt=\(attempt)")
                #endif
                // A cancelled request is a cancellation, never a network failure.
                if error is CancellationError || Task.isCancelled {
                    throw CancellationError()
                }
                // Cellular networks often hand back a connection Skyward already
                // closed; iOS reports it as lost or unstable, and trying again
                // usually works (see retryDelay for which requests may).
                if let urlError = error as? URLError,
                   let delay = retryDelay(for: urlError.code, attempt: attempt, repeatable: repeatable) {
                    attempt += 1
                    try await Task.sleep(for: .milliseconds(delay))
                    continue
                }
                let code = (error as? URLError)?.code
                throw SkywardError.network(code.flatMap(connectionMessage) ?? error.localizedDescription)
            }
        }

        #if DEBUG
        logResponse(
            data: data,
            response: response,
            originalURL: url,
            method: method,
            elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000),
            redacting: sensitiveValues,
            suppressResponsePreview: suppressResponsePreview
        )
        #endif

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw isAuthenticationRequest ? SkywardError.invalidCredentials : SkywardError.sessionExpired
            }
            if http.statusCode >= 500 {
                throw SkywardError.network("Skyward isn't responding right now (server error \(http.statusCode)). Try again in a little while.")
            }
            if http.statusCode >= 400 {
                throw SkywardError.network("Skyward request failed (\(http.statusCode))")
            }
        }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw SkywardError.invalidResponse("non-text body")
        }
        if validatesSession {
            try checkSessionExpired(text)
            try checkSessionRedirect(response.url)
        }
        return text
    }

    #if DEBUG
    private static func logResponse(
        data: Data,
        response: URLResponse,
        originalURL: URL,
        method: String,
        elapsedMilliseconds: Int,
        redacting sensitiveValues: [String],
        suppressResponsePreview: Bool
    ) {
        let http = response as? HTTPURLResponse
        let finalURL = response.url
        let wasRedirected = finalURL != nil && finalURL != originalURL
        let statusCode = http?.statusCode ?? -1
        let mimeType = response.mimeType ?? "unknown"
        let finalHost = finalURL?.host ?? "unknown"
        let finalPath = finalURL?.path ?? "unknown"
        let headerNames = http?.allHeaderFields.keys
            .map { String(describing: $0).lowercased() }
            .sorted()
            .joined(separator: ",") ?? ""

        logger.debug(
            "\(method, privacy: .public) completed status=\(statusCode, privacy: .public) bytes=\(data.count, privacy: .public) mime=\(mimeType, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public) redirected=\(wasRedirected, privacy: .public) finalHost=\(finalHost, privacy: .public) finalPath=\(finalPath, privacy: .public) headers=\(headerNames, privacy: .public)"
        )

        guard data.count <= 256,
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return }

        let preview = suppressResponsePreview && !text.isEmpty
            ? "<suppressed for sensitive request>"
            : diagnosticPreview(text, redacting: sensitiveValues)
        logger.debug("Short response preview=\(preview, privacy: .public)")
    }

    static func diagnosticPreview(_ text: String, redacting sensitiveValues: [String] = []) -> String {
        var preview = text
        for value in sensitiveValues where !value.isEmpty {
            preview = preview.replacingOccurrences(of: value, with: "<redacted>")
        }
        preview = preview
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        if preview.isEmpty { return "<empty>" }
        return String(preview.prefix(256))
    }
    #endif

    /// Session-code fields shared by most authenticated requests.
    static func sessionFields(_ codes: SkywardSessionCodes) -> [(String, String)] {
        [
            ("dwd", codes.dwd),
            ("wfaacl", codes.wfaacl),
            ("encses", codes.encses),
            ("User-Type", codes.userType),
            ("sessionid", codes.sessionid),
        ]
    }

    static func checkSessionRedirect(_ url: URL?) throws {
        guard let path = url?.path.lowercased() else { return }
        if path.contains("fwemnu01.w") || path.contains("skyportlogin") {
            throw SkywardError.sessionExpired
        }
    }

    static func checkSessionExpired(_ html: String) throws {
        if let status = try SkywardLoaderMetadata.status(in: html) {
            if status == "logout" { throw SkywardError.sessionExpired }
            if status != "success", status != "valid" {
                throw SkywardError.invalidResponse("Skyward loader request was unsuccessful")
            }
        }
        let normalized = html.lowercased()
        if normalized.contains("your session has expired")
            || normalized.contains("your session has timed out")
            || normalized.contains("session has ended")
            || (normalized.contains("family access")
                && normalized.contains("detailform")
                && normalized.contains("password")) {
            throw SkywardError.sessionExpired
        }
    }
}

/// The vendor's sff.request consumes response/sff text, then reads
/// sff.httpCalls[requestId].options.status. Only this metadata can signal logout;
/// arbitrary message text and JavaScript functions are never interpreted.
enum SkywardLoaderMetadata {
    struct Call {
        let requestID: String
        var options: [String: Any]?
        var messages: [[String: Any]]?
        var status: String? { options?["status"] as? String }
    }

    private struct Assignment {
        let requestID: String
        let field: String
        let value: Any
    }

    private static let maximumEnvelopeBytes = 5_000_000
    private static let maximumMetadataBytes = 512_000

    static func status(in source: String) throws -> String? {
        let statuses = try parse(source)?.compactMap(\.status) ?? []
        // A response belongs to one request; conflicting statuses do not
        // establish one trustworthy outcome without executing remote script.
        guard statuses.count <= 1 else { throw invalidMetadata() }
        return statuses.first
    }

    /// Nil denotes a non-loader response; callers can match the exact requestID.
    /// The dictionaries contain bounded literal data, never executable values.
    static func parse(_ source: String) throws -> [Call]? {
        let envelopeStart = #"^\s*(?:<\?xml\b[^>]*>\s*)?<response(?:\s|>)"#
        guard source.range(of: envelopeStart, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        guard source.utf8.count <= maximumEnvelopeBytes,
              !source.localizedCaseInsensitiveContains("<!DOCTYPE") else { throw invalidMetadata() }
        let delegate = Envelope()
        let parser = XMLParser(data: Data(source.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.failed else { throw invalidMetadata() }
        var assignments: [Assignment] = []
        for metadata in delegate.metadata {
            guard metadata.utf8.count <= maximumMetadataBytes else { throw invalidMetadata() }
            let trimmed = metadata.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("<") {
                // Script-looking text in a link, template or other inert HTML
                // is not a top-level loader assignment.
                var remainder = trimmed
                let wrapper = #"^<script\b[^>]*>([\s\S]*?)</script\s*>"#
                while remainder.range(of: #"^<script\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    guard let match = SkywardGradesAPI.firstMatch(in: remainder, pattern: wrapper, caseInsensitive: true),
                          let range = remainder.range(of: wrapper, options: [.regularExpression, .caseInsensitive]) else { throw invalidMetadata() }
                    assignments += try parseAssignments(in: match[1])
                    remainder = String(remainder[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !remainder.isEmpty, !assignments.isEmpty { throw invalidMetadata() }
            } else {
                assignments += try parseAssignments(in: trimmed)
            }
        }
        var calls: [String: Call] = [:]
        for assignment in assignments {
            var call = calls[assignment.requestID] ?? Call(requestID: assignment.requestID)
            if assignment.field == "options" {
                guard call.options == nil, let options = assignment.value as? [String: Any] else { throw invalidMetadata() }
                call.options = options
            } else {
                guard call.messages == nil, let messages = assignment.value as? [[String: Any]] else { throw invalidMetadata() }
                call.messages = messages
            }
            calls[assignment.requestID] = call
            guard calls.count <= 128 else { throw invalidMetadata() }
        }
        return calls.values.sorted { $0.requestID < $1.requestID }
    }

    private static func parseAssignments(in script: String) throws -> [Assignment] {
        let requestKey = #"([0-9]+|'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")"#
        let prefix = #"^sff\s*\.\s*httpCalls\s*\[\s*"# + requestKey + #"\s*\](?:\s*\.\s*(options|messages))?\s*="#
        var result: [Assignment] = []
        for statement in try statements(script, separator: ";") {
            let statement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = SkywardGradesAPI.firstMatch(in: statement, pattern: prefix),
                  let range = statement.range(of: prefix, options: .regularExpression) else { continue }
            let requestID: String
            let literal = String(statement[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value: Any
            do {
                let key = try JavaScriptLiteralParser.parse(match[1])
                if let string = key as? String { requestID = string }
                else if let number = key as? Int { requestID = String(number) }
                else { throw invalidMetadata() }
                value = try JavaScriptLiteralParser.parse(literal)
            } catch { throw invalidMetadata() }
            if match[2].isEmpty {
                // Verified loader wire shape assigns the whole request object.
                guard let call = value as? [String: Any] else { throw invalidMetadata() }
                if let optionsValue = call["options"] {
                    guard let options = optionsValue as? [String: Any] else { throw invalidMetadata() }
                    let optionsLiteral = try fieldLiteral("options", in: literal)
                    try validateStatusLiteral(options, literal: optionsLiteral)
                    result.append(Assignment(requestID: requestID, field: "options", value: options))
                }
                if let messagesValue = call["messages"] {
                    guard let messages = messagesValue as? [[String: Any]] else { throw invalidMetadata() }
                    _ = try fieldLiteral("messages", in: literal)
                    result.append(Assignment(requestID: requestID, field: "messages", value: messages))
                }
            } else {
                if match[2] == "options" {
                    guard let options = value as? [String: Any] else { throw invalidMetadata() }
                    try validateStatusLiteral(options, literal: literal)
                } else if !(value is [[String: Any]]) { throw invalidMetadata() }
                result.append(Assignment(requestID: requestID, field: match[2], value: value))
            }
        }
        return result
    }


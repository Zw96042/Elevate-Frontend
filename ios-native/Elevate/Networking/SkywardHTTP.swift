import Foundation
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
            isAuthenticationRequest: isAuthenticationRequest
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
            isAuthenticationRequest: false
        )
    }

    private static func perform(
        _ request: URLRequest,
        fieldNames: [String],
        redacting sensitiveValues: [String],
        suppressResponsePreview: Bool,
        validatesSession: Bool,
        isAuthenticationRequest: Bool
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
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            #if DEBUG
            logger.error("\(method, privacy: .public) failed host=\(url.host ?? "unknown", privacy: .public) path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            #endif
            throw SkywardError.network(error.localizedDescription)
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
                throw SkywardError.network("Skyward server error (\(http.statusCode))")
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
            if let finalPath = response.url?.path.lowercased(),
               finalPath.contains("fwemnu01.w") || finalPath.contains("skyportlogin") {
                throw SkywardError.sessionExpired
            }
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

    static func checkSessionExpired(_ html: String) throws {
        let normalized = html.lowercased()
        if normalized.contains("your session has expired")
            || normalized.contains("your session has timed out")
            || normalized.contains("webspeed error")
            || normalized.contains("session has ended")
            || (normalized.contains("family access")
                && normalized.contains("detailform")
                && normalized.contains("password")) {
            throw SkywardError.sessionExpired
        }
    }
}

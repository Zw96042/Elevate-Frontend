import Foundation

/// Queue credentials and generated download locations exist only for this call.
/// Remote commands are read as bounded data and are never executed.
enum SkywardReportQueueAPI {
    typealias Transport = @Sendable (URL, [(String, String)]) async throws -> String
    typealias Sleep = @Sendable (UInt64) async throws -> Void
    static let maximumPolls = 12
    static let maximumDuration: TimeInterval = 60

    static func generate(baseUrl: String, sessionCodes: SkywardSessionCodes,
                         description: String, program: String, parameters: String,
                         transport: Transport = { try await SkywardHTTP.post(url: $0, fields: $1) },
                         sleep: Sleep = { try await Task.sleep(nanoseconds: $0) }) async throws -> URL {
        try Task.checkCancellation()
        let endpoint = try SkywardBinaryHTTP.resourceURL(relativePath: "httploader.p?file=sfmainhttp001.w", baseUrl: baseUrl)
        guard !program.isEmpty, description.utf8.count <= 16_000,
              program.utf8.count <= 4_000, parameters.utf8.count <= 512_000 else {
            throw invalid("request is unrecognized or too large")
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(maximumDuration))
        var requestID = Int64(Date().timeIntervalSince1970 * 1_000)
        func request(_ fields: [(String, String)], id: Int64) async throws -> QueueResponse {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw invalid("report generation timed out") }
            let source = try await transport(endpoint, SkywardHTTP.sessionFields(sessionCodes) + fields
                + [("ishttp", "true"), ("requestId", String(id))])
            try Task.checkCancellation()
            guard clock.now < deadline else { throw invalid("report generation timed out") }
            return try parseResponse(source, requestID: String(id))
        }
        let added = try await request([("action", "addToPrintQueue"), ("queue_desc", description),
                                       ("queue_prog", program), ("queue_params", parameters)], id: requestID)
        guard added.messages.count >= 2, !added.messages[0].isEmpty, !added.messages[1].isEmpty else {
            throw invalid("queue acknowledgement is incomplete")
        }
        let queueID = added.messages[0]
        let token = added.messages[1]
        for poll in 0..<maximumPolls {
            try Task.checkCancellation()
            try await sleep(poll == 0 ? 2_000_000_000 : 5_000_000_000)
            requestID = max(requestID + 1, Int64(Date().timeIntervalSince1970 * 1_000))
            let result = try await request([("action", "checkPrintQueue"), ("queue_rowid", queueID),
                                            ("queue_token", token)], id: requestID)
            guard let state = result.messages.first else { throw invalid("queue status is missing") }
            switch state {
            case "Q", "R": continue
            case "C":
                guard result.messages.count >= 2 else { throw invalid("completed report location is missing") }
                return try completionURL(result.messages[1], baseUrl: baseUrl)
            default: throw invalid("report generation failed or returned an unknown status")
            }
        }
        throw invalid("report generation timed out")
    }

    struct QueueResponse {
        var messages: [String]
    }

    static func parseResponse(_ source: String, requestID: String) throws -> QueueResponse {
        guard source.utf8.count <= 5_000_000,
              let calls = try SkywardLoaderMetadata.parse(source), calls.count == 1,
              let call = calls.first, call.requestID == requestID else {
            throw invalid("response scope is missing or ambiguous")
        }
        if call.status == "logout" { throw SkywardError.sessionExpired }
        guard call.status == "success", let records = call.messages, records.count <= 16 else {
            throw invalid("request failed or returned unsupported metadata")
        }
        let messages = try records.map { record -> String in
            guard let value = record["message"] as? String, value.utf8.count <= 32_000 else {
                throw invalid("message is missing or too large")
            }
            return value
        }
        return QueueResponse(messages: messages)
    }
    static func completionURL(_ command: String, baseUrl: String) throws -> URL {
        guard command.utf8.count <= 32_000 else { throw invalid("completion command exceeds size limit") }
        let quoted = #"(?:'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")"#
        let pattern = #"^\s*window\.open\(\s*("# + quoted + #"\s*,\s*"# + quoted + #"\s*,\s*"# + quoted + #")\s*\)\s*;?\s*$"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
              let range = Range(match.range(at: 1), in: command),
              let values = try? JavaScriptLiteralParser.parse("[" + command[range] + "]") as? [String],
              values.count == 3, let path = values.first, !path.isEmpty else {
            throw invalid("completion command is unrecognized")
        }
        let url = try SkywardBinaryHTTP.resourceURL(relativePath: path, baseUrl: baseUrl)
        guard url.lastPathComponent.range(of: #"^qdirconfig\d+\.p$"#, options: .regularExpression) != nil,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "StuPic" }) != true else {
            throw invalid("completion resource is unrecognized")
        }
        return url
    }
    private static func invalid(_ detail: String) -> SkywardError {
        .invalidResponse("report queue " + detail)
    }
}

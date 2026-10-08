import XCTest
@testable import ElevateCore

final class ReportQueueTests: XCTestCase {
    private let base = "https://skyward.example.test/scripts/wsisa.dll/"
    private let codes = SkywardSessionCodes(dwd: "synthetic-session", wfaacl: "synthetic-acl", encses: "synthetic-enc", userType: "2", sessionid: "synthetic-id")

    static func response(id: String, messages: [String], status: String = "success") -> String {
        let records = messages.map { "{'message':\(literal($0))}" }.joined(separator: ",")
        return "<response><sff><![CDATA[<script>sff.httpCalls[\(literal(id))] = {'messages':[\(records)],'options':{'status':\(literal(status))}};</script>]]></sff></response>"
    }
    private static func literal(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
    }

    actor QueueTransport {
        var requests: [[String: String]] = []
        var waits: [UInt64] = []
        var states: [String]
        var completion: String
        init(states: [String], completion: String = "unsupportedCommand()") {
            self.states = states
            self.completion = completion
        }
        func send(_ url: URL, fields: [(String, String)]) throws -> String {
            let request = Dictionary(uniqueKeysWithValues: fields)
            requests.append(request)
            guard url.lastPathComponent == "httploader.p", url.query == "file=sfmainhttp001.w" else {
                throw SkywardError.invalidResponse("wrong synthetic endpoint")
            }
            let id = request["requestId"] ?? "missing"
            if request["action"] == "addToPrintQueue" {
                return ReportQueueTests.response(id: id, messages: ["synthetic-row", "synthetic-token"])
            }
            let state = states.isEmpty ? "Q" : states.removeFirst()
            return ReportQueueTests.response(id: id, messages: state == "C" ? [state, completion] : [state])
        }
        func sleep(_ duration: UInt64) { waits.append(duration) }
    }

    func testQueuedRunningCompletedReportReturnsSameOriginURL() async throws {
        let command = "window.open('qdirconfig123.p?blobid=synthetic-report', 'SyntheticWindow', 'width=640,height=480')"
        let queue = QueueTransport(states: ["Q", "R", "C"], completion: command)
        let url = try await SkywardReportQueueAPI.generate(baseUrl: base, sessionCodes: codes,
            description: "Synthetic", program: "reports/example.p", parameters: "synthetic-parameters",
            transport: { try await queue.send($0, fields: $1) }, sleep: { await queue.sleep($0) })
        XCTAssertEqual(url.host, "skyward.example.test")
        XCTAssertEqual(url.lastPathComponent, "qdirconfig123.p")
        let count = await queue.requests.count
        XCTAssertEqual(count, 4)
    }

    func testCompletionAllowsOnlyVerifiedLiteralCommandAndOrigin() throws {
        let valid = "window.open('qdirconfig123.p?blobid=synthetic', 'Report', 'width=640')"
        XCTAssertEqual(try SkywardReportQueueAPI.completionURL(valid, baseUrl: base).host, "skyward.example.test")
        for command in ["window.open(dangerousExpression(), 'Report', 'width=640')",
                        "window.open('https://attacker.example.test/report.pdf', 'Report', 'width=640')",
                        valid + ";dangerousExpression()", "window.open('report.pdf')",
                        "window.open('javascript:dangerousExpression()', 'Report', 'width=640')",
                        "otherFunction('report.pdf', 'Report', 'width=640')",
                        "window.open('sfstudentinfo001.w', 'Report', 'width=640')",
                        "window.open('qdirconfig123.p?StuPic=1', 'Report', 'width=640')"] {
            XCTAssertThrowsError(try SkywardReportQueueAPI.completionURL(command, baseUrl: base))
        }
    }

    func testQueuePollsAreBoundedAndUseAccountSessionFields() async throws {
        let queue = QueueTransport(states: [])
        do {
            _ = try await SkywardReportQueueAPI.generate(baseUrl: base, sessionCodes: codes,
                description: "Synthetic report", program: "reports/example.p", parameters: "synthetic-parameters",
                transport: { try await queue.send($0, fields: $1) }, sleep: { await queue.sleep($0) })
            XCTFail("Expected queue timeout")
        } catch SkywardError.invalidResponse(let detail) {
            XCTAssertTrue(detail.contains("timed out"))
            XCTAssertFalse(detail.contains("synthetic-token"))
        }
        let requests = await queue.requests
        let waits = await queue.waits
        XCTAssertEqual(requests.count, 13)
        XCTAssertEqual(waits.count, 12)
        XCTAssertEqual(waits.first, 2_000_000_000)
        XCTAssertTrue(waits.dropFirst().allSatisfy { $0 == 5_000_000_000 })
        XCTAssertEqual(Set(requests.compactMap { $0["requestId"] }).count, requests.count)
        XCTAssertTrue(requests.allSatisfy { $0["dwd"] == codes.dwd && $0["ishttp"] == "true" })
        XCTAssertEqual(requests[0]["queue_prog"], "reports/example.p")
        XCTAssertEqual(requests[0]["queue_params"], "synthetic-parameters")
        XCTAssertTrue(requests.dropFirst().allSatisfy { $0["queue_rowid"] == "synthetic-row" && $0["queue_token"] == "synthetic-token" })
    }

    func testCancellationDuringWaitStopsPolling() async throws {
        let queue = QueueTransport(states: ["Q"])
        do {
            _ = try await SkywardReportQueueAPI.generate(baseUrl: base, sessionCodes: codes,
                description: "Synthetic", program: "reports/example.p", parameters: "",
                transport: { try await queue.send($0, fields: $1) }, sleep: { _ in throw CancellationError() })
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        let count = await queue.requests.count
        XCTAssertEqual(count, 1)
    }


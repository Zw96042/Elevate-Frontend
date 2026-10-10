import XCTest
@testable import ElevateCore

final class DocumentsTests: XCTestCase {
    private let base = "https://skyward.example.test/scripts/wsisa.dll/"
    private let location = "qdirconfig123.p?blobid=synthetic-blob&duserid=synthetic-user&dwd=synthetic-session&pEnc=synthetic-token"

    private func row(id: String = "anchorA", title: String = "Semester report", kind: String = "PDF", created: String = "01/02/2026") -> String {
        "<tr><td><a id='\(id)' href='javascript:void(0)'>\(title)</a></td><td>\(kind)</td><td>\(created)</td></tr>"
    }
    private func handler(id: String = "anchorA", flags: String = "false,false", kind: String = "blobLink", path: String? = nil, extra: String = "") -> String {
        "sff.aee('a','click',function(e){sfportfolio.eSignCheck(\(flags),'synthetic-esign','\(kind)','\(path ?? location)'\(extra))},'#\(id)');"
    }
    private func page(rows: String? = nil, script: String? = nil) -> String {
        "<table id='grid_attachments123*4'><tbody><tr><th>Description</th><th>Type</th><th>Created</th></tr>\(rows ?? row())</tbody></table><script>\(script ?? handler())</script>"
    }

    func testVerifiedDirectBlobHandlerRetainsMetadataAndTransientLocation() throws {
        let parsed = try SkywardDocumentsAPI.parsePage(page(), baseUrl: base)
        let record = try XCTUnwrap(parsed.data.documents.first)
        XCTAssertEqual(record.title, "Semester report")
        XCTAssertEqual(record.kind, "PDF")
        XCTAssertEqual(record.created, "01/02/2026")
        XCTAssertTrue(record.canOpen)
        XCTAssertEqual(parsed.locations[record.id], location)
        XCTAssertEqual(parsed.data.availability, .available)
    }

    func testMetadataIdentitySurvivesSessionAndAnchorChanges() throws {
        let first = try SkywardDocumentsAPI.parsePage(page(), baseUrl: base)
        let second = try SkywardDocumentsAPI.parsePage(page(rows: row(id: "newAnchor"), script: handler(id: "newAnchor", path: location.replacingOccurrences(of: "synthetic-session", with: "new-session"))), baseUrl: base)
        XCTAssertEqual(first.data.documents, second.data.documents)
        XCTAssertNotEqual(first.locations, second.locations)
    }

    func testDuplicateDescriptionsHaveDistinctStableOccurrenceIDs() throws {
        let parsed = try SkywardDocumentsAPI.parsePage(page(rows: row() + row(id: "anchorB"), script: handler() + handler(id: "anchorB")), baseUrl: base)
        XCTAssertEqual(parsed.data.documents.count, 2)
        XCTAssertEqual(Set(parsed.data.documents.map(\.id)).count, 2)
        XCTAssertEqual(parsed.locations.count, 2)
    }

    func testEncodedCacheContainsNoDownloadOrSessionInformation() throws {
        let data = try SkywardDocumentsAPI.parse(page())
        let encoded = String(decoding: try JSONEncoder().encode(data), as: UTF8.self)
        for secret in ["qdirconfig", "blobid", "duserid", "dwd", "pEnc", "synthetic-session", "synthetic-token", "anchorA"] {
            XCTAssertFalse(encoded.contains(secret), "Cache contains \(secret)")
        }
        XCTAssertEqual(try JSONDecoder().decode(DocumentsData.self, from: Data(encoded.utf8)), data)
    }

    func testGeneratedReportRetainsOnlyMetadataInCache() throws {
        let script = handler(kind: "addToQueue", path: "Semester report", extra: ",'reports/report.r','opaque-synthetic-parameters'")
        let parsed = try SkywardDocumentsAPI.parsePage(page(script: script), baseUrl: base)
        let record = try XCTUnwrap(parsed.data.documents.first)
        XCTAssertTrue(record.canOpen)
        XCTAssertTrue(parsed.locations.isEmpty)
        guard case let .report(description, program, parameters) = parsed.actions[record.id] else {
            return XCTFail("Expected transient generated-report action")
        }
        XCTAssertEqual(description, "Semester report")
        XCTAssertEqual(program, "reports/report.r")
        XCTAssertEqual(parameters, "opaque-synthetic-parameters")
        let encoded = String(decoding: try JSONEncoder().encode(parsed.data), as: UTF8.self)
        XCTAssertFalse(encoded.contains("reports/report.r"))
        XCTAssertFalse(encoded.contains("opaque-synthetic-parameters"))
    }

    func testGeneratedReportSignaturesExpressionsAndUnsafeProgramStayUnavailable() throws {
        for script in [
            handler(flags: "true,false", kind: "addToQueue", path: "Report", extra: ",'reports/report.r','params'"),
            handler(flags: "false,true", kind: "addToQueue", path: "Report", extra: ",'reports/report.r','params'"),
            handler(kind: "addToQueue", path: "Report", extra: ",'../report.r','params'"),
            handler(kind: "addToQueue", path: "Report", extra: ",'https://evil.example/report.r','params'"),
            handler(kind: "addToQueue", path: "Report", extra: ",'reports/report.r',''"),
            handler(kind: "addToQueue", path: "Report", extra: ",'reports/report.r',dangerousExpression()")
        ] {
            let parsed = try SkywardDocumentsAPI.parsePage(page(script: script), baseUrl: base)
            XCTAssertFalse(parsed.data.documents[0].canOpen)
            XCTAssertTrue(parsed.actions.isEmpty)
        }
    }

    func testVerifiedEmptyAndOptionalMetadata() throws {
        let empty = try SkywardDocumentsAPI.parse(page(rows: "<tr><td colspan='3'>No records to display</td></tr>", script: ""))
        XCTAssertTrue(empty.documents.isEmpty)
        XCTAssertEqual(empty.availability, .available)
        let record = try XCTUnwrap(SkywardDocumentsAPI.parse(page(rows: row(kind: "", created: ""))).documents.first)
        XCTAssertNil(record.kind)
        XCTAssertNil(record.created)
    }

    func testUnsupportedSignaturesStayVisibleWithoutDownload() throws {
        let scripts = [handler(flags: "true,false"), handler(flags: "false,true"), handler(kind: "generatedReport"),
                       handler().replacingOccurrences(of: "#anchorA", with: "anchorA"), handler(extra: ",'additional'"), "", "sfportfolio.eSignCheck(false,false,'synthetic-esign','blobLink','\(location)');",
                       handler().replacingOccurrences(of: "'synthetic-esign'", with: "dangerousExpression()")]
        for script in scripts {
            let parsed = try SkywardDocumentsAPI.parsePage(page(script: script), baseUrl: base)
            XCTAssertEqual(parsed.data.documents.count, 1)
            XCTAssertFalse(parsed.data.documents[0].canOpen)
            XCTAssertTrue(parsed.locations.isEmpty)
        }
    }

    func testInvalidResourceOriginsAndStudentPhotoPathsCannotOpen() throws {
        let paths = ["https://attacker.example.test/qdirconfig123.p?blobid=synthetic", "//attacker.example.test/qdirconfig123.p?blobid=synthetic",
                     "qdirconfig123.p?StuPic=1&blobid=synthetic", "qdirconfig123.p?blobid=", "other.p?blobid=synthetic",
                     "javascript:dangerousExpression()"]
        for path in paths {
            let parsed = try SkywardDocumentsAPI.parsePage(page(script: handler(path: path)), baseUrl: base)
            XCTAssertFalse(parsed.data.documents[0].canOpen)
            XCTAssertTrue(parsed.locations.isEmpty)
        }
    }

    func testSameOriginAbsoluteBlobCanOpen() throws {
        let parsed = try SkywardDocumentsAPI.parsePage(page(script: handler(path: base + location)), baseUrl: base)
        XCTAssertTrue(parsed.data.documents[0].canOpen)
    }

    func testMalformedTruncatedNestedAndAmbiguousTablesFail() {
        let malformed = [String(page().prefix(80)), page().replacingOccurrences(of: "</table>", with: ""),
                         page().replacingOccurrences(of: "</td>", with: "", range: page().range(of: "</td>")),
                         page().replacingOccurrences(of: "<td>PDF</td>", with: "<td><table><tr><td>PDF</td></tr></table></td>"),
                         page() + page(), page().replacingOccurrences(of: "<th>Created</th>", with: "<th>Unexpected</th>"),
                         page(rows: row() + "<tr><td colspan='3'>No documents</td></tr>"),
                         page(rows: "<tr><td colspan='3'>No documents</td></tr><tr><td colspan='3'>No documents</td></tr>", script: ""),
                         page(script: handler() + handler()), "<html><body>Maintenance</body></html>"]
        for html in malformed { XCTAssertThrowsError(try SkywardDocumentsAPI.parse(html)) }
    }

    func testBalancedButMisorderedClosingTagsFail() {
        let html = page().replacingOccurrences(of: "<td>01/02/2026</td></tr>", with: "<td>01/02/2026</tr></td>")
        XCTAssertThrowsError(try SkywardDocumentsAPI.parse(html))
    }

    func testDuplicateRowAnchorIDsFail() {
        XCTAssertThrowsError(try SkywardDocumentsAPI.parse(page(rows: row() + row())))
    }

    func testUnrecognizedTableBodyContentAndHeadersFail() {
        let cases = [page(rows: "", script: "").replacingOccurrences(of: "<tbody>", with: "").replacingOccurrences(of: "</tbody>", with: ""),
                     page(rows: "<div>Unrecognized content</div>", script: ""),
                     page(rows: "", script: "").replacingOccurrences(of: "<tbody>", with: "<div>Unexpected</div><tbody>"),
                     page(rows: "", script: "").replacingOccurrences(of: "<tbody>", with: "Unexpected text<tbody>"),
                     page(rows: "<tr><th>Description</th><th>Type</th><th>Created</th></tr>", script: ""),
                     page().replacingOccurrences(of: "<th>Description</th><th>Type</th><th>Created</th>", with: "<th>Type</th><th>Description</th><th>Created</th>")]
        for html in cases { XCTAssertThrowsError(try SkywardDocumentsAPI.parse(html)) }
    }

    func testCompleteHeaderAndEmptyBodyAreVerifiedEmpty() throws {
        let data = try SkywardDocumentsAPI.parse(page(rows: "", script: ""))
        XCTAssertTrue(data.documents.isEmpty)
        XCTAssertEqual(data.availability, .available)
    }

    func testExpiredSessionAndSizeLimitFail() {
        XCTAssertThrowsError(try SkywardDocumentsAPI.parse("Your session has expired")) { error in
            guard case SkywardError.sessionExpired = error else { return XCTFail("Expected session expiry") }
        }
        XCTAssertThrowsError(try SkywardDocumentsAPI.parse(page() + String(repeating: " ", count: 4_000_001)))
    }

    func testOmittedTbodyClosingIsAccepted() {
        XCTAssertNoThrow(try SkywardDocumentsAPI.parse(page().replacingOccurrences(of: "</tbody>", with: "")))
    }
}

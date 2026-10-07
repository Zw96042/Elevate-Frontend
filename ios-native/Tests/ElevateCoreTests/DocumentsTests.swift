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


import Foundation
import Testing
@testable import ElevateCore

@Suite("Posted Skyward fees and payments")
struct FeesTests {
    private let feeHeaders = ["SchoolYear", "Due Date", "Fee Description", "AmountCharged", "AmountPaid", "AmountDue", "RemainingDue", "Payor Name", "Pay Plan ID"]
    private let paymentHeaders = ["Payor Name", "School Year", "Payment Date", "Description", "Payment Amount", "Check #", "Receipt #"]
    private let feeValues = ["2026", "09/30/2026", "Physics lab fee", "$25.00", "$0.00", "$25.00", "$10.00", "Example Payor", "Plan-1"]
    private let paymentValues = ["Example Payor", "2026", "09/15/2026", "Online payment", "$15.00", "", "Receipt-1"]

    @Test("Verified nine- and seven-column tables preserve every posted field")
    func populated() throws {
        let data = try SkywardFeesAPI.parse(page(fees: row(feeValues), payments: row(paymentValues)))
        #expect(data.availability == .available)
        let fee = try #require(data.fees.first)
        #expect(fee.description == "Physics lab fee")
        #expect(fee.schoolYear == "2026")
        #expect(fee.date == "09/30/2026")
        #expect(fee.fields.count == 9)
        #expect(fee.fields.first { $0.label == "Amount due" }?.value == "$25.00")
        #expect(fee.fields.first { $0.label == "Remaining due" }?.value == "$10.00")
        #expect(fee.fields.first { $0.label == "Pay plan ID" }?.value == "Plan-1")
        let payment = try #require(data.payments.first)
        #expect(payment.description == "Online payment")
        #expect(payment.date == "09/15/2026")
        #expect(payment.fields.first { $0.label == "Payment amount" }?.value == "$15.00")
        #expect(payment.fields.first { $0.label == "Check #" }?.value == "")
        #expect(payment.fields.first { $0.label == "Receipt #" }?.value == "Receipt-1")
        #expect(Set(fee.fields.map(\.id)).count == 9)
        #expect(try JSONDecoder().decode(FeesData.self, from: JSONEncoder().encode(data)) == data)
    }

    @Test("Zero, credit, description and date strings remain exact source text")
    func preservesText() throws {
        var values = feeValues
        values[0] = "2025-2026"
        values[1] = "Posted date pending"
        values[2] = "  Materials  &amp; lab  \n"
        values[3] = " $0.00 "
        values[4] = "($10.00)"
        values[5] = "0.00"
        values[6] = "-5.00"
        let fee = try #require(SkywardFeesAPI.parse(page(fees: row(values))).fees.first)
        #expect(fee.description == "Materials  & lab")
        #expect(fee.schoolYear == "2025-2026")
        #expect(fee.date == "Posted date pending")
        #expect(fee.fields.map(\.value)[3...6] == ["$0.00", "($10.00)", "0.00", "-5.00"])
    }

    @Test("Duplicate rows remain separate and distinct-row identities survive reordering")
    func identities() throws {
        let first = row(feeValues)
        var otherValues = feeValues
        otherValues[2] = "Art materials"
        let other = row(otherValues)
        let original = try SkywardFeesAPI.parse(page(fees: first + first + other)).fees
        let reordered = try SkywardFeesAPI.parse(page(fees: other + first + first)).fees
        #expect(original.count == 3)
        #expect(Set(original.map(\.id)).count == 3)
        #expect(Set(original.map(\.id)) == Set(reordered.map(\.id)))
    }

    @Test("Complete empty grids and correct unlinked colspan markers are verified empty")
    func emptyGrids() throws {
        for fees in ["", "<tr><td colspan='9'>No fee records</td></tr>", "<tr><td colspan='9'>No records to display</td></tr>"] {
            let data = try SkywardFeesAPI.parse(page(fees: fees, payments: "<tr><td colspan='7'>No payment records</td></tr>"))
            #expect(data.fees.isEmpty && data.payments.isEmpty)
            #expect(data.availability == .available)
        }
        for fees in [
            "<tr><td colspan='9'><a>No records to display</a></td></tr>",
            "<tr><td colspan='9'>Temporarily unavailable</td></tr>",
            "<tr><td colspan='7'>No fees</td></tr>",
            "<tr><td colspan='9'>No payments</td></tr>",
            "<tr><td colspan='9'>No fees</td></tr>" + row(feeValues),
            row(Array(repeating: "", count: 9)),
        ] {
            #expect(throws: SkywardError.self) { _ = try SkywardFeesAPI.parse(page(fees: fees)) }
        }
    }

    @Test("A missing table requires a specific complete-page empty marker")
    func missingGrid() throws {
        let paymentTable = table(id: "grid_PaymentsDet1", headers: paymentHeaders, rows: row(paymentValues))
        let valid = document("<p>No fees</p>" + paymentTable)
        #expect(try SkywardFeesAPI.parse(valid).fees.isEmpty)
        #expect(try SkywardFeesAPI.parse(valid).payments.count == 1)
        for html in [document(paymentTable), document("<p>No records to display</p>" + paymentTable), document("<p><a>No fees</a></p>" + paymentTable)] {
            #expect(throws: SkywardError.self) { _ = try SkywardFeesAPI.parse(html) }
        }
    }

    @Test("Explicit unavailable state requires the recognized complete page")
    func unavailable() throws {
        #expect(try SkywardFeesAPI.parse(document("<p>Fee management is unavailable.</p>")).availability == .unavailable)
        for html in [
            "<title>Maintenance</title><body>Fee management is unavailable</body>",
            document("<p>Maintenance in progress</p>"),
            "<title>Fee Management</title><body><p>Fees unavailable</p>",
        ] {
            #expect(throws: SkywardError.self) { _ = try SkywardFeesAPI.parse(html) }
        }
    }

    @Test("Wrapped layout tables are ignored and nested record-cell tables are rejected")
    func ownership() throws {
        let wrapped = "<table><tbody><tr><td>" + page(fees: row(feeValues)) + "</td></tr></tbody></table>"
        #expect(try SkywardFeesAPI.parse(wrapped).fees.count == 1)
        var values = feeValues
        values[2] = "<table><tbody>" + row(feeValues) + "</tbody></table>"
        #expect(throws: SkywardError.self) { _ = try SkywardFeesAPI.parse(page(fees: row(values))) }
    }

    @Test("Optional tbody close is accepted but missing row/cell/table closures remain errors")
    func structure() throws {
        let complete = page(fees: row(feeValues), payments: row(paymentValues))
        #expect(try SkywardFeesAPI.parse(complete.replacingOccurrences(of: "</tbody>", with: "")).fees.count == 1)
        for html in [
            complete.replacingOccurrences(of: "</table>", with: ""),
            complete.replacingOccurrences(of: "</tr>", with: ""),
            complete.replacingOccurrences(of: "</td>", with: ""),
            page(fees: "<tr><td>Unknown row</td></tr>"),
            page(fees: "<div>Unknown body content</div>"),
            complete.replacingOccurrences(of: "<th>RemainingDue</th>", with: ""),
            complete.replacingOccurrences(of: "<th>AmountDue</th>", with: "<th>Other amount</th>"),
        ] {
            #expect(throws: SkywardError.self) { _ = try SkywardFeesAPI.parse(html) }
        }
    }

    @Test("Header whitespace and br labels normalize without changing source fields")
    func headerNormalization() throws {
        let html = page(fees: row(feeValues))
            .replacingOccurrences(of: "<th>AmountCharged</th>", with: "<th>Amount<br>Charged</th>")
            .replacingOccurrences(of: "<th>SchoolYear</th>", with: "<th> School \n Year </th>")
        #expect(try SkywardFeesAPI.parse(html).fees.count == 1)
    }

    @Test("Expired and login responses remain session errors")
    func sessionExpiry() {
        for html in ["Your session has expired", "<title>Family Access</title><form id='detailform'><input type='password'></form>"] {
            do {
                _ = try SkywardFeesAPI.parse(html)
                Issue.record("Expected session expiry")
            } catch SkywardError.sessionExpired {
                // Expected.
            } catch {
                Issue.record("Unexpected error category")
            }
        }
    }

    @Test("Ambiguous student grids and oversized payloads cannot become records")
    func limitsAndScope() {
        let duplicate = page(fees: row(feeValues)) + table(id: "grid_FeesDet2", headers: feeHeaders, rows: row(feeValues))
        #expect(throws: SkywardError.self) { _ = try SkywardFeesAPI.parse(duplicate) }
        #expect(throws: SkywardError.self) {
            _ = try SkywardFeesAPI.parse(String(repeating: "x", count: SkywardFeesAPI.maximumHTMLBytes + 1))
        }
        let many = String(repeating: row(feeValues), count: SkywardFeesAPI.maximumRows + 1)
        #expect(throws: SkywardError.self) { _ = try SkywardFeesAPI.parse(page(fees: many)) }
    }

    private func row(_ values: [String]) -> String { "<tr>" + values.map { "<td>\($0)</td>" }.joined() + "</tr>" }
    private func table(id: String, headers: [String], rows: String) -> String {
        "<table id='\(id)'><thead><tr>" + headers.map { "<th>\($0)</th>" }.joined() + "</tr></thead><tbody>\(rows)</tbody></table>"
    }
    private func document(_ content: String) -> String { "<html><head><title>Fee Management</title></head><body>\(content)</body></html>" }
    private func page(fees: String = "", payments: String = "") -> String {
        document(table(id: "grid_FeesDet1", headers: feeHeaders, rows: fees) + table(id: "grid_PaymentsDet1", headers: paymentHeaders, rows: payments))
    }
}

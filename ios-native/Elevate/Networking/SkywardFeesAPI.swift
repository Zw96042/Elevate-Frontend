import Foundation

/// Read-only fee/payment records from the verified Student Access endpoint.
enum SkywardFeesAPI {
    static let maximumHTMLBytes = 4_000_000
    static let maximumRows = 10_000

    private struct TableSchema: Sendable {
        var idPattern: String
        var columns: [String]
        var labels: [String]
        var descriptionIndex: Int
        var yearIndex: Int
        var dateIndex: Int
        var emptyMarkers: Set<String>
    }

    private static let feesSchema = TableSchema(
        idPattern: #"^grid_FeesDet\d+$"#,
        columns: ["schoolyear", "duedate", "feedescription", "amountcharged", "amountpaid", "amountdue", "remainingdue", "payorname", "payplanid"],
        labels: ["School year", "Due date", "Fee description", "Amount charged", "Amount paid", "Amount due", "Remaining due", "Payor name", "Pay plan ID"],
        descriptionIndex: 2, yearIndex: 0, dateIndex: 1,
        emptyMarkers: ["no fees", "no fee records", "no fees to display", "no records to display", "no records found"]
    )
    private static let paymentsSchema = TableSchema(
        idPattern: #"^grid_PaymentsDet\d+$"#,
        columns: ["payorname", "schoolyear", "paymentdate", "description", "paymentamount", "check#", "receipt#"],
        labels: ["Payor name", "School year", "Payment date", "Description", "Payment amount", "Check #", "Receipt #"],
        descriptionIndex: 3, yearIndex: 1, dateIndex: 2,
        emptyMarkers: ["no payments", "no payment records", "no payments to display", "no records to display", "no records found"]
    )

    static func fetch(baseUrl: String, sessionCodes: SkywardSessionCodes) async throws -> FeesData {
        guard let url = URL(string: baseUrl + "sffeemanagement001.w") else {
            throw SkywardError.invalidResponse("invalid base URL")
        }
        let html = try await SkywardHTTP.post(url: url, fields: SkywardHTTP.sessionFields(sessionCodes))
        return try parse(html)
    }

    static func parse(_ html: String) throws -> FeesData {
        try SkywardHTTP.checkSessionExpired(html)
        guard html.utf8.count <= maximumHTMLBytes else {
            throw SkywardError.invalidResponse("fees response exceeds size limit")
        }
        let root = MiniHTML.parse(html)
        let tables = root.querySelectorAll("table")
        let feesTables = tables.filter { $0.id.range(of: feesSchema.idPattern, options: .regularExpression) != nil }
        let paymentsTables = tables.filter { $0.id.range(of: paymentsSchema.idPattern, options: .regularExpression) != nil }
        guard feesTables.count <= 1, paymentsTables.count <= 1 else {
            throw SkywardError.invalidResponse("fees response has ambiguous student scope")
        }
        let recognizedPage = isCompleteFeesPage(root, html: html)
        if feesTables.isEmpty, paymentsTables.isEmpty, recognizedPage,
           containsStaticMarker(root, markers: ["fees unavailable", "fees are unavailable", "fee management unavailable", "fee management is unavailable", "fee management is not available", "fee management is disabled"]) {
            return FeesData(fees: [], payments: [], availability: .unavailable)
        }
        let fees = try records(in: feesTables.first, schema: feesSchema, root: root, html: html, recognizedPage: recognizedPage)
        let payments = try records(in: paymentsTables.first, schema: paymentsSchema, root: root, html: html, recognizedPage: recognizedPage)
        guard fees.count + payments.count <= maximumRows else {
            throw SkywardError.invalidResponse("fees response exceeds row limit")
        }
        return FeesData(fees: fees, payments: payments)
    }

    private static func records(in table: HTMLNode?, schema: TableSchema, root: HTMLNode, html: String, recognizedPage: Bool) throws -> [FeeRecord] {
        guard let table else {
            // A generic no-records message cannot establish which missing grid
            // is empty. Require an explicit fees/payments-specific marker.
            let specificMarkers = schema.emptyMarkers.filter { $0.contains("fee") || $0.contains("payment") }
            guard recognizedPage, containsStaticMarker(root, markers: Set(specificMarkers)) else {
                throw SkywardError.invalidResponse("fees or payments table not found")
            }
            return []
        }
        try requireCompleteTable(html, tableID: table.id)
        guard table.elements.contains(where: { $0.tagName == "tbody" }) else {
            throw SkywardError.invalidResponse("fees table body is missing")
        }
        for section in table.elements where ["thead", "tbody", "tfoot"].contains(section.tagName) {
            guard section.elements.allSatisfy({ $0.tagName == "tr" }),
                  section.children.filter(\.isText).allSatisfy({ trimmed($0.text).isEmpty }) else {
                throw SkywardError.invalidResponse("fees table section is unrecognized")
            }
        }
        let rows = table.querySelectorAll("tr").filter { nearestTable($0) === table }
        guard rows.count <= maximumRows + 1 else {
            throw SkywardError.invalidResponse("fees table exceeds row limit")
        }
        let headers = rows.filter { $0.elements.contains { $0.tagName == "th" } }
        guard headers.count == 1, let header = headers.first,
              header.elements.count == schema.columns.count,
              header.elements.allSatisfy({ $0.tagName == "th" && $0.querySelector("table") == nil }),
              header.elements.map({ normalizedHeader($0.text) }) == schema.columns else {
            throw SkywardError.invalidResponse("fees table columns are unrecognized")
        }
        var records: [FeeRecord] = []
        var occurrences: [String: Int] = [:]
        var emptyMarkerSeen = false
        for row in rows where row !== header {
            let cells = row.elements
            guard cells.allSatisfy({ $0.tagName == "td" && $0.querySelector("table") == nil
                && $0.querySelector("script") == nil && $0.querySelector("style") == nil }),
                  row.children.filter(\.isText).allSatisfy({ trimmed($0.text).isEmpty }) else {
                throw SkywardError.invalidResponse("fees table row is incomplete")
            }
            if cells.count == 1, cells[0].attribute("colspan") == String(schema.columns.count),
               row.querySelector("a") == nil, schema.emptyMarkers.contains(normalizedMarker(cells[0].text)) {
                guard !emptyMarkerSeen else { throw SkywardError.invalidResponse("fees table has repeated empty markers") }
                emptyMarkerSeen = true
                continue
            }
            guard cells.count == schema.columns.count,
                  cells.allSatisfy({ ($0.attribute("colspan") ?? "1") == "1" && ($0.attribute("rowspan") ?? "1") == "1" }) else {
                throw SkywardError.invalidResponse("fees table row has invalid columns")
            }
            let values = cells.map { trimmed($0.text) }
            guard values.contains(where: { !$0.isEmpty }) else {
                throw SkywardError.invalidResponse("fees table contains an unrecognized blank row")
            }
            let identity = ([table.id] + values).map { "\($0.utf8.count):\($0)" }.joined()
            let occurrence = occurrences[identity, default: 0]
            occurrences[identity] = occurrence + 1
            records.append(FeeRecord(
                id: "fee:\(identity):\(occurrence)", description: values[schema.descriptionIndex],
                schoolYear: optionalText(values[schema.yearIndex]), date: optionalText(values[schema.dateIndex]),
                fields: zip(schema.labels, values).map { FeeField(label: $0.0, value: $0.1) }
            ))
        }
        guard !emptyMarkerSeen || records.isEmpty else {
            throw SkywardError.invalidResponse("fees table mixes records and an empty marker")
        }
        return records
    }


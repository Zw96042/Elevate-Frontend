import Foundation

/// Labelled source text. Amounts are kept as posted rather than recomputed.
struct FeeField: Codable, Hashable, Identifiable {
    var label: String
    var value: String
    var id: String { label }
}

struct FeeRecord: Codable, Hashable, Identifiable {
    var id: String
    var description: String
    var schoolYear: String?
    var date: String?
    var fields: [FeeField]
}

struct FeesData: Codable, Equatable {
    var fees: [FeeRecord]
    var payments: [FeeRecord]
    var availability: AttendanceAvailability = .available
}

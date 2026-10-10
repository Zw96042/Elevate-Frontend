import Foundation

enum AttendanceAvailability: String, Codable {
    case available, unavailable
}

enum AttendanceGranularity: String, Codable {
    case daily, period, unknown
}

/// A source attendance exception, not a count of absent days or days present.
struct AttendanceRecord: Codable, Hashable, Identifiable {
    var id: String
    /// School date without a timezone, in yyyy-MM-dd form.
    var date: String
    var attendance: String
    var period: String?
    var courseName: String?
    var rawCode: String? = nil
    var granularity: AttendanceGranularity = .unknown

    /// Local noon keeps the source school date when rendered in the local timezone.
    var displayDate: Date? {
        guard let components = AttendanceSchoolDate.components(date) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(
            year: components.year, month: components.month, day: components.day, hour: 12
        ))
    }
}

struct AttendanceData: Codable, Equatable {
    var records: [AttendanceRecord]
    var availability: AttendanceAvailability = .available
}

enum AttendanceSchoolDate {
    static func components(_ isoDate: String) -> (year: Int, month: Int, day: Int)? {
        let parts = isoDate.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1900...9999).contains(year), (1...12).contains(month) else { return nil }
        let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...monthDays[month - 1]).contains(day) else { return nil }
        return (year, month, day)
    }

    static func normalize(_ source: String) -> String? {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if components(text) != nil { return text }
        // Verified portal form: Wed Sep 16, 2026. Parse components directly so
        // invalid school dates cannot be silently rolled into the next month.
        let portalPattern = #"^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2}),\s+(\d{4})$"#
        if let match = SkywardGradesAPI.firstMatch(in: text, pattern: portalPattern, caseInsensitive: true),
           let monthIndex = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].firstIndex(of: match[1].lowercased()),
           let day = Int(match[2]), let year = Int(match[3]) {
            let result = String(format: "%04d-%02d-%02d", year, monthIndex + 1, day)
            return components(result) == nil ? nil : result
        }
        // Accept an optional source weekday, then an unambiguous US school date.
        let pattern = #"^(?:(?:Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?),?\s+)?(\d{1,2})/(\d{1,2})/(\d{4})$"#
        guard let match = SkywardGradesAPI.firstMatch(in: text, pattern: pattern, caseInsensitive: true),
              let month = Int(match[1]), let day = Int(match[2]), let year = Int(match[3]) else { return nil }
        let result = String(format: "%04d-%02d-%02d", year, month, day)
        return components(result) == nil ? nil : result
    }
}

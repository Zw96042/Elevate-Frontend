import Foundation

struct SkywardDocument: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var kind: String?
    var created: String?
    var canOpen: Bool = true
}

struct DocumentsData: Codable, Equatable {
    var documents: [SkywardDocument]
    var availability: AttendanceAvailability = .available
}

struct DocumentPreview: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var title: String
}

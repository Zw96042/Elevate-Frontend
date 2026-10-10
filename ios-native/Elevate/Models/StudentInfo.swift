import Foundation

struct StudentInfoField: Codable, Hashable, Identifiable {
    var label: String
    var value: String
    var id: String { label }
}

struct StudentEnrollment: Codable, Hashable, Identifiable {
    var id: String
    var schoolName: String?
    var fields: [StudentInfoField]
}

struct StudentInfoData: Codable, Hashable {
    var name: String
    var contactFields: [StudentInfoField]
    var studentFields: [StudentInfoField]
    var enrollments: [StudentEnrollment]
    var photoData: Data? = nil
    var photoLoadFailed: Bool = false

    private enum CodingKeys: String, CodingKey {
        case name, contactFields, studentFields, enrollments, photoData, photoLoadFailed
    }

    init(name: String, contactFields: [StudentInfoField], studentFields: [StudentInfoField],
         enrollments: [StudentEnrollment], photoData: Data? = nil, photoLoadFailed: Bool = false) {
        self.name = name
        self.contactFields = contactFields
        self.studentFields = studentFields
        self.enrollments = enrollments
        self.photoData = photoData
        self.photoLoadFailed = photoLoadFailed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        contactFields = try container.decode([StudentInfoField].self, forKey: .contactFields)
        studentFields = try container.decode([StudentInfoField].self, forKey: .studentFields)
        enrollments = try container.decode([StudentEnrollment].self, forKey: .enrollments)
        photoData = try container.decodeIfPresent(Data.self, forKey: .photoData)
        photoLoadFailed = try container.decodeIfPresent(Bool.self, forKey: .photoLoadFailed) ?? false
    }
}

import Foundation

struct Tag: Codable, Identifiable, Hashable {
    let id: Int
    let userId: Int
    let name: String
    let color: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case color
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TagCreate: Encodable {
    let name: String
    let color: String?
}

struct TagUpdate: Encodable {
    let name: String?
    let color: String?
}

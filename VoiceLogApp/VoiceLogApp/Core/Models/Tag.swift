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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        userId = try container.decode(Int.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(String.self, forKey: .color)

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        guard let createdAtDate = DateParsing.parseDate(createdAtString) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [CodingKeys.createdAt], debugDescription: "Cannot parse date: \(createdAtString)")
            )
        }
        createdAt = createdAtDate

        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        guard let updatedAtDate = DateParsing.parseDate(updatedAtString) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [CodingKeys.updatedAt], debugDescription: "Cannot parse date: \(updatedAtString)")
            )
        }
        updatedAt = updatedAtDate
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

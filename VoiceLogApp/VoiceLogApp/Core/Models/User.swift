import Foundation

struct User: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, email
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)

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

struct UserRegister: Encodable {
    let name: String
    let email: String
    let password: String
}

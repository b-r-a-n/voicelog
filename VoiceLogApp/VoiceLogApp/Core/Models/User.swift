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
}

struct UserRegister: Encodable {
    let name: String
    let email: String
    let password: String
}

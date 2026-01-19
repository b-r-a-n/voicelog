import Foundation

struct ExportStatus: Codable {
    let exportId: String
    let noteId: Int
    let format: String
    let status: String
    let createdAt: Date
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case exportId = "export_id"
        case noteId = "note_id"
        case format
        case status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportId = try container.decode(String.self, forKey: .exportId)
        noteId = try container.decode(Int.self, forKey: .noteId)
        format = try container.decode(String.self, forKey: .format)
        status = try container.decode(String.self, forKey: .status)

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        guard let createdAtDate = DateParsing.parseDate(createdAtString) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [CodingKeys.createdAt], debugDescription: "Cannot parse date: \(createdAtString)")
            )
        }
        createdAt = createdAtDate

        if let expiresAtString = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
            expiresAt = DateParsing.parseDate(expiresAtString)
        } else {
            expiresAt = nil
        }
    }
}

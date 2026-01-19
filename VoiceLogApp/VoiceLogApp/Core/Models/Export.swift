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
}

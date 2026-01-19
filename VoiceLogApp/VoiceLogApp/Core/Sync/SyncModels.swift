import Foundation

struct SyncRequest: Encodable {
    let since: Date?
    let notes: [ClientNoteChange]
    let tags: [ClientTagChange]
}

struct ClientNoteChange: Encodable {
    let localId: String
    let title: String
    let transcript: String?
    let transcriptChecksum: String?
    let transcriptPreview: String?
    let duration: Double
    let recordedAt: Date?
    let isDeleted: Bool
    let tagIds: [Int]

    enum CodingKeys: String, CodingKey {
        case localId = "local_id"
        case title
        case transcript
        case transcriptChecksum = "transcript_checksum"
        case transcriptPreview = "transcript_preview"
        case duration
        case recordedAt = "recorded_at"
        case isDeleted = "is_deleted"
        case tagIds = "tag_ids"
    }
}

struct ClientTagChange: Encodable {
    let localId: String?
    let serverId: Int?
    let name: String
    let color: String?
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case localId = "local_id"
        case serverId = "server_id"
        case name
        case color
        case isDeleted = "is_deleted"
    }
}

struct SyncResponse: Decodable {
    let notes: [NoteSync]
    let tags: [TagSync]
    let syncTimestamp: Date

    enum CodingKeys: String, CodingKey {
        case notes
        case tags
        case syncTimestamp = "sync_timestamp"
    }
}

struct NoteSync: Decodable {
    let id: Int
    let localId: String?
    let title: String
    let transcriptPreview: String?
    let transcriptSize: Int
    let transcriptChecksum: String?
    let duration: Double
    let recordedAt: Date?
    let summary: String?
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool
    let tagIds: [Int]

    enum CodingKeys: String, CodingKey {
        case id
        case localId = "local_id"
        case title
        case transcriptPreview = "transcript_preview"
        case transcriptSize = "transcript_size"
        case transcriptChecksum = "transcript_checksum"
        case duration
        case recordedAt = "recorded_at"
        case summary
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case tagIds = "tag_ids"
    }
}

struct TagSync: Decodable {
    let id: Int
    let name: String
    let color: String?
    let createdAt: Date
    let updatedAt: Date
    let isDeleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
    }
}

import Foundation

struct Note: Codable, Identifiable {
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
    let tags: [Tag]

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
        case tags
    }
}

struct NoteDetail: Codable, Identifiable {
    let id: Int
    let localId: String?
    let title: String
    let transcript: String?
    let transcriptPreview: String?
    let transcriptSize: Int
    let transcriptChecksum: String?
    let duration: Double
    let recordedAt: Date?
    let summary: String?
    let createdAt: Date
    let updatedAt: Date
    let tags: [Tag]

    enum CodingKeys: String, CodingKey {
        case id
        case localId = "local_id"
        case title
        case transcript
        case transcriptPreview = "transcript_preview"
        case transcriptSize = "transcript_size"
        case transcriptChecksum = "transcript_checksum"
        case duration
        case recordedAt = "recorded_at"
        case summary
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case tags
    }
}

struct NoteCreate: Encodable {
    let title: String
    let localId: String?
    let transcript: String?
    let transcriptChecksum: String?
    let duration: Double
    let recordedAt: Date?

    enum CodingKeys: String, CodingKey {
        case title
        case localId = "local_id"
        case transcript
        case transcriptChecksum = "transcript_checksum"
        case duration
        case recordedAt = "recorded_at"
    }
}

struct NoteUpdate: Encodable {
    let title: String?
    let transcript: String?
    let transcriptChecksum: String?

    enum CodingKeys: String, CodingKey {
        case title
        case transcript
        case transcriptChecksum = "transcript_checksum"
    }
}

struct NoteSummarize: Encodable {
    let prompt: String?
}

struct NoteExport: Encodable {
    let format: String
}

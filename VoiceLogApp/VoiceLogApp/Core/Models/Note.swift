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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        localId = try container.decodeIfPresent(String.self, forKey: .localId)
        title = try container.decode(String.self, forKey: .title)
        transcriptPreview = try container.decodeIfPresent(String.self, forKey: .transcriptPreview)
        transcriptSize = try container.decode(Int.self, forKey: .transcriptSize)
        transcriptChecksum = try container.decodeIfPresent(String.self, forKey: .transcriptChecksum)
        duration = try container.decode(Double.self, forKey: .duration)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        tags = try container.decode([Tag].self, forKey: .tags)

        if let recordedAtString = try container.decodeIfPresent(String.self, forKey: .recordedAt) {
            recordedAt = DateParsing.parseDate(recordedAtString)
        } else {
            recordedAt = nil
        }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        localId = try container.decodeIfPresent(String.self, forKey: .localId)
        title = try container.decode(String.self, forKey: .title)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        transcriptPreview = try container.decodeIfPresent(String.self, forKey: .transcriptPreview)
        transcriptSize = try container.decode(Int.self, forKey: .transcriptSize)
        transcriptChecksum = try container.decodeIfPresent(String.self, forKey: .transcriptChecksum)
        duration = try container.decode(Double.self, forKey: .duration)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        tags = try container.decode([Tag].self, forKey: .tags)

        if let recordedAtString = try container.decodeIfPresent(String.self, forKey: .recordedAt) {
            recordedAt = DateParsing.parseDate(recordedAtString)
        } else {
            recordedAt = nil
        }

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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(localId, forKey: .localId)
        try container.encodeIfPresent(transcript, forKey: .transcript)
        try container.encodeIfPresent(transcriptChecksum, forKey: .transcriptChecksum)
        try container.encode(duration, forKey: .duration)
        if let recordedAt = recordedAt {
            try container.encode(DateParsing.formatDate(recordedAt), forKey: .recordedAt)
        }
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

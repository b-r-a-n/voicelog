import Foundation
import SwiftData

enum SyncStatus: String, Codable {
    case synced
    case pendingUpload
    case pendingUpdate
    case pendingDelete
    case conflict
}

@Model
final class CachedNote {
    @Attribute(.unique) var localId: String
    var serverId: Int?
    var title: String

    var transcriptPreview: String?
    var transcriptInline: String?  // For small transcripts
    var transcriptPath: String?     // For large transcripts (file path)
    var transcriptChecksum: String?
    var transcriptSize: Int

    var duration: Double
    var recordedAt: Date
    var summary: String?

    var syncStatus: String  // SyncStatus raw value
    var isDeleted: Bool
    var lastSyncedAt: Date?
    var serverUpdatedAt: Date?
    var createdAt: Date

    @Relationship(deleteRule: .nullify) var tags: [CachedTag]

    init(
        localId: String = UUID().uuidString,
        title: String,
        transcriptPreview: String? = nil,
        transcriptInline: String? = nil,
        transcriptChecksum: String? = nil,
        duration: Double = 0,
        recordedAt: Date = Date()
    ) {
        self.localId = localId
        self.title = title
        self.transcriptPreview = transcriptPreview
        self.transcriptInline = transcriptInline
        self.transcriptChecksum = transcriptChecksum
        self.transcriptSize = (transcriptInline?.utf8.count ?? 0)
        self.duration = duration
        self.recordedAt = recordedAt
        self.syncStatus = SyncStatus.pendingUpload.rawValue
        self.isDeleted = false
        self.createdAt = Date()
        self.tags = []
    }
}

extension CachedNote: Identifiable {
    var id: String { localId }
}

extension CachedNote {
    var syncStatusEnum: SyncStatus {
        get { SyncStatus(rawValue: syncStatus) ?? .pendingUpload }
        set { syncStatus = newValue.rawValue }
    }

    var transcript: String? {
        if let inline = transcriptInline {
            return inline
        }
        if let path = transcriptPath {
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
        return nil
    }
}

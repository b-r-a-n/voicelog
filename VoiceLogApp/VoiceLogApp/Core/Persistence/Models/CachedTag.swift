import Foundation
import SwiftData

@Model
final class CachedTag {
    @Attribute(.unique) var localId: String
    var serverId: Int?
    var name: String
    var color: String?
    var isDeleted: Bool
    var lastSyncedAt: Date?
    var serverUpdatedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \CachedNote.tags) var notes: [CachedNote]

    init(
        localId: String = UUID().uuidString,
        name: String,
        color: String? = nil
    ) {
        self.localId = localId
        self.name = name
        self.color = color
        self.isDeleted = false
        self.notes = []
    }
}

extension CachedTag: Identifiable {
    var id: String { localId }
}

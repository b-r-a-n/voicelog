import Foundation
import SwiftData

@Model
final class SyncMetadata {
    @Attribute(.unique) var key: String
    var lastSyncTimestamp: Date?
    var userId: Int?

    init(key: String) {
        self.key = key
    }
}

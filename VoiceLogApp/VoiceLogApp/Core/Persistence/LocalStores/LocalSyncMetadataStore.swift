import Foundation
import SwiftData

actor LocalSyncMetadataStore {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    func getLastSyncTimestamp(for key: String) throws -> Date? {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SyncMetadata>(
            predicate: #Predicate { $0.key == key }
        )
        return try context.fetch(descriptor).first?.lastSyncTimestamp
    }

    @MainActor
    func updateAfterSync(for key: String, timestamp: Date) throws {
        let context = container.mainContext
        let descriptor = FetchDescriptor<SyncMetadata>(
            predicate: #Predicate { $0.key == key }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.lastSyncTimestamp = timestamp
        } else {
            let metadata = SyncMetadata(key: key)
            metadata.lastSyncTimestamp = timestamp
            context.insert(metadata)
        }

        try context.save()
    }

    @MainActor
    func deleteAll() throws {
        let context = container.mainContext
        try context.delete(model: SyncMetadata.self)
        try context.save()
    }
}

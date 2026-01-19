import Foundation
import SwiftData

actor LocalTagStore {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    func save(_ tag: CachedTag) throws {
        let context = container.mainContext
        context.insert(tag)
        try context.save()
    }

    @MainActor
    func getAll(includeDeleted: Bool = false) throws -> [CachedTag] {
        let context = container.mainContext
        var descriptor = FetchDescriptor<CachedTag>(
            sortBy: [SortDescriptor(\.name)]
        )
        if !includeDeleted {
            descriptor.predicate = #Predicate { !$0.isDeleted }
        }
        return try context.fetch(descriptor)
    }

    @MainActor
    func getByServerId(_ serverId: Int) throws -> CachedTag? {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedTag>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        return try context.fetch(descriptor).first
    }

    @MainActor
    func update(_ tag: CachedTag) throws {
        let context = container.mainContext
        try context.save()
    }

    @MainActor
    func markDeleted(serverId: Int) throws {
        guard let tag = try getByServerId(serverId) else { return }
        tag.isDeleted = true
        try container.mainContext.save()
    }

    @MainActor
    func deleteAll() throws {
        let context = container.mainContext
        try context.delete(model: CachedTag.self)
        try context.save()
    }

    @MainActor
    func upsertFromServer(_ serverTag: TagSync) throws {
        let context = container.mainContext

        if let existing = try getByServerId(serverTag.id) {
            existing.name = serverTag.name
            existing.color = serverTag.color
            existing.isDeleted = serverTag.isDeleted
            existing.serverUpdatedAt = serverTag.updatedAt
            existing.lastSyncedAt = Date()
        } else {
            let tag = CachedTag(
                name: serverTag.name,
                color: serverTag.color
            )
            tag.serverId = serverTag.id
            tag.isDeleted = serverTag.isDeleted
            tag.serverUpdatedAt = serverTag.updatedAt
            tag.lastSyncedAt = Date()
            context.insert(tag)
        }

        try context.save()
    }
}

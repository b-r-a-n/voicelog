import Foundation
import SwiftData

actor LocalNoteStore {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    func save(_ note: CachedNote) throws {
        let context = container.mainContext
        context.insert(note)
        try context.save()
    }

    @MainActor
    func getAll(includeDeleted: Bool = false) throws -> [CachedNote] {
        let context = container.mainContext
        var descriptor = FetchDescriptor<CachedNote>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        if !includeDeleted {
            descriptor.predicate = #Predicate { !$0.isDeleted }
        }
        return try context.fetch(descriptor)
    }

    @MainActor
    func getByLocalId(_ localId: String) throws -> CachedNote? {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedNote>(
            predicate: #Predicate { $0.localId == localId }
        )
        return try context.fetch(descriptor).first
    }

    @MainActor
    func getByServerId(_ serverId: Int) throws -> CachedNote? {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedNote>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        return try context.fetch(descriptor).first
    }

    @MainActor
    func getPendingChanges() throws -> [CachedNote] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedNote>(
            predicate: #Predicate {
                $0.syncStatus != "synced"
            }
        )
        return try context.fetch(descriptor)
    }

    @MainActor
    func update(_ note: CachedNote) throws {
        let context = container.mainContext
        try context.save()
    }

    @MainActor
    func markDeleted(_ localId: String) throws {
        guard let note = try getByLocalId(localId) else { return }
        note.isDeleted = true
        note.syncStatusEnum = .pendingDelete
        try container.mainContext.save()
    }

    @MainActor
    func deleteAll() throws {
        let context = container.mainContext
        try context.delete(model: CachedNote.self)
        try context.save()
    }

    @MainActor
    func upsertFromServer(_ serverNote: NoteSync) throws {
        let context = container.mainContext

        if let existing = try getByServerId(serverNote.id) {
            // Update existing
            existing.title = serverNote.title
            existing.transcriptPreview = serverNote.transcriptPreview
            existing.transcriptChecksum = serverNote.transcriptChecksum
            existing.transcriptSize = serverNote.transcriptSize
            existing.duration = serverNote.duration
            existing.recordedAt = serverNote.recordedAt ?? existing.recordedAt
            existing.summary = serverNote.summary
            existing.isDeleted = serverNote.isDeleted
            existing.serverUpdatedAt = serverNote.updatedAt
            existing.lastSyncedAt = Date()
            existing.syncStatusEnum = .synced
        } else if let existing = try getByLocalId(serverNote.localId ?? "") {
            // Link local note to server
            existing.serverId = serverNote.id
            existing.title = serverNote.title
            existing.transcriptPreview = serverNote.transcriptPreview
            existing.transcriptChecksum = serverNote.transcriptChecksum
            existing.transcriptSize = serverNote.transcriptSize
            existing.duration = serverNote.duration
            existing.summary = serverNote.summary
            existing.isDeleted = serverNote.isDeleted
            existing.serverUpdatedAt = serverNote.updatedAt
            existing.lastSyncedAt = Date()
            existing.syncStatusEnum = .synced
        } else {
            // Create new from server
            let note = CachedNote(
                localId: serverNote.localId ?? UUID().uuidString,
                title: serverNote.title,
                transcriptPreview: serverNote.transcriptPreview,
                transcriptChecksum: serverNote.transcriptChecksum,
                duration: serverNote.duration,
                recordedAt: serverNote.recordedAt ?? Date()
            )
            note.serverId = serverNote.id
            note.transcriptSize = serverNote.transcriptSize
            note.summary = serverNote.summary
            note.isDeleted = serverNote.isDeleted
            note.serverUpdatedAt = serverNote.updatedAt
            note.lastSyncedAt = Date()
            note.syncStatusEnum = .synced
            context.insert(note)
        }

        try context.save()
    }
}

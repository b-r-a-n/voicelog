import Foundation
import SwiftData

actor SyncManager {
    @MainActor static var shared: SyncManager = SyncManager(
        container: PersistenceController.shared.container
    )

    private var isSyncing = false
    private let minSyncInterval: TimeInterval = 30
    private var lastSyncAttempt: Date?

    private let apiClient: APIClient
    private let container: ModelContainer

    init(
        apiClient: APIClient = .shared,
        container: ModelContainer
    ) {
        self.apiClient = apiClient
        self.container = container
    }

    func syncIfNeeded() async throws {
        guard !isSyncing else { return }

        if let lastAttempt = lastSyncAttempt,
           Date().timeIntervalSince(lastAttempt) < minSyncInterval {
            return
        }

        try await performSync()
    }

    func forceSync() async throws {
        guard !isSyncing else { return }
        try await performSync()
    }

    private func performSync() async throws {
        isSyncing = true
        lastSyncAttempt = Date()
        defer { isSyncing = false }

        let metadataStore = LocalSyncMetadataStore(container: container)
        let noteStore = LocalNoteStore(container: container)
        let tagStore = LocalTagStore(container: container)

        // Get last sync timestamp
        let lastSync = try await metadataStore.getLastSyncTimestamp(for: "all")

        // Get pending local changes
        let pendingNotes = try await noteStore.getPendingChanges()

        // Build sync request
        let noteChanges = pendingNotes.map { note in
            ClientNoteChange(
                localId: note.localId,
                title: note.title,
                transcript: note.transcript,
                transcriptChecksum: note.transcriptChecksum,
                transcriptPreview: note.transcriptPreview,
                duration: note.duration,
                recordedAt: note.recordedAt,
                isDeleted: note.isDeleted,
                tagIds: note.tags.compactMap { $0.serverId }
            )
        }

        let syncRequest = SyncRequest(
            since: lastSync,
            notes: noteChanges,
            tags: []
        )

        // Send to server
        let response: SyncResponse = try await apiClient.request(
            endpoint: .sync,
            body: syncRequest,
            responseType: SyncResponse.self
        )

        // Apply server changes
        try await applySync(response, noteStore: noteStore, tagStore: tagStore)

        // Update sync metadata
        try await metadataStore.updateAfterSync(for: "all", timestamp: response.syncTimestamp)
    }

    private func applySync(
        _ response: SyncResponse,
        noteStore: LocalNoteStore,
        tagStore: LocalTagStore
    ) async throws {
        // Update tags first (notes may reference them)
        for tag in response.tags {
            if tag.isDeleted {
                try await tagStore.markDeleted(serverId: tag.id)
            } else {
                try await tagStore.upsertFromServer(tag)
            }
        }

        // Update notes
        for note in response.notes {
            try await noteStore.upsertFromServer(note)
        }
    }

    func clearAllData() async throws {
        let noteStore = LocalNoteStore(container: container)
        let tagStore = LocalTagStore(container: container)
        let metadataStore = LocalSyncMetadataStore(container: container)

        try await noteStore.deleteAll()
        try await tagStore.deleteAll()
        try await metadataStore.deleteAll()
    }
}

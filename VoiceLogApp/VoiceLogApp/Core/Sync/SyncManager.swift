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

    // Retry configuration
    private let maxRetryAttempts = 3
    private let baseRetryDelay: TimeInterval = 1.0  // 1 second

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

        // Send to server with retry logic for transient failures
        let response: SyncResponse = try await performSyncRequestWithRetry(syncRequest)

        // Apply server changes
        try await applySync(response, noteStore: noteStore, tagStore: tagStore)

        // Update sync metadata
        try await metadataStore.updateAfterSync(for: "all", timestamp: response.syncTimestamp)
    }

    /// Performs sync request with exponential backoff retry for transient failures
    private func performSyncRequestWithRetry(_ syncRequest: SyncRequest) async throws -> SyncResponse {
        var lastError: Error?

        for attempt in 0..<maxRetryAttempts {
            do {
                return try await apiClient.request(
                    endpoint: .sync,
                    body: syncRequest,
                    responseType: SyncResponse.self
                )
            } catch {
                // Don't retry client errors (4xx) - these won't succeed on retry
                if !isRetryableError(error) {
                    throw error
                }

                lastError = error

                // Don't delay after the last attempt
                if attempt < maxRetryAttempts - 1 {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))  // 1s, 2s, 4s
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // If we exhausted all retries, throw the last error
        throw lastError ?? APIError.unknown
    }

    /// Determines if an error is transient and should be retried
    private func isRetryableError(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else {
            // Unknown errors could be network-related, so retry
            return true
        }

        switch apiError {
        case .serverError, .networkError, .unknown:
            // Server errors (5xx) and network errors are transient
            return true
        case .unauthorized, .badRequest, .forbidden, .notFound,
             .decodingFailed, .encodingFailed, .tokenRefreshFailed:
            // Client errors (4xx) and encoding/decoding errors won't improve on retry
            return false
        }
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

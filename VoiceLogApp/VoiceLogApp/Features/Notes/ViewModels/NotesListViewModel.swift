import Foundation
import SwiftUI
import SwiftData

@MainActor
final class NotesListViewModel: ObservableObject {
    @Published private(set) var notes: [CachedNote] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published var error: Error?

    private let container: PersistenceController

    init(container: PersistenceController = .shared) {
        self.container = container
    }

    func loadNotes() async {
        isLoading = true
        defer { isLoading = false }

        let noteStore = LocalNoteStore(container: container.container)

        do {
            notes = try await noteStore.getAll()
        } catch {
            self.error = error
        }
    }

    func syncNotes() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await SyncManager.shared.forceSync()
            await loadNotes()
        } catch {
            self.error = error
        }
    }

    func deleteNote(_ note: CachedNote) async {
        let noteStore = LocalNoteStore(container: container.container)

        do {
            try await noteStore.markDeleted(note.localId)
            await loadNotes()

            // Trigger sync
            Task {
                try? await SyncManager.shared.syncIfNeeded()
            }
        } catch {
            self.error = error
        }
    }
}

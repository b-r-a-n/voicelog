import Foundation
import SwiftUI

@MainActor
final class NoteDetailViewModel: ObservableObject {
    @Published private(set) var note: CachedNote
    @Published private(set) var isSummarizing = false
    @Published private(set) var isExporting = false
    @Published var error: Error?
    @Published var exportStatus: ExportStatus?

    private let apiClient: APIClient
    private let container: PersistenceController

    init(
        note: CachedNote,
        apiClient: APIClient = .shared,
        container: PersistenceController = .shared
    ) {
        self.note = note
        self.apiClient = apiClient
        self.container = container
    }

    var transcript: String {
        note.transcript ?? note.transcriptPreview ?? ""
    }

    func summarize() async {
        guard let serverId = note.serverId else {
            error = NSError(domain: "", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Note must be synced before summarizing"
            ])
            return
        }

        isSummarizing = true
        defer { isSummarizing = false }

        do {
            let detail: NoteDetail = try await apiClient.request(
                endpoint: .summarizeNote(id: serverId),
                body: NoteSummarize(prompt: nil),
                responseType: NoteDetail.self
            )

            note.summary = detail.summary

            let noteStore = LocalNoteStore(container: container.container)
            try await noteStore.update(note)
        } catch {
            self.error = error
        }
    }

    func exportToPDF() async {
        await export(format: "pdf")
    }

    func exportToMarkdown() async {
        await export(format: "markdown")
    }

    private func export(format: String) async {
        guard let serverId = note.serverId else {
            error = NSError(domain: "", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Note must be synced before exporting"
            ])
            return
        }

        isExporting = true
        defer { isExporting = false }

        do {
            let status: ExportStatus = try await apiClient.request(
                endpoint: .exportNote(id: serverId),
                body: NoteExport(format: format),
                responseType: ExportStatus.self
            )

            exportStatus = status
        } catch {
            self.error = error
        }
    }
}

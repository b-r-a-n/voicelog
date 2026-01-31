import Foundation
import SwiftUI

@MainActor
final class NoteDetailViewModel: ObservableObject {
    @Published private(set) var note: CachedNote
    @Published private(set) var isSummarizing = false
    @Published private(set) var isExporting = false
    @Published var error: Error?
    @Published var exportStatus: ExportStatus?
    @Published var exportedFileURL: URL?

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
            // Step 1: Request export from server
            let status: ExportStatus = try await apiClient.request(
                endpoint: .exportNote(id: serverId),
                body: NoteExport(format: format),
                responseType: ExportStatus.self
            )

            exportStatus = status

            // Step 2: Download the exported file
            let (fileData, _) = try await apiClient.downloadFile(
                endpoint: .downloadExport(exportId: status.exportId)
            )

            // Step 3: Save to temp directory with sanitized filename
            let fileExtension = format == "pdf" ? "pdf" : "md"
            let sanitizedTitle = sanitizeFilename(note.title ?? "Export")
            let filename = "\(sanitizedTitle).\(fileExtension)"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            try fileData.write(to: tempURL)
            exportedFileURL = tempURL
        } catch {
            self.error = error
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        // Remove characters that are invalid in filenames
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")

        // Trim whitespace and limit length
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }

        // Fallback to default name if empty
        return sanitized.isEmpty ? "Export" : sanitized
    }
}

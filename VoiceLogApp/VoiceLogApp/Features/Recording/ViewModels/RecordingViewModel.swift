import Foundation
import SwiftUI
import CryptoKit

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var title = ""
    @Published var isRecording = false
    @Published var currentTranscript = ""
    @Published var recordingDuration: TimeInterval = 0
    @Published var error: Error?
    @Published var isSaving = false
    @Published var didSave = false

    private let speechService: SpeechService
    private let container: PersistenceController

    init(
        speechService: SpeechService = .shared,
        container: PersistenceController = .shared
    ) {
        self.speechService = speechService
        self.container = container
    }

    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var canSave: Bool {
        !currentTranscript.isEmpty && !title.isEmpty
    }

    func startRecording() async {
        do {
            try await speechService.startRecording()
            isRecording = true

            // Observe speech service updates
            Task {
                for await _ in Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().values {
                    if !self.isRecording { break }
                    self.currentTranscript = self.speechService.currentTranscript
                    self.recordingDuration = self.speechService.recordingDuration
                }
            }
        } catch {
            self.error = error
        }
    }

    func stopRecording() async {
        do {
            let result = try await speechService.stopRecording()
            isRecording = false
            currentTranscript = result.transcript
            recordingDuration = result.duration

            // Generate default title if empty
            if title.isEmpty {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                title = "Note - \(formatter.string(from: Date()))"
            }
        } catch {
            self.error = error
        }
    }

    func cancelRecording() {
        speechService.cancelRecording()
        isRecording = false
        currentTranscript = ""
        recordingDuration = 0
    }

    func saveNote() async {
        guard canSave else { return }

        isSaving = true
        defer { isSaving = false }

        let checksum = computeChecksum(currentTranscript)
        let preview = String(currentTranscript.prefix(500))

        let note = CachedNote(
            title: title,
            transcriptPreview: preview,
            transcriptInline: currentTranscript,
            transcriptChecksum: checksum,
            duration: recordingDuration,
            recordedAt: Date()
        )

        let noteStore = LocalNoteStore(container: container.container)

        do {
            try await noteStore.save(note)
            didSave = true

            // Trigger sync in background
            Task {
                try? await SyncManager.shared.syncIfNeeded()
            }
        } catch {
            self.error = error
        }
    }

    private func computeChecksum(_ content: String) -> String {
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func reset() {
        title = ""
        currentTranscript = ""
        recordingDuration = 0
        error = nil
        didSave = false
    }
}

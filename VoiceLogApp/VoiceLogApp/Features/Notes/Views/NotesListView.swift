import SwiftUI

struct NotesListView: View {
    @StateObject private var viewModel = NotesListViewModel()
    @State private var showRecording = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.notes.isEmpty {
                    ProgressView()
                } else if viewModel.notes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "doc.text",
                        description: Text("Tap the + button to create your first voice note")
                    )
                } else {
                    List {
                        ForEach(viewModel.notes) { note in
                            NavigationLink(value: note) {
                                NoteRowView(note: note)
                            }
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    await viewModel.deleteNote(viewModel.notes[index])
                                }
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.syncNotes()
                    }
                }
            }
            .navigationTitle("Notes")
            .navigationDestination(for: CachedNote.self) { note in
                NoteDetailView(note: note)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showRecording = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                if viewModel.isSyncing {
                    ToolbarItem(placement: .status) {
                        ProgressView()
                    }
                }
            }
            .sheet(isPresented: $showRecording) {
                RecordingView()
            }
            .onChange(of: showRecording) { _, isShowing in
                if !isShowing {
                    Task {
                        await viewModel.loadNotes()
                    }
                }
            }
            .task {
                await viewModel.loadNotes()
            }
        }
    }
}

struct NoteRowView: View {
    let note: CachedNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if note.syncStatusEnum != .synced {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let preview = note.transcriptPreview {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Text(note.recordedAt, style: .date)
                Text(formatDuration(note.duration))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NotesListView()
}

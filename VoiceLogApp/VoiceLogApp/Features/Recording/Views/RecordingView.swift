import SwiftUI

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Duration display
                Text(viewModel.formattedDuration)
                    .font(.system(size: 64, weight: .thin, design: .monospaced))
                    .foregroundStyle(viewModel.isRecording ? .red : .primary)
                    .accessibilityIdentifier("recording_duration")

                // Transcript preview
                ScrollView {
                    Text(viewModel.currentTranscript.isEmpty
                         ? "Tap the microphone to start recording..."
                         : viewModel.currentTranscript)
                        .font(.body)
                        .foregroundStyle(viewModel.currentTranscript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .accessibilityIdentifier("recording_transcript_preview")
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Recording controls
                HStack(spacing: 40) {
                    if viewModel.isRecording {
                        Button {
                            viewModel.cancelRecording()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.gray)
                        }
                        .accessibilityIdentifier("cancel_button")

                        Button {
                            Task {
                                await viewModel.stopRecording()
                            }
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.red)
                        }
                        .accessibilityIdentifier("stop_button")
                    } else {
                        Button {
                            Task {
                                await viewModel.startRecording()
                            }
                        } label: {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.blue)
                        }
                        .accessibilityIdentifier("record_button")
                    }
                }
                .padding(.vertical)

                // Title field (shown after recording)
                if !viewModel.isRecording && !viewModel.currentTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(.headline)

                        TextField("Note title", text: $viewModel.title)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("note_title_field")
                    }

                    Button {
                        Task {
                            await viewModel.saveNote()
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Save Note")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSave || viewModel.isSaving)
                    .accessibilityIdentifier("save_note_button")
                }
            }
            .padding()
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelRecording()
                        dismiss()
                    }
                    .accessibilityIdentifier("recording_cancel_button")
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                }
            }
            .onChange(of: viewModel.didSave) { _, didSave in
                if didSave {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    RecordingView()
}

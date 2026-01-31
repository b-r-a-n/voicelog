import SwiftUI

struct NoteDetailView: View {
    @StateObject private var viewModel: NoteDetailViewModel

    init(note: CachedNote) {
        _viewModel = StateObject(wrappedValue: NoteDetailViewModel(note: note))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Metadata
                HStack {
                    Label(viewModel.note.recordedAt.formatted(date: .abbreviated, time: .shortened),
                          systemImage: "calendar")

                    Spacer()

                    Label(formatDuration(viewModel.note.duration),
                          systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Divider()

                // Summary section
                if let summary = viewModel.note.summary {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.headline)

                        Text(summary)
                            .font(.body)
                            .accessibilityIdentifier("note_detail_summary")
                    }

                    Divider()
                }

                // Transcript section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript")
                        .font(.headline)

                    Text(viewModel.transcript)
                        .font(.body)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("note_detail_transcript")
                }

                // Tags
                if !viewModel.note.tags.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags")
                            .font(.headline)

                        FlowLayout(spacing: 8) {
                            ForEach(viewModel.note.tags) { tag in
                                TagChip(tag: tag)
                                    .accessibilityIdentifier("tag_chip_\(tag.id)")
                            }
                        }
                        .accessibilityIdentifier("note_detail_tags")
                    }
                    .accessibilityIdentifier("note_detail_tags_section")
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task {
                            await viewModel.summarize()
                        }
                    } label: {
                        Label("Generate Summary", systemImage: "sparkles")
                    }
                    .disabled(viewModel.isSummarizing)
                    .accessibilityIdentifier("generate_summary_button")

                    Divider()

                    Button {
                        Task {
                            await viewModel.exportToPDF()
                        }
                    } label: {
                        Label("Export as PDF", systemImage: "doc.fill")
                    }
                    .disabled(viewModel.isExporting)

                    Button {
                        Task {
                            await viewModel.exportToMarkdown()
                        }
                    } label: {
                        Label("Export as Markdown", systemImage: "doc.plaintext")
                    }
                    .disabled(viewModel.isExporting)
                } label: {
                    if viewModel.isSummarizing || viewModel.isExporting {
                        ProgressView()
                            .accessibilityIdentifier("note_detail_loading")
                    } else {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityIdentifier("note_detail_menu_button")
                    }
                }
                .accessibilityIdentifier("note_detail_menu")
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
        .sheet(isPresented: .init(
            get: { viewModel.exportedFileURL != nil },
            set: { if !$0 { viewModel.exportedFileURL = nil } }
        )) {
            if let url = viewModel.exportedFileURL {
                ActivityView(activityItems: [url])
                    .accessibilityIdentifier("export_share_sheet")
            }
        }
    }

    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct TagChip: View {
    let tag: CachedTag

    var body: some View {
        Text(tag.name)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tagColor.opacity(0.2))
            .foregroundStyle(tagColor)
            .clipShape(Capsule())
    }

    private var tagColor: Color {
        if let hex = tag.color {
            return Color(hex: hex)
        }
        return .blue
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                self.size.width = max(self.size.width, currentX)
            }

            self.size.height = currentY + lineHeight
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    NavigationStack {
        NoteDetailView(note: CachedNote(
            title: "Test Note",
            transcriptPreview: "This is a test transcript preview...",
            transcriptInline: "This is a test transcript. It contains multiple sentences and some content.",
            duration: 125,
            recordedAt: Date()
        ))
    }
}

import SwiftUI

struct NotesListView: View {
    @Environment(NotesController.self) private var controller
    @State private var path: [UUID] = []
    @State private var query = ""

    private var filtered: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let notes = controller.sortedNotes.filter { !$0.isEmpty || path.contains($0.id) }
        guard !q.isEmpty else { return notes }
        return notes.filter { $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filtered) { note in
                    NavigationLink(value: note.id) {
                        NoteRow(note: note)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { controller.delete(note.id) }
                    }
                    .contextMenu {
                        Button("Copy All", systemImage: "doc.on.doc") { controller.copy(note) }
                        Button("Delete", systemImage: "trash", role: .destructive) { controller.delete(note.id) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search Notes")
            .overlay {
                if controller.notes.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "note.text")
                    } description: {
                        Text("Tap New Note below. You can also ask in Talk: “what's on my packing note?”")
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Notes")
            .navigationDestination(for: UUID.self) { id in
                NoteEditorView(noteID: id)
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionButton(title: "New Note", systemImage: "square.and.pencil") {
                    path.append(controller.add().id)
                }
            }
            .animation(.snappy, value: controller.notes)
            .task(id: AppNavigation.shared.pendingNoteID) {
                // Opened from a chat event: show that note.
                guard let id = AppNavigation.shared.pendingNoteID else { return }
                AppNavigation.shared.pendingNoteID = nil
                if controller.note(id) != nil { path = [id] }
            }
        }
        .tint(.orange)
    }
}

private struct NoteRow: View {
    @Environment(NotesController.self) private var controller
    let note: Note
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(note.updatedAt.formatted(.relative(presentation: .named)))
                        .foregroundStyle(.secondary)
                    if !note.preview.isEmpty {
                        Text(note.preview)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            CopyButton(copied: $copied) { controller.copy(note) }
        }
        .padding(.vertical, 2)
    }
}

/// A copy icon that briefly turns into a checkmark.
struct CopyButton: View {
    @Binding var copied: Bool
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            action()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            if let label {
                Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
            } else {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.body.weight(.medium))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.orange.opacity(0.12)))
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.orange)
        .contentTransition(.symbolEffect(.replace))
        .sensoryFeedback(.success, trigger: copied) { _, now in now }
        .accessibilityLabel(copied ? "Copied" : "Copy All")
    }
}

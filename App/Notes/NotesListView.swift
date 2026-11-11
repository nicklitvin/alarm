import SwiftUI

struct NotesListView: View {
    @Environment(NotesController.self) private var controller
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var editMode: EditMode = .inactive

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canReorder: Bool { controller.sort == .manual && !isSearching }

    private var visible: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let notes = controller.sortedNotes.filter { !$0.isEmpty || path.contains($0.id) }
        guard !q.isEmpty else { return notes }
        return notes.filter { $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            let pinned = visible.filter(\.isPinned)
            let others = visible.filter { !$0.isPinned }
            List {
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned) { row($0) }
                            .onMove(perform: canReorder ? { controller.move(in: pinned, from: $0, to: $1) } : nil)
                    }
                }
                Section {
                    ForEach(others) { row($0) }
                        .onMove(perform: canReorder ? { controller.move(in: others, from: $0, to: $1) } : nil)
                } header: {
                    if !pinned.isEmpty && !others.isEmpty { Text("Notes") }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, $editMode)
            .overlay {
                if controller.notes.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "note.text")
                    } description: {
                        Text("Tap New Note below. You can also ask in Talk: “what's on my packing note?”")
                    }
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Notes")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    TabHeader(title: "Notes", tab: .notes, detail: { _ in
                        controller.notes.isEmpty ? nil : "\(controller.notes.count) note\(controller.notes.count == 1 ? "" : "s")"
                    }) {
                        if canReorder && controller.notes.count > 1 {
                            Button(editMode.isEditing ? "Done" : "Reorder") {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                    SearchField(text: $query)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                        .background(Color(.systemGroupedBackground))
                }
            }
            .navigationDestination(for: UUID.self) { id in
                NoteEditorView(noteID: id)
            }
            .safeAreaInset(edge: .bottom) {
                if !editMode.isEditing {
                    BottomActionButton(title: "New Note", systemImage: "square.and.pencil") {
                        path.append(controller.add().id)
                    }
                }
            }
            .animation(.snappy, value: controller.notes)
            .onChange(of: canReorder) { _, can in if !can { editMode = .inactive } }
            .task(id: AppNavigation.shared.pendingNoteID) {
                // Opened from a chat event: show that note.
                guard let id = AppNavigation.shared.pendingNoteID else { return }
                AppNavigation.shared.pendingNoteID = nil
                if controller.note(id) != nil { path = [id] }
            }
        }
        .tint(.orange)
    }

    private func row(_ note: Note) -> some View {
        NavigationLink(value: note.id) {
            NoteRow(note: note)
        }
        .swipeActions(edge: .leading) {
            Button(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin") {
                controller.setPinned(!note.isPinned, for: note.id)
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { controller.delete(note.id) }
        }
        .contextMenu {
            Button("Copy All", systemImage: "doc.on.doc") { controller.copy(note) }
            Button(note.isPinned ? "Unpin" : "Pin to Top", systemImage: note.isPinned ? "pin.slash" : "pin") {
                controller.setPinned(!note.isPinned, for: note.id)
            }
            Button("Move to Top", systemImage: "arrow.up.to.line") { controller.moveToTop(note.id) }
            Button("Delete", systemImage: "trash", role: .destructive) { controller.delete(note.id) }
        }
    }
}

/// Rounded search field under the Notes title.
private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search Notes", text: $text)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

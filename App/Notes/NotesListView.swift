import SwiftUI

struct NotesListView: View {
    @Environment(NotesController.self) private var controller
    @State private var path: [UUID] = []
    @State private var query = ""

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

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
                // No empty header views: the list used to reserve header space on the first frame
                // and then collapse it, so the notes jumped up toward the search field.
                if pinned.isEmpty {
                    Section {
                        ForEach(others) { row($0) }
                    }
                } else {
                    Section("Pinned") {
                        ForEach(pinned) { row($0) }
                    }
                    if !others.isEmpty {
                        Section("Notes") {
                            ForEach(others) { row($0) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, 8, for: .scrollContent)
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
                    TabHeader(title: "Notes", tab: .notes) { _ in
                        controller.notes.isEmpty ? nil : "\(controller.notes.count) note\(controller.notes.count == 1 ? "" : "s")"
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
                BottomActionButton(title: "New Note", systemImage: "square.and.pencil") {
                    path.append(controller.add().id)
                }
            }
            // No list-wide animation: notes re-sort while you edit one, and animating that
            // on the way back made the edited note flicker into place.
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
                withAnimation(.snappy) { controller.setPinned(!note.isPinned, for: note.id) }
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { controller.delete(note.id) }
        }
        // Press and hold a note to pick it up, then drop it on another note to move it there.
        .draggable(note.id.uuidString) {
            NoteRow(note: note)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(width: 320)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .environment(controller)
        }
        .dropDestination(for: String.self) { items, _ in
            guard !isSearching, let id = items.first.flatMap(UUID.init(uuidString:)), id != note.id else { return false }
            withAnimation(.snappy) { controller.move(id, onto: note.id) }
            return true
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
                    if let progress = NoteChecklist.progress(of: note.body) {
                        // Notes with a checklist show how far along it is.
                        Label("\(progress.done)/\(progress.total)", systemImage: "checklist")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(progress.done == progress.total ? Color.orange : Color.secondary)
                    }
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

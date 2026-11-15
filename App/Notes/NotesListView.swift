import SwiftUI

struct NotesListView: View {
    @Environment(NotesController.self) private var controller
    @State private var path: [UUID] = []
    @State private var query = ""
    /// The note open beside the list (iPad and the Mac).
    @State private var selection: UUID?
    @State private var showRecentlyDeleted = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var visible: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let notes = controller.sortedNotes.filter { !$0.isEmpty || path.contains($0.id) || selection == $0.id }
        guard !q.isEmpty else { return notes }
        return notes.filter { $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad and the Mac: the notes on the left, the open note beside them.
                HStack(spacing: 0) {
                    notesColumn
                        .frame(width: 340)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(.systemGroupedBackground))
            } else {
                NavigationStack(path: $path) {
                    notesColumn
                        .navigationDestination(for: UUID.self) { id in
                            NoteEditorView(noteID: id)
                        }
                }
            }
        }
        .tint(.orange)
    }

    /// Opens a note: pushed on iPhone, shown beside the list on iPad and the Mac.
    private func open(_ id: UUID) {
        if horizontalSizeClass == .regular { selection = id } else { path = [id] }
    }

    /// The open note in the wide layout (each note gets a fresh editor).
    @ViewBuilder
    private var detail: some View {
        if let id = selection, controller.note(id) != nil {
            NavigationStack {
                NoteEditorView(noteID: id)
            }
            .id(id)
        } else {
            ContentUnavailableView("No Note Selected", systemImage: "note.text",
                                   description: Text("Pick a note, or make a new one."))
        }
    }

    @ViewBuilder
    private var notesColumn: some View {
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

            // Deleted notes wait here for 30 days.
            if !controller.deletedNotes.isEmpty {
                Section {
                    Button { showRecentlyDeleted = true } label: {
                        HStack {
                            Label("Recently Deleted", systemImage: "trash")
                            Spacer()
                            Text("\(controller.deletedNotes.count)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 8, for: .scrollContent)
        // The same light gray as the other tabs, empty space included.
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .overlay {
            Group {
                if controller.activeNotes.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "note.text")
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showRecentlyDeleted) {
            RecentlyDeletedView()
        }
        .navigationTitle("Notes")
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                TabHeader(title: "Notes", tab: .notes) { _ in
                    let count = controller.activeNotes.count
                    return count == 0 ? nil : "\(count) note\(count == 1 ? "" : "s")"
                }
                SearchField(text: $query)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    .background(Color(.systemGroupedBackground))
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionButton(title: "New Note", systemImage: "square.and.pencil") {
                open(controller.add().id)
            }
        }
        // No list-wide animation: notes re-sort while you edit one, and animating that
        // on the way back made the edited note flicker into place.
        .task(id: AppNavigation.shared.pendingNoteID) {
            // Opened from a chat event: show that note.
            guard let id = AppNavigation.shared.pendingNoteID else { return }
            AppNavigation.shared.pendingNoteID = nil
            if controller.note(id) != nil { open(id) }
        }
        .task(id: AppNavigation.shared.pendingNewNote) {
            // The widget's note button: a new note, ready to type.
            guard AppNavigation.shared.pendingNewNote else { return }
            AppNavigation.shared.pendingNewNote = false
            open(controller.add().id)
        }
    }

    private func row(_ note: Note) -> some View {
        Group {
            if horizontalSizeClass == .regular {
                // Wide layout: tapping shows the note beside the list; the open one is highlighted.
                Button { selection = note.id } label: {
                    NoteRow(note: note)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(selection == note.id ? Color.orange.opacity(0.18) : nil)
            } else {
                NavigationLink(value: note.id) {
                    NoteRow(note: note)
                }
            }
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
    let note: Note

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
        }
        .padding(.vertical, 2)
    }
}

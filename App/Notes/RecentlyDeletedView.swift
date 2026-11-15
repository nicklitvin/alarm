import SwiftUI

/// Notes you deleted, kept for 30 days: recover them or delete them for good.
struct RecentlyDeletedView: View {
    @Environment(NotesController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Note?
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(controller.deletedNotes) { note in
                        Button { chosen = note } label: { row(note) }
                            .foregroundStyle(.primary)
                            .swipeActions(edge: .leading) {
                                Button("Recover", systemImage: "arrow.uturn.backward") { recover(note) }
                                    .tint(.orange)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) { controller.deletePermanently(note.id) }
                                    .tint(.red)
                            }
                    }
                } footer: {
                    Text("Notes are removed for good \(NotesTrash.keepDays) days after you delete them. Tap one to recover it.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .overlay {
                if controller.deletedNotes.isEmpty {
                    ContentUnavailableView("No Recently Deleted Notes", systemImage: "trash")
                }
            }
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if !controller.deletedNotes.isEmpty {
                    HStack(spacing: 10) {
                        Button { withAnimation { controller.recoverAll() }; dismiss() } label: {
                            Text("Recover All").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        Button(role: .destructive) { confirmDeleteAll = true } label: {
                            Text("Delete All").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .frame(maxWidth: 400)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .alert(chosen.map { "Recover “\($0.displayTitle)”?" } ?? "", isPresented: Binding(
                get: { chosen != nil }, set: { if !$0 { chosen = nil } }
            ), presenting: chosen) { note in
                Button("Recover") { recover(note) }
                Button("Delete Permanently", role: .destructive) { controller.deletePermanently(note.id) }
                Button("Cancel", role: .cancel) {}
            } message: { note in
                Text("It goes back to your notes. Otherwise it's removed in \(NotesTrash.daysLeft(note)) day\(NotesTrash.daysLeft(note) == 1 ? "" : "s").")
            }
            .alert("Delete all recently deleted notes?", isPresented: $confirmDeleteAll) {
                Button("Delete All", role: .destructive) { withAnimation { controller.emptyRecentlyDeleted() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
        .tint(.orange)
    }

    private func row(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.displayTitle)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                let days = NotesTrash.daysLeft(note)
                Text("\(days) day\(days == 1 ? "" : "s") left")
                    .foregroundStyle(.secondary)
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func recover(_ note: Note) {
        withAnimation { controller.recover(note.id) }
    }
}

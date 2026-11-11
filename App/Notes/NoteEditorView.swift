import SwiftUI
import UIKit

/// Full-screen note editor. Saves as you type; an empty note is discarded when you leave.
struct NoteEditorView: View {
    @Environment(NotesController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID

    @State private var title = ""
    @State private var text = ""
    @State private var loaded = false
    @State private var copied = false
    @FocusState private var focus: Field?

    private enum Field { case title, body }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title.weight(.bold))
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = .body }

                if let note = controller.note(noteID) {
                    Text("Edited \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Start writing…", text: $text, axis: .vertical)
                    .font(.body)
                    .focused($focus, equals: .body)
                    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CopyButton(copied: $copied, label: "Copy All") {
                    UIPasteboard.general.string = Note(title: title, body: text).copyText
                }
                .labelStyle(.titleAndIcon)
                .disabled(title.isEmpty && text.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete Note", systemImage: "trash", role: .destructive) {
                        controller.delete(noteID)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }.fontWeight(.semibold)
            }
        }
        .onAppear(perform: load)
        .onChange(of: title) { save() }
        .onChange(of: text) { save() }
        .onDisappear {
            if let note = controller.note(noteID), note.isEmpty { controller.delete(noteID) }
        }
    }

    private func load() {
        guard !loaded, let note = controller.note(noteID) else { return }
        title = note.title
        text = note.body
        loaded = true
        if note.isEmpty { focus = .title }
    }

    private func save() {
        guard loaded, var note = controller.note(noteID) else { return }
        note.title = title
        note.body = text
        controller.update(note)
    }
}

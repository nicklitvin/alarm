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
    @State private var confirmDelete = false
    @State private var confirmClear = false
    @FocusState private var focus: Field?

    private enum Field { case title, body }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $title, axis: .vertical)
                .font(.title.weight(.bold))
                .focused($focus, equals: .title)
                .submitLabel(.next)
                .onSubmit { focus = .body }

            // A real text editor: it fills the rest of the screen (tap anywhere below the text to
            // keep writing), scrolls to follow the cursor, and leaves room at the bottom so the
            // keyboard's Done bar never covers the last lines.
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Start writing…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.body)
                    .focused($focus, equals: .body)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, 120, for: .scrollContent)
                    .scrollDismissesKeyboard(.interactively)
                    .padding(.leading, -5) // the editor's built-in inset, so text lines up with the title
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Copy All, Clear and Delete as plain icons.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = Note(title: title, body: text).copyText
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .sensoryFeedback(.success, trigger: copied) { _, now in now }
                .accessibilityLabel(copied ? "Copied" : "Copy All")
                .disabled(title.isEmpty && text.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    confirmClear = true
                } label: {
                    Image(systemName: "eraser")
                }
                .accessibilityLabel("Clear Note")
                .disabled(text.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete Note")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }.fontWeight(.semibold)
            }
        }
        // Alerts (centered, no popover arrow) to confirm Clear and Delete.
        .alert("Clear this note?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { text = "" }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything you wrote is removed. The title stays.")
        }
        .alert("Delete this note?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                controller.delete(noteID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
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

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class NotesController {
    static let shared = NotesController()

    private(set) var notes: [Note]

    private init() {
        notes = NoteStorage.load()
    }

    /// Most recently edited first.
    var sortedNotes: [Note] { notes.sorted { $0.updatedAt > $1.updatedAt } }

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    @discardableResult
    func add(title: String = "", body: String = "") -> Note {
        let note = Note(title: title, body: body)
        notes.append(note)
        save()
        return note
    }

    func update(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }), notes[index] != note else { return }
        var note = note
        note.updatedAt = Date()
        notes[index] = note
        save()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    /// Copies the whole note (title and text) to the clipboard.
    func copy(_ note: Note) {
        UIPasteboard.general.string = note.copyText
    }

    private func save() {
        NoteStorage.save(notes)
    }
}

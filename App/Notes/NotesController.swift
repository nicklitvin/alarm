import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class NotesController {
    static let shared = NotesController()

    private(set) var notes: [Note]
    /// The order chosen in Notes settings.
    private(set) var sort: NotesSort

    private init() {
        notes = NoteStorage.load()
        // An old "Manual" choice no longer exists: it falls back to Date Edited.
        sort = NotesSort(rawValue: AppSettings.store.string(forKey: AppSettings.notesSortKey) ?? "") ?? .edited
    }

    /// In the chosen order, pinned first.
    var sortedNotes: [Note] { sort.sorted(notes) }

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

    /// Settings → Delete All Notes.
    func deleteAll() {
        notes.removeAll()
        save()
    }

    func setPinned(_ pinned: Bool, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned = pinned
        save()
    }

    func setSort(_ newSort: NotesSort) {
        guard newSort != sort else { return }
        sort = newSort
        AppSettings.store.set(newSort.rawValue, forKey: AppSettings.notesSortKey)
    }

    /// Copies the whole note (title and text) to the clipboard.
    func copy(_ note: Note) {
        UIPasteboard.general.string = note.copyText
    }

    private func save() {
        NoteStorage.save(notes)
    }
}

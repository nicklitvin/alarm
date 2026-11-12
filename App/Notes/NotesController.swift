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
        sort = NotesSort(rawValue: AppSettings.store.string(forKey: AppSettings.notesSortKey) ?? "") ?? .edited
    }

    /// In the chosen order, pinned first.
    var sortedNotes: [Note] { sort.sorted(notes) }

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    @discardableResult
    func add(title: String = "", body: String = "") -> Note {
        // New notes go to the top of the Manual order.
        let top = (notes.map(\.sortIndex).min() ?? 0) - 1
        let note = Note(title: title, body: body, sortIndex: top)
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

    /// Press-and-hold drag: drop `id` onto `target`. Switches the list to Manual order.
    func move(_ id: UUID, onto target: UUID) {
        let previousSort = sort
        notes = notes.reordered(moving: id, onto: target, currentSort: previousSort)
        if previousSort != .manual {
            sort = .manual
            AppSettings.store.set(NotesSort.manual.rawValue, forKey: AppSettings.notesSortKey)
        }
        save()
    }

    func setSort(_ newSort: NotesSort) {
        guard newSort != sort else { return }
        // Make the Manual order start from whatever is on screen now.
        if newSort == .manual {
            for (offset, note) in sort.sorted(notes).enumerated() {
                if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index].sortIndex = Double(offset) }
            }
        }
        sort = newSort
        AppSettings.store.set(newSort.rawValue, forKey: AppSettings.notesSortKey)
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

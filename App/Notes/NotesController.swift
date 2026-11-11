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

    func setPinned(_ pinned: Bool, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned = pinned
        save()
    }

    /// Moves a note to the top of the Manual order (switching to Manual if needed).
    func moveToTop(_ id: UUID) {
        if sort != .manual { setSort(.manual) }
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].sortIndex = (notes.map(\.sortIndex).min() ?? 0) - 1
        save()
    }

    /// Drag-to-rearrange within a section (pinned or not) of the Manual order.
    func move(in section: [Note], from source: IndexSet, to destination: Int) {
        var reordered = section
        reordered.move(fromOffsets: source, toOffset: destination)
        let base = (notes.map(\.sortIndex).min() ?? 0) - Double(notes.count) - 1
        for (offset, note) in reordered.enumerated() {
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index].sortIndex = base + Double(offset)
            }
        }
        // Keep the other section's notes after these, in their current order.
        let others = sort.sorted(notes).filter { note in !reordered.contains { $0.id == note.id } }
        for (offset, note) in others.enumerated() {
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index].sortIndex = base + Double(reordered.count + offset)
            }
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

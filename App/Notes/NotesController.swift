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
        let stored = NoteStorage.load()
        notes = NotesTrash.purged(stored)
        if notes.count != stored.count { NoteStorage.save(notes) }
        // An old "Manual" choice no longer exists: it falls back to Date Edited.
        sort = NotesSort(rawValue: AppSettings.store.string(forKey: AppSettings.notesSortKey) ?? "") ?? .edited
    }

    /// Notes that aren't deleted.
    var activeNotes: [Note] { notes.filter { !$0.isDeleted } }

    /// In the chosen order, pinned first (deleted notes left out).
    var sortedNotes: [Note] { sort.sorted(activeNotes) }

    /// Recently Deleted, most recently deleted first.
    var deletedNotes: [Note] {
        notes.filter(\.isDeleted).sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// After restoring a backup.
    func reloadFromStorage() {
        notes = NotesTrash.purged(NoteStorage.load())
    }

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

    /// Moves a note to Recently Deleted (a blank note is just removed).
    func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[index].isEmpty {
            notes.remove(at: index)
        } else {
            notes[index].deletedAt = Date()
        }
        save()
    }

    /// Brings a note back from Recently Deleted.
    func recover(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].deletedAt = nil
        save()
    }

    /// Recently Deleted → Delete: gone for good.
    func deletePermanently(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    /// Recently Deleted → Delete All.
    func emptyRecentlyDeleted() {
        notes.removeAll(where: \.isDeleted)
        save()
    }

    /// Recently Deleted → Recover All.
    func recoverAll() {
        for index in notes.indices { notes[index].deletedAt = nil }
        save()
    }

    /// Settings → Delete All Notes: they all go to Recently Deleted.
    func deleteAll() {
        notes.removeAll { $0.isEmpty }
        let now = Date()
        for index in notes.indices where notes[index].deletedAt == nil { notes[index].deletedAt = now }
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
        Backups.scheduleBackup()
    }
}

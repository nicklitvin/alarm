import Foundation

struct Note: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Pinned notes stay at the top in every sort order.
    var isPinned: Bool = false
    /// Position in the Manual order (lower = higher up).
    var sortIndex: Double = 0

    init(id: UUID = UUID(), title: String = "", body: String = "", createdAt: Date = Date(), updatedAt: Date = Date(),
         isPinned: Bool = false, sortIndex: Double = 0) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.sortIndex = sortIndex
    }

    // Tolerates fields added in later versions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        // Older notes: newest first in Manual order until rearranged.
        sortIndex = try c.decodeIfPresent(Double.self, forKey: .sortIndex) ?? -createdAt.timeIntervalSince1970
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The title, or the first line of the body if there's no title.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.isEmpty ? "New Note" : firstLine
    }

    /// Body text for the list, skipping a first line already used as the title.
    var preview: String {
        var lines = body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !lines.isEmpty { lines.removeFirst() }
        return lines.joined(separator: " ")
    }

    /// What "Copy All" puts on the clipboard.
    var copyText: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return b }
        if b.isEmpty { return t }
        return "\(t)\n\n\(b)"
    }
}

/// How the Notes list is ordered (Notes settings).
enum NotesSort: String, CaseIterable, Identifiable, Sendable {
    case manual, edited, created, title

    var id: String { rawValue }

    var name: String {
        switch self {
        case .manual: "Manual"
        case .edited: "Date Edited"
        case .created: "Date Created"
        case .title: "Title"
        }
    }

    /// Pinned notes first, then by this order.
    func sorted(_ notes: [Note]) -> [Note] {
        notes.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            switch self {
            case .manual:
                return a.sortIndex != b.sortIndex ? a.sortIndex < b.sortIndex : a.updatedAt > b.updatedAt
            case .edited:
                return a.updatedAt > b.updatedAt
            case .created:
                return a.createdAt > b.createdAt
            case .title:
                let order = a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle)
                return order != .orderedSame ? order == .orderedAscending : a.updatedAt > b.updatedAt
            }
        }
    }
}

enum NoteStorage {
    private static let key = "notes.v1"

    static func load() -> [Note] {
        guard let data = AlarmStorage.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Note].self, from: data)) ?? []
    }

    static func save(_ notes: [Note]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        AlarmStorage.defaults.set(data, forKey: key)
    }
}

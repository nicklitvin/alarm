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
        // Checklist boxes are left out; the list shows the checklist's progress instead.
        var lines = body.split(whereSeparator: \.isNewline)
            .map { line -> String in
                let text = String(line)
                let kind = NoteChecklist.kind(of: text)
                return (kind == .unchecked || kind == .checked ? String(text.dropFirst(NoteChecklist.prefixLength)) : text)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
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

extension Array where Element == Note {
    /// Drag `id` onto `target` (press and hold, then drop): returns the notes in Manual order with
    /// the dragged note in the target's place. Dragging down lands after the target, up lands
    /// before it. Moving between Pinned and the rest takes on the target's pin.
    func reordered(moving id: UUID, onto target: UUID, currentSort: NotesSort) -> [Note] {
        guard id != target, let targetNote = first(where: { $0.id == target }), contains(where: { $0.id == id }) else { return self }
        let current = currentSort.sorted(self).map(\.id)
        let movingDown = (current.firstIndex(of: id) ?? 0) < (current.firstIndex(of: target) ?? 0)

        var notes = self
        if let index = notes.firstIndex(where: { $0.id == id }) { notes[index].isPinned = targetNote.isPinned }
        // Pinned notes stay first, then everything in the order on screen.
        var order = NotesSort.manual.sorted(notes.enumerated().map { offset, note in
            var n = note
            n.sortIndex = Double(current.firstIndex(of: note.id) ?? offset)
            return n
        }).map(\.id).filter { $0 != id }
        let targetIndex = order.firstIndex(of: target) ?? order.endIndex
        order.insert(id, at: movingDown ? targetIndex + 1 : targetIndex)

        for (offset, noteID) in order.enumerated() {
            if let index = notes.firstIndex(where: { $0.id == noteID }) { notes[index].sortIndex = Double(offset) }
        }
        return notes
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

/// Lists inside a note, like Apple Notes: checklists and bulleted lists. A checklist item is a
/// line that starts with "☐ " (to do) or "☑ " (done); a bullet is a line that starts with "• ".
/// Both stay readable when copied or read by the assistant. Positions are UTF-16 offsets, as
/// UITextView uses.
enum NoteChecklist {
    static let uncheckedPrefix = "☐ "
    static let checkedPrefix = "☑ "
    static let bulletPrefix = "• "
    /// All prefixes are two UTF-16 units long.
    static let prefixLength = 2

    enum LineKind: Equatable { case plain, unchecked, checked, bullet }

    /// Which kind of list the list buttons make.
    enum ListStyle { case checklist, bullets }

    static func kind(of line: String) -> LineKind {
        if line.hasPrefix(uncheckedPrefix) { return .unchecked }
        if line.hasPrefix(checkedPrefix) { return .checked }
        if line.hasPrefix(bulletPrefix) { return .bullet }
        return .plain
    }

    private static func isItem(_ kind: LineKind) -> Bool { kind == .unchecked || kind == .checked }

    /// The line containing `location`, without its line break.
    static func lineRange(in text: String, at location: Int) -> NSRange {
        let ns = text as NSString
        let clamped = max(0, min(location, ns.length))
        var range = ns.lineRange(for: NSRange(location: clamped, length: 0))
        let line = ns.substring(with: range)
        if line.hasSuffix("\n") { range.length -= 1 }
        return range
    }

    /// Every line of the text with its kind and range, for styling.
    static func lines(in text: String) -> [(range: NSRange, kind: LineKind)] {
        let ns = text as NSString
        var result: [(NSRange, LineKind)] = []
        var location = 0
        repeat {
            let range = lineRange(in: text, at: location)
            result.append((range, kind(of: ns.substring(with: range))))
            location = range.location + range.length + 1
        } while location <= ns.length
        return result
    }

    /// Checks or unchecks the item on the line at `location`. Nil if that line isn't an item.
    static func toggleItem(in text: String, at location: Int) -> String? {
        let ns = text as NSString
        let range = lineRange(in: text, at: location)
        let prefixRange = NSRange(location: range.location, length: prefixLength)
        switch kind(of: ns.substring(with: range)) {
        case .unchecked: return ns.replacingCharacters(in: prefixRange, with: checkedPrefix)
        case .checked: return ns.replacingCharacters(in: prefixRange, with: uncheckedPrefix)
        case .plain, .bullet: return nil
        }
    }

    /// The checklist button: turns the selected lines into items, or back into plain text when
    /// they all are items already. Returns the new text and where the cursor goes.
    static func toggleChecklist(in text: String, selection: NSRange) -> (text: String, selection: NSRange) {
        toggleList(.checklist, in: text, selection: selection)
    }

    /// The bullet button: turns the selected lines into bullets (•), or back into plain text.
    static func toggleBullets(in text: String, selection: NSRange) -> (text: String, selection: NSRange) {
        toggleList(.bullets, in: text, selection: selection)
    }

    static func toggleList(_ style: ListStyle, in text: String, selection: NSRange) -> (text: String, selection: NSRange) {
        let ns = text as NSString
        let first = lineRange(in: text, at: selection.location)
        let last = lineRange(in: text, at: selection.location + selection.length)
        let block = NSRange(location: first.location, length: last.location + last.length - first.location)
        let blockLines = ns.substring(with: block).components(separatedBy: "\n")
        let matches: (LineKind) -> Bool = { style == .checklist ? isItem($0) : $0 == .bullet }
        let allAlready = blockLines.allSatisfy { matches(kind(of: $0)) }
        let prefix = style == .checklist ? uncheckedPrefix : bulletPrefix

        var delta = 0
        let changed = blockLines.map { line -> String in
            let lineKind = kind(of: line)
            if allAlready {
                delta -= prefixLength
                return String(line.dropFirst(prefixLength))
            }
            if matches(lineKind) { return line }
            if lineKind != .plain {
                // A bullet becomes an item and the other way round: swap the prefix.
                return prefix + line.dropFirst(prefixLength)
            }
            delta += prefixLength
            return prefix + line
        }
        let newText = ns.replacingCharacters(in: block, with: changed.joined(separator: "\n"))
        let caret = max(block.location, selection.location + selection.length + delta)
        return (newText, NSRange(location: min(caret, (newText as NSString).length), length: 0))
    }

    /// Return on an item (or bullet) starts the next one; Return on an empty one ends the list.
    /// Nil when the line isn't part of a list (a normal line break).
    static func handleReturn(in text: String, at location: Int) -> (text: String, caret: Int)? {
        let ns = text as NSString
        let range = lineRange(in: text, at: location)
        let line = ns.substring(with: range)
        let lineKind = kind(of: line)
        guard lineKind != .plain, location >= range.location + prefixLength else { return nil }
        if line.dropFirst(prefixLength).trimmingCharacters(in: .whitespaces).isEmpty {
            let newText = ns.replacingCharacters(in: range, with: "")
            return (newText, range.location)
        }
        let insert = "\n" + (lineKind == .bullet ? bulletPrefix : uncheckedPrefix)
        let newText = ns.replacingCharacters(in: NSRange(location: location, length: 0), with: insert)
        return (newText, location + (insert as NSString).length)
    }

    /// Typing "- " or "* " at the start of a line makes a bullet, like Apple Notes.
    static func autoBullet(in text: String, at location: Int, typing: String) -> (text: String, caret: Int)? {
        guard typing == " " else { return nil }
        let ns = text as NSString
        let range = lineRange(in: text, at: location)
        let before = ns.substring(with: NSRange(location: range.location, length: location - range.location))
        guard before == "-" || before == "*" else { return nil }
        let newText = ns.replacingCharacters(in: NSRange(location: range.location, length: 1), with: bulletPrefix)
        return (newText, range.location + prefixLength)
    }

    /// Adds text to the end of a note. If the note ends with a checklist (or bullets), each new
    /// line becomes an item (or bullet) too ("add milk to my grocery list").
    static func appending(_ addition: String, to body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return addition }
        let lastLine = trimmedBody.components(separatedBy: "\n").last ?? ""
        var lines = addition.components(separatedBy: "\n")
        let lastKind = kind(of: lastLine)
        if lastKind != .plain {
            let prefix = lastKind == .bullet ? bulletPrefix : uncheckedPrefix
            lines = lines.map { line in
                let item = line.trimmingCharacters(in: .whitespaces)
                if item.isEmpty || kind(of: item) != .plain { return item }
                return prefix + item.replacingOccurrences(of: #"^[-*]\s*"#, with: "", options: .regularExpression)
            }
        }
        return trimmedBody + "\n" + lines.joined(separator: "\n")
    }

    /// "2 of 5 done" for a note with a checklist.
    static func progress(of body: String) -> (done: Int, total: Int)? {
        let kinds = body.components(separatedBy: "\n").map(kind(of:)).filter(isItem)
        guard !kinds.isEmpty else { return nil }
        return (kinds.filter { $0 == .checked }.count, kinds.count)
    }
}

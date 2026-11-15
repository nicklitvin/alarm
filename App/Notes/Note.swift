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
    case edited, created, title

    var id: String { rawValue }

    var name: String {
        switch self {
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

/// Lists inside a note, like Apple Notes: checklists, bulleted and numbered lists. A checklist
/// item is a line that starts with "☐ " (to do) or "☑ " (done), a bullet starts with "• " and a
/// numbered line with "1. ". All stay readable when copied or read by the assistant. Positions
/// are UTF-16 offsets, as UITextView uses.
enum NoteChecklist {
    static let uncheckedPrefix = "☐ "
    static let checkedPrefix = "☑ "
    static let bulletPrefix = "• "
    /// Checkbox and bullet prefixes are two UTF-16 units long (numbers vary: see prefixLength(of:)).
    static let prefixLength = 2

    enum LineKind: Equatable { case plain, unchecked, checked, bullet, numbered }

    /// Which kind of list the list button makes.
    enum ListStyle: CaseIterable { case checklist, bullets, numbers }

    static func kind(of line: String) -> LineKind {
        if line.hasPrefix(uncheckedPrefix) { return .unchecked }
        if line.hasPrefix(checkedPrefix) { return .checked }
        if line.hasPrefix(bulletPrefix) { return .bullet }
        if numberPrefixLength(line) != nil { return .numbered }
        return .plain
    }

    /// The length of the line's list marker ("☐ ", "• ", "12. "), 0 for plain text.
    static func prefixLength(of line: String) -> Int {
        switch kind(of: line) {
        case .plain: 0
        case .numbered: numberPrefixLength(line) ?? 0
        case .unchecked, .checked, .bullet: prefixLength
        }
    }

    /// "12. milk" → 4: one to three digits, a dot and a space.
    private static func numberPrefixLength(_ line: String) -> Int? {
        let units = Array(line.utf16.prefix(5))
        var digits = 0
        while digits < units.count, digits < 3, (48...57).contains(units[digits]) { digits += 1 }
        guard digits > 0, units.count >= digits + 2, units[digits] == 46, units[digits + 1] == 32 else { return nil }
        return digits + 2
    }

    /// The number of a numbered line ("3. eggs" → 3).
    private static func number(of line: String) -> Int? {
        guard let length = numberPrefixLength(line) else { return nil }
        return Int(line.prefix(length - 2))
    }

    private static func isItem(_ kind: LineKind) -> Bool { kind == .unchecked || kind == .checked }

    /// Where the cursor goes when you press Return in the title: the start of the first line's
    /// text (after its checkbox, bullet or number, if it has one).
    static func firstLineCaret(in text: String) -> Int {
        prefixLength(of: (text as NSString).substring(with: lineRange(in: text, at: 0)))
    }

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
        case .plain, .bullet, .numbered: return nil
        }
    }

    /// The checklist option: turns the selected lines into items, or back into plain text when
    /// they all are items already. Returns the new text and where the cursor goes.
    static func toggleChecklist(in text: String, selection: NSRange) -> (text: String, selection: NSRange) {
        toggleList(.checklist, in: text, selection: selection)
    }

    /// The bulleted list option: turns the selected lines into bullets (•), or back into plain text.
    static func toggleBullets(in text: String, selection: NSRange) -> (text: String, selection: NSRange) {
        toggleList(.bullets, in: text, selection: selection)
    }

    /// Turns the selected lines into a list of `style`, or back into plain text when they all are
    /// that kind already. Other list kinds switch over. Numbers always count 1, 2, 3…
    static func toggleList(_ style: ListStyle, in text: String, selection: NSRange) -> (text: String, selection: NSRange) {
        let ns = text as NSString
        let first = lineRange(in: text, at: selection.location)
        let last = lineRange(in: text, at: selection.location + selection.length)
        let block = NSRange(location: first.location, length: last.location + last.length - first.location)
        let blockLines = ns.substring(with: block).components(separatedBy: "\n")
        let matches: (LineKind) -> Bool = { kind in
            switch style {
            case .checklist: isItem(kind)
            case .bullets: kind == .bullet
            case .numbers: kind == .numbered
            }
        }
        let allAlready = blockLines.allSatisfy { matches(kind(of: $0)) }

        var delta = 0
        var counter = 0
        let changed = blockLines.map { line -> String in
            let lineKind = kind(of: line)
            let oldLength = prefixLength(of: line)
            if allAlready {
                delta -= oldLength
                return String(line.dropFirst(oldLength))
            }
            counter += 1
            if matches(lineKind) { return line }
            let prefix = switch style {
            case .checklist: uncheckedPrefix
            case .bullets: bulletPrefix
            case .numbers: "\(counter). "
            }
            // Another kind of list switches over: swap the marker.
            delta += (prefix as NSString).length - oldLength
            return prefix + line.dropFirst(oldLength)
        }
        let newText = ns.replacingCharacters(in: block, with: changed.joined(separator: "\n"))
        let caret = max(block.location, selection.location + selection.length + delta)
        let result = renumbered(newText, caret: min(caret, (newText as NSString).length))
        return (result.text, NSRange(location: result.caret, length: 0))
    }

    /// Numbers every run of numbered lines 1, 2, 3… (a line that isn't numbered ends a run),
    /// keeping the cursor on the same text.
    static func renumbered(_ text: String, caret: Int) -> (text: String, caret: Int) {
        var lines = text.components(separatedBy: "\n")
        var count = 0
        var position = 0
        var newCaret = caret
        for index in lines.indices {
            let line = lines[index]
            let lineLength = (line as NSString).length
            if let length = numberPrefixLength(line) {
                count += 1
                let prefix = "\(count). "
                if !line.hasPrefix(prefix) {
                    lines[index] = prefix + line.dropFirst(length)
                    if caret >= position + length { newCaret += (prefix as NSString).length - length }
                }
            } else {
                count = 0
            }
            position += lineLength + 1
        }
        return (lines.joined(separator: "\n"), newCaret)
    }

    /// Return on a list line starts the next one (the next number for numbered lists); Return on
    /// an empty one ends the list. Nil when the line isn't part of a list (a normal line break).
    static func handleReturn(in text: String, at location: Int) -> (text: String, caret: Int)? {
        let ns = text as NSString
        let range = lineRange(in: text, at: location)
        let line = ns.substring(with: range)
        let lineKind = kind(of: line)
        let length = prefixLength(of: line)
        guard lineKind != .plain, location >= range.location + length else { return nil }
        if line.dropFirst(length).trimmingCharacters(in: .whitespaces).isEmpty {
            let newText = ns.replacingCharacters(in: range, with: "")
            return renumbered(newText, caret: range.location)
        }
        let next: String = switch lineKind {
        case .bullet: bulletPrefix
        case .numbered: "\((number(of: line) ?? 0) + 1). "
        case .plain, .unchecked, .checked: uncheckedPrefix
        }
        let insert = "\n" + next
        let newText = ns.replacingCharacters(in: NSRange(location: location, length: 0), with: insert)
        return renumbered(newText, caret: location + (insert as NSString).length)
    }

    /// Typing "- " or "* " at the start of a line makes a bullet, like Apple Notes. ("1. " is
    /// already a numbered line.)
    static func autoBullet(in text: String, at location: Int, typing: String) -> (text: String, caret: Int)? {
        guard typing == " " else { return nil }
        let ns = text as NSString
        let range = lineRange(in: text, at: location)
        let before = ns.substring(with: NSRange(location: range.location, length: location - range.location))
        guard before == "-" || before == "*" else { return nil }
        let newText = ns.replacingCharacters(in: NSRange(location: range.location, length: 1), with: bulletPrefix)
        return (newText, range.location + prefixLength)
    }

    /// Adds text to the end of a note. If the note ends with a list, each new line joins it
    /// ("add milk to my grocery list").
    static func appending(_ addition: String, to body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return addition }
        let lastLine = trimmedBody.components(separatedBy: "\n").last ?? ""
        var lines = addition.components(separatedBy: "\n")
        let lastKind = kind(of: lastLine)
        if lastKind != .plain {
            lines = lines.map { line in
                let item = line.trimmingCharacters(in: .whitespaces)
                if item.isEmpty || kind(of: item) != .plain { return item }
                let text = item.replacingOccurrences(of: #"^[-*]\s*"#, with: "", options: .regularExpression)
                return switch lastKind {
                case .bullet: bulletPrefix + text
                case .numbered: "1. " + text // renumbered below
                case .plain, .unchecked, .checked: uncheckedPrefix + text
                }
            }
        }
        return renumbered(trimmedBody + "\n" + lines.joined(separator: "\n"), caret: 0).text
    }

    /// "2 of 5 done" for a note with a checklist.
    static func progress(of body: String) -> (done: Int, total: Int)? {
        let kinds = body.components(separatedBy: "\n").map(kind(of:)).filter(isItem)
        guard !kinds.isEmpty else { return nil }
        return (kinds.filter { $0 == .checked }.count, kinds.count)
    }
}

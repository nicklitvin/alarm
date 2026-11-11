import Foundation

/// Finds the alarm or to-do the user is talking about ("my 7am alarm", "the gym one",
/// "milk"), and reads weekday lists like ["weekdays"] or ["mon", "fri"].
enum AssistantMatching {
    enum Match<Item> {
        case found(Item)
        case none
        case ambiguous([Item])
    }

    private static let englishDays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// Reads repeat days from free text: "weekdays", "mon-fri", "monday to friday",
    /// "tuesdays and thursdays", "every day except sunday", "weekends and wednesday".
    /// Returns an empty set for a one-time alarm ("once", "never"), and nil if no days were recognized.
    static func parseDays(_ text: String) -> Set<Weekday>? {
        var normalized = " " + text.lowercased() + " "
        for separator in [",", ";", "/", "&", "+", ".", "\"", "[", "]", "(", ")", "'"] {
            normalized = normalized.replacingOccurrences(of: separator, with: " ")
        }
        normalized = normalized
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "-", with: " - ")
        let words = normalized.split(separator: " ").map(String.init)
        let joined = " " + words.joined(separator: " ") + " "

        let oneTimePhrases = [" once ", " never ", " none ", " one time ", " one - time ", " no repeat", " not repeat", " no days "]
        if oneTimePhrases.contains(where: joined.contains) { return [] }

        // Split off "except sunday" / "but not friday".
        let exceptMarkers: Set<String> = ["except", "excluding", "but", "besides", "minus", "without"]
        let split = words.firstIndex(where: exceptMarkers.contains) ?? words.endIndex
        guard var days = dayList(Array(words[..<split])) else { return nil }
        if split < words.endIndex, let excluded = dayList(Array(words[words.index(after: split)...])) {
            days.subtract(excluded)
        }
        return days
    }

    /// Backwards-compatible: a list of day words. Unrecognized input gives an empty set.
    static func weekdays(from words: [String]) -> Set<Weekday> {
        parseDays(words.joined(separator: ", ")) ?? []
    }

    static func meansOneTime(_ words: [String]) -> Bool {
        parseDays(words.joined(separator: ", ")) == []
    }

    private static func dayList(_ words: [String]) -> Set<Weekday>? {
        let joined = " " + words.joined(separator: " ") + " "
        var days = Set<Weekday>()
        var found = false

        if [" every day ", " everyday ", " daily ", " all week ", " all days ", " 7 days ", " seven days "].contains(where: joined.contains) {
            days.formUnion(Weekday.allCases); found = true
        }
        if [" weekday ", " weekdays ", " workday ", " workdays ", " work days ", " week days ", " business days "].contains(where: joined.contains) {
            days.formUnion(Weekday.workdays); found = true
        }
        if joined.contains(" weekend ") || joined.contains(" weekends ") {
            days.formUnion(Weekday.weekend); found = true
        }

        var previous: Weekday?
        var rangePending = false
        for word in words {
            if let day = dayName(word) {
                if rangePending, let start = previous {
                    var current = start
                    while current != day {
                        days.insert(current)
                        current = Weekday(rawValue: current.rawValue % 7 + 1)!
                    }
                }
                days.insert(day)
                previous = day
                rangePending = false
                found = true
            } else if ["to", "through", "thru", "until", "till", "-"].contains(word), previous != nil {
                rangePending = true
            }
        }
        return found ? days : nil
    }

    private static func dayName(_ word: String) -> Weekday? {
        var w = word
        if w.count > 3, w.hasSuffix("s") { w.removeLast() }   // "mondays", "tues", "thurs"
        guard w.count >= 2 else { return nil }
        guard let index = englishDays.firstIndex(where: { $0.hasPrefix(w) }) else { return nil }
        // Two letters only for unambiguous abbreviations ("tu", "th", "sa", "su", …).
        if w.count == 2, englishDays.filter({ $0.hasPrefix(w) }).count > 1 { return nil }
        return Weekday(rawValue: index + 1)
    }

    static func alarm(matching query: String, in alarms: [AlarmItem]) -> Match<AlarmItem> {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty || q == "alarm" || q == "my alarm" {
            return alarms.count == 1 ? .found(alarms[0]) : (alarms.isEmpty ? .none : .ambiguous(alarms))
        }

        var candidates = alarms
        if let clock = NaturalTime.parseClock(q) {
            candidates = alarms.filter { alarm in
                alarm.minute == clock.minute &&
                    (alarm.hour == clock.hour || (!clock.isExplicit && clock.hour < 12 && alarm.hour == clock.hour + 12))
            }
        }

        // Narrow down by label using the words that aren't part of a time.
        let words = q.split(whereSeparator: { !$0.isLetter }).map(String.init)
            .filter { !["am", "pm", "alarm", "the", "my", "one", "at", "a"].contains($0) }
        if !words.isEmpty {
            let byLabel = candidates.filter { alarm in
                let label = alarm.label.lowercased()
                return !label.isEmpty && words.allSatisfy { label.contains($0) }
            }
            if !byLabel.isEmpty || NaturalTime.parseClock(q) == nil { candidates = byLabel }
        }
        return result(candidates)
    }

    static func todo(matching query: String, in todos: [TodoItem]) -> Match<TodoItem> {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return .none }

        let exact = todos.filter { $0.title.lowercased() == q }
        if !exact.isEmpty { return result(preferOpen(exact)) }

        let containing = todos.filter { $0.title.lowercased().contains(q) || (q.count > 3 && q.contains($0.title.lowercased())) }
        if !containing.isEmpty { return result(preferOpen(containing)) }

        let words = q.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 }
        guard !words.isEmpty else { return .none }
        let overlapping = todos.filter { todo in
            let title = todo.title.lowercased()
            return words.filter { title.contains($0) }.count * 2 >= words.count
        }
        return result(preferOpen(overlapping))
    }

    /// Finds a note by title, then by words in its title or text.
    static func note(matching query: String, in notes: [Note]) -> Match<Note> {
        let fillers: Set<String> = ["my", "the", "a", "note", "notes"]
        let q = query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !fillers.contains($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return notes.count == 1 ? .found(notes[0]) : .none }

        let titled = notes.map { ($0, $0.displayTitle.lowercased()) }
        if let exact = titled.filter({ $0.1 == q }).map(\.0).first { return .found(exact) }

        let inTitle = titled.filter { $0.1.contains(q) || (q.count > 3 && q.contains($0.1)) }.map(\.0)
        if !inTitle.isEmpty { return result(inTitle) }

        let words = q.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 }
        guard !words.isEmpty else { return .none }
        let byTitleWords = titled.filter { pair in words.filter { pair.1.contains($0) }.count * 2 >= words.count }.map(\.0)
        if !byTitleWords.isEmpty { return result(byTitleWords) }

        let byBody = notes.filter { note in
            let text = note.body.lowercased()
            return words.allSatisfy { text.contains($0) }
        }
        return result(byBody)
    }

    private static func preferOpen(_ todos: [TodoItem]) -> [TodoItem] {
        let open = todos.filter { !$0.isDone }
        return open.isEmpty ? todos : open
    }

    private static func result<Item>(_ items: [Item]) -> Match<Item> {
        switch items.count {
        case 0: .none
        case 1: .found(items[0])
        default: .ambiguous(items)
        }
    }
}

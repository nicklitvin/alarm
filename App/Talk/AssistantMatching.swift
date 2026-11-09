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

    /// Reads repeat days. Words like "once" or "never" mean a one-time alarm (empty set).
    static func weekdays(from words: [String]) -> Set<Weekday> {
        var result = Set<Weekday>()
        for raw in words {
            let word = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            switch word {
            case "weekdays", "weekday", "workdays", "work days", "monday to friday", "mon-fri":
                result.formUnion(Weekday.workdays)
            case "weekends", "weekend":
                result.formUnion(Weekday.weekend)
            case "every day", "everyday", "daily", "all", "all days":
                result.formUnion(Weekday.allCases)
            default:
                if word.count >= 2, let index = englishDays.firstIndex(where: { $0.hasPrefix(String(word.prefix(3))) }) {
                    result.insert(Weekday(rawValue: index + 1)!)
                }
            }
        }
        return result
    }

    /// Whether a days list explicitly asks for a one-time alarm.
    static func meansOneTime(_ words: [String]) -> Bool {
        words.contains { ["once", "never", "none", "one time", "one-time", "no repeat"].contains($0.lowercased()) }
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

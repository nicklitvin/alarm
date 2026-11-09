import Foundation

/// A to-do with an optional deadline (a time, and possibly a date).
struct TodoItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var due: Date? = nil
    var isDone: Bool = false
    var completedAt: Date? = nil
    var createdAt: Date = Date()

    func isOverdue(at now: Date) -> Bool {
        guard !isDone, let due else { return false }
        return due <= now
    }

    mutating func setDone(_ done: Bool, at date: Date = Date()) {
        isDone = done
        completedAt = done ? date : nil
    }
}

extension Array where Element == TodoItem {
    /// Open to-dos first, soonest deadline first (no deadline last), then by creation.
    var sortedForDisplay: [TodoItem] {
        sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }
}

/// Persists to-dos in the shared App Group so the widget can show and check them off.
enum TodoStorage {
    static let widgetKind = "TodoWidget"
    private static let key = "todos.v1"

    static func load() -> [TodoItem] {
        guard let data = AlarmStorage.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TodoItem].self, from: data)) ?? []
    }

    static func save(_ todos: [TodoItem]) {
        guard let data = try? JSONEncoder().encode(todos) else { return }
        AlarmStorage.defaults.set(data, forKey: key)
    }
}

extension TimeFormat {
    /// "5:00 PM", "Tomorrow 9:00 AM", "Fri 9:00 AM" or "Nov 14, 9:00 AM".
    static func dueDescription(_ date: Date, relativeTo now: Date, calendar: Calendar = .current) -> String {
        let time = string(for: date)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDue = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfDue).day ?? 0
        switch days {
        case 1: return "Tomorrow \(time)"
        case -1: return "Yesterday \(time)"
        case 2...6: return "\(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]) \(time)"
        default:
            let month = calendar.shortMonthSymbols[calendar.component(.month, from: date) - 1]
            return "\(month) \(calendar.component(.day, from: date)), \(time)"
        }
    }
}

import Foundation

/// A to-do with an optional deadline (a time, and possibly a date).
struct TodoItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    /// Optional extra line shown under the title.
    var details: String = ""
    var due: Date? = nil
    var isDone: Bool = false
    var completedAt: Date? = nil
    var createdAt: Date = Date()
    /// Its place on the To-Do tab (lower is higher up), set when you drag to-dos around.
    /// Nil for to-dos saved before you could.
    var sortIndex: Double? = nil

    init(id: UUID = UUID(), title: String, details: String = "", due: Date? = nil,
         isDone: Bool = false, completedAt: Date? = nil, createdAt: Date = Date(), sortIndex: Double? = nil) {
        self.id = id
        self.title = title
        self.details = details
        self.due = due
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }

    // Tolerates to-dos saved by older versions (e.g. without `details`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        sortIndex = try c.decodeIfPresent(Double.self, forKey: .sortIndex)
    }

    var trimmedDetails: String { details.trimmingCharacters(in: .whitespacesAndNewlines) }

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
    /// The To-Do tab's order: the order you arranged by dragging. To-dos that were never placed
    /// (from before reordering existed) follow, by deadline.
    var inListOrder: [TodoItem] {
        let byDeadline = sortedForDisplay.map(\.id)
        return sorted { a, b in
            switch (a.sortIndex, b.sortIndex) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (byDeadline.firstIndex(of: a.id) ?? 0) < (byDeadline.firstIndex(of: b.id) ?? 0)
            }
        }
    }

    /// Where a new to-do goes among these open to-dos (in list order): just before the first one
    /// with a later deadline (or none), so new to-dos land by deadline; without a deadline, last.
    func sortIndex(forNew todo: TodoItem) -> Double {
        let list = inListOrder
        let last = (list.compactMap(\.sortIndex).max() ?? -1) + 1
        guard let due = todo.due,
              let next = list.firstIndex(where: { other in other.due.map { $0 > due } ?? true })
        else { return last }
        let after = list[next].sortIndex ?? Double(next)
        let before = next > 0 ? (list[next - 1].sortIndex ?? Double(next - 1)) : after - 2
        return (before + after) / 2
    }

    /// Drag-to-reorder on the list (these are in list order): moves the rows and renumbers
    /// every to-do's place.
    func moving(from source: IndexSet, to destination: Int) -> [TodoItem] {
        var items = self
        let moved = source.sorted().map { items[$0] }
        for index in source.sorted(by: >) { items.remove(at: index) }
        let insertAt = destination - source.filter { $0 < destination }.count
        items.insert(contentsOf: moved, at: Swift.min(Swift.max(0, insertAt), items.count))
        return items.enumerated().map { offset, todo in
            var placed = todo
            placed.sortIndex = Double(offset)
            return placed
        }
    }

    /// The To-Do tab's two open sections: to-dos without a deadline in your order (drag to
    /// arrange), then those with a deadline, soonest first.
    var tabSections: (todos: [TodoItem], deadlines: [TodoItem]) {
        let open = filter { !$0.isDone }
        return (open.filter { $0.due == nil }.inListOrder,
                open.filter { $0.due != nil }.sortedForDisplay)
    }

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

extension TodoItem {
    /// "Remind Me Tomorrow": the same time one day after the deadline (not a day after you tap).
    /// If that has passed too, the next day at that time that's still ahead. No deadline: a day from now.
    static func dayLater(than due: Date?, now: Date, calendar: Calendar = .current) -> Date {
        guard let due else { return now.addingTimeInterval(24 * 3600) }
        func nextDay(_ date: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(24 * 3600) }
        var next = nextDay(due)
        while next <= now { next = nextDay(next) }
        return next
    }
}

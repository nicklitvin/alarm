import Foundation
import Observation
import WidgetKit

/// Holds the to-do list. Every change is saved to the App Group, synced to reminders,
/// and refreshes the widget.
@MainActor
@Observable
final class TodoController {
    static let shared = TodoController()

    private(set) var todos: [TodoItem]

    @ObservationIgnored private var syncTask: Task<Void, Never>?

    private init() {
        todos = TodoStorage.load()
        TodoIntentRunner.handler = { id in
            await TodoController.shared.toggle(id)
        }
        commit(reloadWidget: false)
    }

    var openTodos: [TodoItem] { todos.filter { !$0.isDone }.sortedForDisplay }
    var completedTodos: [TodoItem] {
        todos.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    // MARK: - Editing

    @discardableResult
    func add(title: String, due: Date?) -> TodoItem {
        let todo = TodoItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), due: due)
        todos.append(todo)
        commit()
        return todo
    }

    func update(_ todo: TodoItem) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        var todo = todo
        todo.title = todo.title.trimmingCharacters(in: .whitespacesAndNewlines)
        todos[index] = todo
        commit()
    }

    func toggle(_ id: UUID) async {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].setDone(!todos[index].isDone)
        await commit().value
    }

    func setDone(_ done: Bool, for id: UUID) async {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].setDone(done)
        await commit().value
    }

    /// "Remind Me in 1 Hour" from the notification.
    func snooze(_ id: UUID, by interval: TimeInterval = 3600) async {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].due = Date().addingTimeInterval(interval)
        todos[index].setDone(false)
        await commit().value
    }

    func delete(_ id: UUID) {
        todos.removeAll { $0.id == id }
        commit()
    }

    func clearCompleted() {
        todos.removeAll(where: \.isDone)
        commit()
    }

    /// Picks up changes made from the widget while the app wasn't running.
    func reload() {
        let stored = TodoStorage.load()
        guard stored != todos else { return }
        todos = stored
        commit(reloadWidget: false)
    }

    // MARK: - Sync

    @discardableResult
    private func commit(reloadWidget: Bool = true) -> Task<Void, Never> {
        TodoStorage.save(todos)
        if reloadWidget { WidgetCenter.shared.reloadTimelines(ofKind: TodoStorage.widgetKind) }

        let previous = syncTask
        let task = Task { @MainActor in
            await previous?.value
            await TodoReminders.sync(self.todos)
        }
        syncTask = task
        return task
    }
}

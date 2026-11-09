import AppIntents
import Foundation
import WidgetKit

/// Checks a to-do off (or back on) from the widget.
///
/// Depending on iOS, this may run in the app or the widget extension. The app installs a
/// `handler` so its list stays in sync. Otherwise the shared storage is edited directly.
struct ToggleTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle To-Do"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "To-Do ID") var todoID: String

    init() { todoID = "" }
    init(todoID: UUID) { self.todoID = todoID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: todoID) else { return .result() }
        await TodoIntentRunner.toggle(id)
        return .result()
    }
}

enum TodoIntentRunner {
    @MainActor static var handler: ((UUID) async -> Void)?

    static func toggle(_ id: UUID) async {
        if let handler = await MainActor.run(body: { handler }) {
            await handler(id)
            return
        }
        var todos = TodoStorage.load()
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].setDone(!todos[index].isDone)
        TodoStorage.save(todos)
        await TodoReminders.update(todos[index])
        WidgetCenter.shared.reloadTimelines(ofKind: TodoStorage.widgetKind)
    }
}

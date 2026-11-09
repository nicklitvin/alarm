import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct TodoEntry: TimelineEntry {
    let date: Date
    /// Open to-dos, soonest deadline first.
    let todos: [TodoItem]
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: .now, todos: TodoEntry.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        let open = Self.openTodos()
        completion(TodoEntry(date: .now, todos: open.isEmpty && context.isPreview ? TodoEntry.samples : open))
    }

    /// Re-renders at each upcoming deadline so overdue items turn red on time.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        let now = Date()
        let open = Self.openTodos()
        let deadlines = open.compactMap(\.due).filter { $0 > now }.sorted().prefix(10)
        var entries = [TodoEntry(date: now, todos: open)]
        entries += deadlines.map { TodoEntry(date: $0, todos: open) }
        let refresh = deadlines.last.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private static func openTodos() -> [TodoItem] {
        TodoStorage.load().filter { !$0.isDone }.sortedForDisplay
    }
}

private extension TodoEntry {
    static var samples: [TodoItem] {
        let now = Date()
        return [
            TodoItem(title: "Call the dentist", due: now.addingTimeInterval(3600)),
            TodoItem(title: "Buy groceries", due: now.addingTimeInterval(6 * 3600)),
            TodoItem(title: "Pay rent", due: now.addingTimeInterval(26 * 3600)),
            TodoItem(title: "Plan weekend trip"),
        ]
    }
}

// MARK: - Views

struct TodoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodoEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        default: list
        }
    }

    private var maxRows: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 3
        case .systemLarge: 8
        default: 3
        }
    }

    // Home screen.
    private var list: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("To-Do", systemImage: "checklist")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                if !entry.todos.isEmpty {
                    Text("\(entry.todos.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            if entry.todos.isEmpty {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text("All done")
                        .font(.headline)
                    Text("Nothing left to do.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                ForEach(entry.todos.prefix(maxRows)) { todo in
                    TodoWidgetRow(todo: todo, now: entry.date, compact: family == .systemSmall)
                }
                Spacer(minLength: 0)
                if entry.todos.count > maxRows {
                    Text("+\(entry.todos.count - maxRows) more")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Lock screen: the next to-do.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(entry.todos.isEmpty ? "To-Do" : "To-Do · \(entry.todos.count)", systemImage: "checklist")
                .font(.system(size: 13, weight: .semibold))
                .widgetAccentable()
            if let next = entry.todos.first {
                Text(next.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let due = next.due {
                    Text(next.isOverdue(at: entry.date) ? "Overdue · \(TimeFormat.dueDescription(due, relativeTo: entry.date))"
                                                         : TimeFormat.dueDescription(due, relativeTo: entry.date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("All done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inline: some View {
        if let next = entry.todos.first {
            if let due = next.due {
                Label("\(next.title) · \(TimeFormat.dueDescription(due, relativeTo: entry.date))", systemImage: "checklist")
            } else {
                Label(next.title, systemImage: "checklist")
            }
        } else {
            Label("All done", systemImage: "checkmark.circle")
        }
    }
}

/// A row with a tappable checkbox that completes the to-do right from the home screen.
private struct TodoWidgetRow: View {
    let todo: TodoItem
    let now: Date
    let compact: Bool

    var body: some View {
        let overdue = todo.isOverdue(at: now)
        HStack(alignment: .top, spacing: 8) {
            Button(intent: ToggleTodoIntent(todoID: todo.id)) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(compact ? .body : .title3)
                    .foregroundStyle(overdue ? Color.red : Color.orange)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                Text(todo.title)
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                    .lineLimit(1)
                if let due = todo.due {
                    Text(TimeFormat.dueDescription(due, relativeTo: now))
                        .font(.caption2)
                        .foregroundStyle(overdue ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoStorage.widgetKind, provider: TodoProvider()) { entry in
            TodoWidgetView(entry: entry)
                .widgetBackground()
        }
        .configurationDisplayName("To-Do")
        .description("Your upcoming to-dos. Tap a circle to check one off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemMedium) {
    TodoWidget()
} timeline: {
    TodoEntry(date: .now, todos: TodoEntry.samples)
    TodoEntry(date: .now, todos: [])
}

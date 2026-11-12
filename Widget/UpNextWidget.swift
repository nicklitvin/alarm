import AppIntents
import SwiftUI
import WidgetKit

// The "Up Next" widget: whatever is relevant right now. An alarm within the hour (with Dismiss),
// running timers, overdue and soon-due to-dos, the next alarm, then the rest of the to-do list.
// It keeps the To-Do widget's kind, so widgets already on the home screen upgrade in place.

// MARK: - Timeline

struct UpNextEntry: TimelineEntry {
    let date: Date
    let items: [UpNextItem]
}

struct UpNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpNextEntry {
        UpNextEntry(date: .now, items: UpNextEntry.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
        let items = Self.items(at: .now)
        completion(UpNextEntry(date: .now, items: items.isEmpty && context.isPreview ? UpNextEntry.samples : items))
    }

    /// One entry now, plus one at every moment the list changes (an alarm enters its last hour,
    /// a timer ends, a to-do becomes due, …).
    func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> Void) {
        let now = Date()
        let alarms = AlarmStorage.load(), todos = TodoStorage.load(), timers = TimerStorage.load()
        let changes = UpNext.changeDates(alarms: alarms, todos: todos, timers: timers, now: now)
        let entries = ([now] + changes).map { date in
            UpNextEntry(date: date, items: UpNext.items(alarms: alarms, todos: todos, timers: timers, now: date))
        }
        let refresh = changes.last.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private static func items(at date: Date) -> [UpNextItem] {
        UpNext.items(alarms: AlarmStorage.load(), todos: TodoStorage.load(), timers: TimerStorage.load(), now: date)
    }
}

private extension UpNextEntry {
    static var samples: [UpNextItem] {
        let now = Date()
        let alarm = AlarmItem(hour: 7, minute: 0, label: "Wake up", weekdays: Weekday.workdays)
        return [
            UpNextItem(kind: .alarmSoon(alarm, now.addingTimeInterval(40 * 60))),
            UpNextItem(kind: .timer(TimerItem(id: UUID(), label: "Tea", duration: 300, state: .running,
                                              fireDate: now.addingTimeInterval(180), remaining: 300))),
            UpNextItem(kind: .todo(TodoItem(title: "Pay rent", details: "Transfer before noon", due: now.addingTimeInterval(2 * 3600)))),
            UpNextItem(kind: .todo(TodoItem(title: "Buy groceries"))),
        ]
    }
}

// MARK: - Views

struct UpNextWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpNextEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            case .systemSmall: small
            default: list
            }
        }
        // Tapping anywhere else opens the top item (small and lock screen widgets only support this).
        .widgetURL((entry.items.first?.deepLink ?? .todos).url)
    }

    private var maxRows: Int {
        family == .systemLarge ? 7 : 2
    }

    // Medium / large: a list with the Ask button in the bottom-right corner.
    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                allClear
                Spacer(minLength: 0)
            } else {
                ForEach(entry.items.prefix(maxRows)) { item in
                    UpNextRow(item: item, now: entry.date)
                }
                Spacer(minLength: 0)
            }
            footer(hidden: max(0, entry.items.count - maxRows))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Small: the single most relevant thing.
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let first = entry.items.first {
                UpNextRow(item: first, now: entry.date, prominent: true)
            } else {
                allClear
            }
            Spacer(minLength: 0)
            footer(hidden: max(0, entry.items.count - 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        Label("Up Next", systemImage: "sparkles.rectangle.stack")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
    }

    private var allClear: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("All clear")
                .font(.headline)
            Text("Nothing coming up.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "+N more" on the left, the Ask button in the bottom-right corner.
    private func footer(hidden: Int) -> some View {
        HStack(alignment: .center) {
            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            AskButton()
        }
    }

    // Lock screen: the most relevant thing.
    @ViewBuilder
    private var rectangular: some View {
        if let first = entry.items.first {
            UpNextRow(item: first, now: entry.date, compactLockScreen: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Label("Up Next", systemImage: "sparkles.rectangle.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text("All clear")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let first = entry.items.first {
            switch first.kind {
            case .alarmSoon(_, let date): Label("Alarm \(TimeFormat.string(for: date))", systemImage: "alarm.fill")
            case .timer(let timer): Label(timer.title, systemImage: "timer")
            case .todo(let todo): Label(todo.due.map { "\(todo.title) · \(TimeFormat.dueDescription($0, relativeTo: entry.date))" } ?? todo.title,
                                        systemImage: "checklist")
            case .nextAlarm(_, let date): Label(TimeFormat.dueDescription(date, relativeTo: entry.date), systemImage: "alarm")
            }
        } else {
            Label("All clear", systemImage: "checkmark.circle")
        }
    }
}

/// Opens the system prompt at the top of the screen to ask the assistant.
private struct AskButton: View {
    var body: some View {
        Button(intent: AskAssistantIntent()) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.orange.gradient))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask Assistant")
    }
}

/// One row. Icons/checkboxes are vertically centered with their text.
private struct UpNextRow: View {
    let item: UpNextItem
    let now: Date
    var prominent = false
    var compactLockScreen = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            leading
            // Tapping the text opens the item in the app; the circle and buttons do their own thing.
            Link(destination: item.deepLink.url) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        title
                            .font(compactLockScreen ? .system(size: 15, weight: .semibold) : (prominent ? .headline : .subheadline.weight(.medium)))
                            .lineLimit(prominent ? 2 : 1)
                        subtitle
                            .font(compactLockScreen ? .system(size: 12, weight: .medium) : .caption2)
                            .foregroundStyle(subtitleIsUrgent ? Color.red : Color.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            if !compactLockScreen { trailing }
        }
    }

    @ViewBuilder private var leading: some View {
        switch item.kind {
        case .todo(let todo):
            Button(intent: ToggleTodoIntent(todoID: todo.id)) {
                Image(systemName: "circle")
                    .font(prominent ? .title3 : .body)
                    .foregroundStyle(todo.isOverdue(at: now) ? Color.red : Color.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(todo.title) as done")
        case .alarmSoon:
            icon("alarm.fill")
        case .timer(let timer):
            icon(timer.state == .ringing ? "bell.fill" : "timer")
        case .nextAlarm:
            icon("alarm")
        }
    }

    private func icon(_ name: String, tint: Color = .orange) -> some View {
        Image(systemName: name)
            .font(prominent ? .title3 : .body)
            .foregroundStyle(tint)
            .frame(minWidth: 20)
            .widgetAccentable()
    }

    @ViewBuilder private var title: some View {
        switch item.kind {
        case .alarmSoon(let alarm, let date):
            Text("\(alarm.title) · \(TimeFormat.string(for: date))")
        case .timer(let timer):
            Text(timer.title)
        case .todo(let todo):
            Text(todo.title)
        case .nextAlarm(let alarm, let date):
            Text("\(alarm.title) · \(TimeFormat.dueDescription(date, relativeTo: now))")
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch item.kind {
        case .alarmSoon(_, let date):
            Text("Rings in \(date, style: .relative)")
        case .timer(let timer):
            switch timer.state {
            case .running where timer.fireDate > now:
                Text(timerInterval: now...timer.fireDate, countsDown: true)
            case .paused:
                Text("Paused · \(TimeFormat.clock(timer.remaining))")
            default:
                Text("Time's up")
            }
        case .todo(let todo):
            if let due = todo.due {
                Text(todo.isOverdue(at: now) ? "Overdue · \(TimeFormat.dueDescription(due, relativeTo: now))"
                                             : "Due \(TimeFormat.dueDescription(due, relativeTo: now))")
            } else if !todo.trimmedDetails.isEmpty {
                Text(todo.trimmedDetails)
            } else {
                Text("No deadline")
            }
        case .nextAlarm(_, let date):
            Text("in \(date, style: .relative)")
        }
    }

    private var subtitleIsUrgent: Bool {
        if case .todo(let todo) = item.kind { return todo.isOverdue(at: now) }
        return false
    }

    @ViewBuilder private var trailing: some View {
        switch item.kind {
        case .alarmSoon(let alarm, _):
            Button(intent: DismissNextAlarmIntent(alarmID: alarm.id)) {
                Text("Dismiss")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        default:
            EmptyView()
        }
    }
}

// MARK: - Widget

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoStorage.widgetKind, provider: UpNextProvider()) { entry in
            UpNextWidgetView(entry: entry)
                .widgetBackground()
        }
        .configurationDisplayName("Up Next")
        .description("What matters now: an alarm you can dismiss, timers, to-dos that are due. Tap ✦ to ask the assistant.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemMedium) {
    UpNextWidget()
} timeline: {
    UpNextEntry(date: .now, items: UpNextEntry.samples)
    UpNextEntry(date: .now, items: [])
}

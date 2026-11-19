import AppIntents
import SwiftUI
import WidgetKit

// The "Up Next" widget: the next alarm on top, however far away (with Dismiss), then
// running timers, overdue and soon-due to-dos and the rest of the to-do list. Taps open the tab.
// It keeps the To-Do widget's kind, so widgets already on the home screen upgrade in place.

// MARK: - Timeline

struct UpNextEntry: TimelineEntry {
    let date: Date
    let items: [UpNextItem]
    /// How many to-dos are open (bottom left of the medium and large widget).
    var todoCount = 0
}

struct UpNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpNextEntry {
        UpNextEntry(date: .now, items: UpNextEntry.samples, todoCount: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
        let items = Self.items(at: .now)
        let preview = items.isEmpty && context.isPreview
        completion(UpNextEntry(date: .now, items: preview ? UpNextEntry.samples : items,
                               todoCount: preview ? 5 : TodoStorage.load().filter { !$0.isDone }.count))
    }

    /// An entry every minute for the next hour (so the alarm's "in 2h 4m" stays right), plus one
    /// at every moment the list changes in that hour (a timer ends, a to-do becomes due, …).
    /// Then the widget asks for a fresh timeline.
    func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> Void) {
        let now = Date()
        let alarms = AlarmStorage.load(), todos = TodoStorage.load(), timers = TimerStorage.load()
        let horizon = now.addingTimeInterval(3600)
        let minute = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
        let ticks = (1...60).map { minute.addingTimeInterval(TimeInterval($0 * 60)) }
        let changes = UpNext.changeDates(alarms: alarms, todos: todos, timers: timers, now: now).filter { $0 < horizon }
        let dates = Array(Set([now] + ticks + changes)).sorted()
        let openCount = todos.filter { !$0.isDone }.count
        let entries = dates.map { date in
            UpNextEntry(date: date, items: UpNext.items(alarms: alarms, todos: todos, timers: timers, now: date, options: .current),
                        todoCount: openCount)
        }
        completion(Timeline(entries: entries, policy: .after(horizon)))
    }

    private static func items(at date: Date) -> [UpNextItem] {
        UpNext.items(alarms: AlarmStorage.load(), todos: TodoStorage.load(), timers: TimerStorage.load(), now: date, options: .current)
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
        // Tapping anywhere else opens the tab of what's on top.
        .widgetURL((layout.alarm != nil ? DeepLink.alarms : entry.items.first?.deepLink ?? .todos).url)
    }

    private var layout: UpNext.Layout { UpNext.layout(entry.items, now: entry.date) }

    // Medium / large, like the Reminders widget: the Live Talk button (or a to-do icon) top left,
    // how many to-dos are open bottom left; on the right the next alarm with Dismiss, then to-dos
    // and timers, in equal-height rows (four in the medium widget).
    private var list: some View {
        GeometryReader { geometry in
            let layout = self.layout
            let lines = family == .systemMedium ? 4 : max(4, Int(geometry.size.height / 31))
            // Like Reminders, the rows reach into the widget's top and bottom margins (about 5 pt
            // from the edge instead of 16), so they're spread out rather than bunched in the middle.
            let line = (geometry.size.height + 2 * Self.rowBleed) / CGFloat(lines)
            // The featured alarm is the first row; other alarms stay off this narrower column.
            let others = layout.rows.filter { item in
                switch item.kind {
                case .alarmSoon, .nextAlarm: false
                case .timer, .todo: true
                }
            }
            let shown = Array(others.prefix(lines - (layout.alarm != nil ? 1 : 0)))
            HStack(alignment: .top, spacing: 10) {
                // Just wide enough for the two buttons, so the to-dos get the rest.
                summary
                    .frame(width: 78, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    if let alarm = layout.alarm {
                        UpNextAlarmLine(upcoming: alarm, now: entry.date)
                            .frame(height: line)
                    }
                    // No gaps between rows: every point of a row opens its tab.
                    ForEach(shown) { item in
                        UpNextRow(item: item, now: entry.date, singleLine: true)
                            .frame(height: line)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                    // Quick, not floaty: a checked-off row slides away and the rest move up fast.
                    .animation(.snappy(duration: 0.25), value: shown.map(\.id))
                    if layout.alarm == nil && shown.isEmpty {
                        Text("Nothing coming up")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(height: line)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.vertical, -Self.rowBleed)
            }
        }
    }

    /// How far the right column's rows reach into the top and bottom margins.
    private static let rowBleed: CGFloat = 11

    /// The left column: Notes (opens the tab) and New Timer buttons, and the number of open to-dos, which also
    /// tells you how many didn't fit on the right.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Link(destination: DeepLink.notes.url) {
                    SummaryIcon(systemImage: "note.text")
                }
                .accessibilityLabel("Open Notes")
                Link(destination: DeepLink.newTimer.url) {
                    SummaryIcon(systemImage: "timer")
                }
                .accessibilityLabel("New Timer")
            }
            Spacer(minLength: 0)
            Link(destination: DeepLink.todos.url) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(entry.todoCount)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(entry.todoCount == 1 ? "To-Do" : "To-Dos")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.orange)
                }
                .foregroundStyle(.primary)
            }
            // Down toward the corner like Reminders' count (the label's descenders sit in the margin).
            .padding(.bottom, -5)
            .accessibilityLabel("\(entry.todoCount) to-dos")
        }
    }

    // Small: the next alarm with Dismiss, otherwise (no alarms) the most relevant thing.
    // (No ✦: there's no room for it.)
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let alarm = layout.alarm {
                SmallAlarm(upcoming: alarm, now: entry.date)
            } else {
                if let first = entry.items.first {
                    UpNextRow(item: first, now: entry.date, prominent: true)
                } else {
                    allClear
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    // Lock screen: the most relevant thing.
    @ViewBuilder
    private var rectangular: some View {
        if let first = entry.items.first {
            UpNextRow(item: first, now: entry.date, compactLockScreen: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text("Up Next")
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


extension UpcomingAlarm {
    /// Dismiss is offered within 12 hours of the ring, unless the alarm already skips a ring.
    func canDismiss(now: Date) -> Bool {
        date.timeIntervalSince(now) <= AlarmItem.dismissWindow && (alarm.skippedOccurrence ?? .distantPast) <= now
    }
}

/// The small home screen alarm widget (Next Alarm): "in 2h 4m" at the top, big time, label, and a
/// full-width Dismiss button along the bottom.
struct SmallAlarm: View {
    let upcoming: UpcomingAlarm
    let now: Date

    var body: some View {
        let parts = TimeFormat.parts(for: upcoming.date)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
                Spacer(minLength: 4)
                Text("in \(TimeFormat.countdown(from: now, to: upcoming.date))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts.time)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let period = parts.period {
                    Text(period).font(.system(size: 16, weight: .semibold))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            if let label = upcoming.alarm.customLabel {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            // Within the Show Alarm window, and one skipped ring per alarm.
            if upcoming.canDismiss(now: now) {
                Button(intent: DismissNextAlarmIntent(alarmID: upcoming.alarm.id)) {
                    Text("Dismiss")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss the \(TimeFormat.string(for: upcoming.date)) alarm")
                // Down into the widget's bottom margin, so the button sits near the bottom edge.
                .padding(.bottom, -8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}


/// A round orange button top left (New Note, New Timer), like the Reminders widget's list icon.
private struct SummaryIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.orange.gradient))
    }
}

/// The next alarm as the first row on the right: "⏰ 9:50 PM  in 38m" with Dismiss (the countdown
/// is left out when there isn't room).
private struct UpNextAlarmLine: View {
    let upcoming: UpcomingAlarm
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Link(destination: DeepLink.alarms.url) {
                ViewThatFits(in: .horizontal) {
                    label(withCountdown: true)
                    label(withCountdown: false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)

            // One skipped ring per alarm: once its next ring is dismissed, the one after it can't be.
            if upcoming.canDismiss(now: now) {
                Button(intent: DismissNextAlarmIntent(alarmID: upcoming.alarm.id)) {
                    Text("Dismiss")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss the \(TimeFormat.string(for: upcoming.date)) alarm")
            }
        }
    }

    private func label(withCountdown: Bool) -> some View {
        let parts = TimeFormat.parts(for: upcoming.date)
        return HStack(spacing: 8) {
            Image(systemName: "alarm.fill")
                .font(.body)
                .foregroundStyle(.orange)
                .frame(width: 20) // the to-do circles' column
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(parts.time)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let period = parts.period {
                    Text(period).font(.caption2.weight(.semibold))
                }
            }
            if withCountdown {
                Text("in \(TimeFormat.countdown(from: now, to: upcoming.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// One row. Icons/checkboxes are vertically centered with their text.
private struct UpNextRow: View {
    let item: UpNextItem
    let now: Date
    var prominent = false
    var compactLockScreen = false
    /// One line per row (title left, time right), so more rows fit (medium and large widgets).
    var singleLine = false
    /// Extra tappable space above and below the text, so rows have no dead gaps between them.
    var tapPadding: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            leading
            // Tapping the row opens the item in the app; the circle and buttons do their own thing.
            Link(destination: item.deepLink.url) {
                HStack(spacing: 0) {
                    if singleLine {
                        title
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        inlineDetail
                            .font(.caption.weight(.medium))
                            .foregroundStyle(subtitleIsUrgent ? Color.red : Color.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    } else {
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
                }
                .padding(.leading, 8)
                .padding(.vertical, tapPadding)
                // One-line rows fill their whole line, so every point of it is tappable.
                .frame(maxHeight: singleLine ? .infinity : nil)
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            if !compactLockScreen { trailing.padding(.leading, 8) }
        }
    }

    @ViewBuilder private var leading: some View {
        switch item.kind {
        case .todo(let todo):
            // Tapping checks it off: the circle turns into a checkmark, then the row leaves
            // (UpNext keeps a just-completed to-do for a moment so the check is seen).
            Button(intent: ToggleTodoIntent(todoID: todo.id)) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(prominent ? .title3 : .body)
                    .foregroundStyle(todo.isOverdue(at: now) ? Color.red : Color.orange)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.snappy(duration: 0.15), value: todo.isDone)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isDone ? "Mark \(todo.title) as not done" : "Mark \(todo.title) as done")
        case .alarmSoon:
            icon("alarm.fill")
        case .timer(let timer):
            icon(timer.state == .ringing ? "bell.fill" : "timer")
        case .nextAlarm:
            icon("alarm.fill")
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
                .strikethrough(todo.isDone)
                .foregroundStyle(todo.isDone ? Color.secondary : Color.primary)
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
            }
        case .nextAlarm(_, let date):
            Text("in \(date, style: .relative)")
        }
    }

    /// The short detail on the right of a one-line row: a to-do's due time, a timer's countdown,
    /// when an alarm rings.
    @ViewBuilder private var inlineDetail: some View {
        switch item.kind {
        case .todo(let todo):
            if let due = todo.due {
                Text(TimeFormat.dueDescription(due, relativeTo: now))
            }
        case .alarmSoon(_, let date), .nextAlarm(_, let date):
            // The title already has the time: show how long until it rings.
            Text("in \(TimeFormat.countdown(from: now, to: date))")
        case .timer(let timer):
            if timer.state == .running && timer.fireDate > now {
                // A live countdown claims all the width it can; a fixed width keeps the row (and the
                // rows under it) in place.
                subtitle
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: timer.fireDate.timeIntervalSince(now) >= 3600 ? 58 : 44, alignment: .trailing)
            } else {
                subtitle
            }
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
        .description("Your next alarm with a Dismiss button, then timers and to-dos. Tap the waveform to open Talk.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline]) // small: Next Alarm, with Dismiss
    }
}

#Preview(as: .systemMedium) {
    UpNextWidget()
} timeline: {
    UpNextEntry(date: .now, items: UpNextEntry.samples)
    UpNextEntry(date: .now, items: [])
}

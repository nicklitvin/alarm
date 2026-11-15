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
}

struct UpNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpNextEntry {
        UpNextEntry(date: .now, items: UpNextEntry.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
        let items = Self.items(at: .now)
        completion(UpNextEntry(date: .now, items: items.isEmpty && context.isPreview ? UpNextEntry.samples : items))
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
        let entries = dates.map { date in
            UpNextEntry(date: date, items: UpNext.items(alarms: alarms, todos: todos, timers: timers, now: date, options: .current))
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

    /// Open to-dos in the widget, shown next to the title.
    private var todoCount: Int {
        entry.items.filter { item in
            if case .todo(let todo) = item.kind { return !todo.isDone }
            return false
        }.count
    }

    /// As many one-line rows as fit in `height`: the medium widget shows the alarm and three
    /// rows (four lines of content), the large one about ten.
    private func rowsThatFit(_ rows: [UpNextItem], height: CGFloat) -> [UpNextItem] {
        var used: CGFloat = 0
        var fitting: [UpNextItem] = []
        for row in rows {
            let rowHeight = Self.rowHeight
            guard used + rowHeight <= height || fitting.isEmpty else { break }
            used += rowHeight
            fitting.append(row)
        }
        return fitting
    }
    private static let headerHeight: CGFloat = 20
    private static let alarmHeight: CGFloat = 34
    /// A one-line row, including the tappable space above and below (tapPadding).
    private static let rowHeight: CGFloat = 26
    /// The bottom line with "+3 to-dos" and the Live Talk button.
    private static let footerHeight: CGFloat = 34

    /// "+3 to-dos" for the to-dos that didn't fit ("+2 more" if only alarms or timers didn't).
    private static func moreText(_ hidden: [UpNextItem]) -> String {
        let todos = hidden.filter { if case .todo = $0.kind { true } else { false } }.count
        return todos > 0 ? "+\(todos) to-do\(todos == 1 ? "" : "s")" : "+\(hidden.count) more"
    }

    // Medium / large: the next alarm on top with Dismiss on its line,
    // then as many rows as fit, and the ✦ (open Talk) button in the bottom-right corner.
    private var list: some View {
        GeometryReader { geometry in
            let layout = self.layout
            // With an alarm on top, the rows follow it directly (no divider or "To-Do" line).
            let top = layout.alarm != nil ? Self.alarmHeight + 6 : Self.headerHeight + 2
            // With the Live Talk button, the bottom line holds "+3 to-dos" and the button.
            let showsTalk = AppSettings.widgetShowsTalkButton
            let footer: CGFloat = showsTalk ? Self.footerHeight : 0
            let shown = rowsThatFit(layout.rows, height: geometry.size.height - top - footer)
            let hidden = Array(layout.rows.dropFirst(shown.count))
            VStack(alignment: .leading, spacing: 2) {
                if let alarm = layout.alarm {
                    AlarmHeader(upcoming: alarm, now: entry.date)
                        .frame(height: Self.alarmHeight)
                        .padding(.bottom, 4)
                } else {
                    header(title: "Up Next")
                }
                if shown.isEmpty {
                    if layout.alarm == nil {
                        Spacer(minLength: 0)
                        allClear
                    } else {
                        Text("Nothing to do.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                } else {
                    // No gaps between rows: every point of a row opens its tab.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { item in
                            UpNextRow(item: item, now: entry.date, singleLine: true, tapPadding: 3)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    Spacer(minLength: 0)
                }
                if showsTalk {
                    HStack(alignment: .center) {
                        if !hidden.isEmpty {
                            Text(Self.moreText(hidden))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        AskButton()
                    }
                    .frame(height: Self.footerHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // Small: the next alarm with Dismiss, otherwise (no alarms) the most relevant thing.
    // (No ✦: there's no room for it.)
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let alarm = layout.alarm {
                SmallAlarm(upcoming: alarm, now: entry.date)
            } else {
                header(title: "Up Next")
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

    /// "Up Next" (or "To-Do" under the alarm) and how many to-dos there are.
    private func header(title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            if todoCount > 0 {
                Text("\(todoCount) to-do\(todoCount == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: Self.headerHeight - 2, alignment: .leading)
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

/// The next alarm across the top (however far away): big time, label and when, with Dismiss on
/// the right. Dismiss always works for the next ring, however far away it is.
private struct AlarmHeader: View {
    let upcoming: UpcomingAlarm
    let now: Date
    /// Small widget: Dismiss under the time instead of beside it.
    var stacked = false

    var body: some View {
        let parts = TimeFormat.parts(for: upcoming.date)
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            Link(destination: DeepLink.alarms.url) {
                if stacked {
                    VStack(alignment: .leading, spacing: 1) {
                        time(parts, size: 34)
                        details.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                } else {
                    // Everything on one line: "⏰ 7:00 AM  in 2h 4m" (with the label, if it has one).
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "alarm.fill")
                            .font(.headline)
                            .foregroundStyle(.primary) // black (white in dark mode)
                        time(parts, size: 24)
                        details.font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
            .foregroundStyle(.primary)

            // One skipped ring per alarm: once its next ring is dismissed, the one after it
            // (shown here) can't be dismissed too.
            if (upcoming.alarm.skippedOccurrence ?? .distantPast) <= now {
            Button(intent: DismissNextAlarmIntent(alarmID: upcoming.alarm.id)) {
                Text("Dismiss")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss the \(TimeFormat.string(for: upcoming.date)) alarm")
            }
        }
    }

    private func time(_ parts: (time: String, period: String?), size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(parts.time)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let period = parts.period {
                Text(period).font(.system(size: size * 0.5, weight: .semibold))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// "in 2h 4m" (two units at most: "in 1d 5h" when it's days away), after the alarm's own
    /// label if it has one ("Gym · in 2h 4m"). An unlabeled alarm doesn't say "Alarm".
    private var details: some View {
        Text(upcoming.alarm.customLabel.map { "\($0) · " } ?? "") + Text("in \(TimeFormat.countdown(from: now, to: upcoming.date))")
    }
}

/// Small widget with an alarm: fills the space like the Next Alarm widget ("in 2h 4m" at the top,
/// big time, label), with a full-width Dismiss button along the bottom.
private struct SmallAlarm: View {
    let upcoming: UpcomingAlarm
    let now: Date

    var body: some View {
        let parts = TimeFormat.parts(for: upcoming.date)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.primary)
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
            // One skipped ring per alarm (see AlarmHeader).
            if (upcoming.alarm.skippedOccurrence ?? .distantPast) <= now {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Opens Alarmie on the Talk tab. (Widgets can't show the system's type-a-request prompt,
/// so the assistant is one tap away in the app instead.)
private struct AskButton: View {
    var body: some View {
        Link(destination: DeepLink.talk.url) {
            Image(systemName: "waveform") // the Live Talk icon, as on the Talk tab
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.orange.gradient))
        }
        .accessibilityLabel("Open Talk")
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isDone ? "Mark \(todo.title) as not done" : "Mark \(todo.title) as done")
        case .alarmSoon:
            icon("alarm.fill", tint: .primary)
        case .timer(let timer):
            icon(timer.state == .ringing ? "bell.fill" : "timer")
        case .nextAlarm:
            icon("alarm.fill", tint: .primary)
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
        case .timer:
            subtitle
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemMedium) {
    UpNextWidget()
} timeline: {
    UpNextEntry(date: .now, items: UpNextEntry.samples)
    UpNextEntry(date: .now, items: [])
}

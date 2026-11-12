import Foundation

/// What matters right now, most urgent first: for the smart "Up Next" widget.
struct UpNextItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Rings within the hour; can be dismissed.
        case alarmSoon(AlarmItem, Date)
        case timer(TimerItem)
        case todo(TodoItem)
        /// The next alarm, when it's more than an hour away.
        case nextAlarm(AlarmItem, Date)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .alarmSoon(let a, _): "soon-\(a.id)"
        case .timer(let t): "timer-\(t.id)"
        case .todo(let t): "todo-\(t.id)"
        case .nextAlarm(let a, _): "next-\(a.id)"
        }
    }
}

enum UpNext {
    /// To-dos due within this window count as "soon" and move up.
    static let todoSoonWindow: TimeInterval = 3 * 3600
    /// Show the next alarm when it's within this long.
    static let nextAlarmWindow: TimeInterval = 24 * 3600

    /// What the widget shows (Alarm and To-Do settings → Widget).
    struct Options: Sendable {
        var alarms = true
        var todosWithDeadline = true
        var todosWithoutDeadline = true

        static var current: Options {
            Options(alarms: AppSettings.widgetShowsAlarms,
                    todosWithDeadline: AppSettings.widgetShowsTimedTodos,
                    todosWithoutDeadline: AppSettings.widgetShowsUntimedTodos)
        }
    }

    /// A to-do checked off this recently stays (shown checked) so the widget can show the check
    /// before the item goes away.
    static let completedLinger: TimeInterval = 2

    static func items(alarms: [AlarmItem], todos: [TodoItem], timers: [TimerItem], now: Date,
                      options: Options = Options()) -> [UpNextItem] {
        var result: [UpNextItem] = []
        let headsUp = AlarmItem.headsUpInterval
        let alarms = options.alarms ? alarms : []
        let todos = todos.filter { $0.due == nil ? options.todosWithoutDeadline : options.todosWithDeadline }

        // 1. Alarms ringing within the hour. A dismissed ring is skipped, so it simply disappears.
        var soonAlarmIDs = Set<UUID>()
        var urgentAlarms: [(Date, UpNextItem)] = []
        for alarm in alarms where alarm.isEnabled {
            if let next = alarm.nextFireDate(after: now), next.timeIntervalSince(now) <= headsUp {
                urgentAlarms.append((next, UpNextItem(kind: .alarmSoon(alarm, next))))
                soonAlarmIDs.insert(alarm.id)
            }
        }
        result += urgentAlarms.sorted { $0.0 < $1.0 }.map(\.1)

        // 2. Timers: ringing, then running (soonest first), then paused.
        func timerRank(_ t: TimerItem) -> (Int, TimeInterval) {
            switch t.state {
            case .ringing: (0, 0)
            case .running: t.fireDate <= now ? (0, 0) : (1, t.fireDate.timeIntervalSince(now))
            case .paused: (2, t.remaining)
            }
        }
        result += timers.sorted { timerRank($0) < timerRank($1) }.map { UpNextItem(kind: .timer($0)) }

        // 3–4. Overdue to-dos, then ones due soon. Just-checked-off ones keep their place for a moment.
        let justDone = Set(todos.filter { todo in
            guard todo.isDone, let completed = todo.completedAt else { return false }
            return now.timeIntervalSince(completed) < completedLinger
        }.map(\.id))
        let original = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
        let open = todos.filter { !$0.isDone || justDone.contains($0.id) }
            .map { todo -> TodoItem in var t = todo; t.isDone = false; return t } // sort as if still open
            .sortedForDisplay
        let overdue = open.filter { $0.isOverdue(at: now) }
        let dueSoon = open.filter { todo in
            guard let due = todo.due, due > now else { return false }
            return due.timeIntervalSince(now) <= todoSoonWindow
        }
        func item(_ todo: TodoItem) -> UpNextItem { UpNextItem(kind: .todo(original[todo.id] ?? todo)) }
        result += (overdue + dueSoon).map(item)

        // 5. The next alarm, if it isn't already shown above.
        if let next = alarms.filter({ !soonAlarmIDs.contains($0.id) }).nextFire(after: now),
           next.date.timeIntervalSince(now) <= nextAlarmWindow {
            result.append(UpNextItem(kind: .nextAlarm(next.alarm, next.date)))
        }

        // 6. Everything else on the to-do list.
        let shownTodoIDs = Set((overdue + dueSoon).map(\.id))
        result += open.filter { !shownTodoIDs.contains($0.id) }.map(item)
        return result
    }

    /// Moments when the list above changes, so the widget can refresh exactly then.
    static func changeDates(alarms: [AlarmItem], todos: [TodoItem], timers: [TimerItem], now: Date, limit: Int = 20) -> [Date] {
        var dates: [Date] = []
        for alarm in alarms where alarm.isEnabled {
            for ring in alarm.upcomingFireDates(after: now, limit: 2) {
                dates += [ring.addingTimeInterval(-AlarmItem.headsUpInterval), ring, ring.addingTimeInterval(-nextAlarmWindow)]
            }
        }
        for timer in timers where timer.state == .running {
            dates.append(timer.fireDate)
        }
        for todo in todos {
            if !todo.isDone, let due = todo.due { dates += [due.addingTimeInterval(-todoSoonWindow), due] }
            // A just-checked-off to-do leaves the widget after its check has shown.
            if todo.isDone, let completed = todo.completedAt { dates.append(completed.addingTimeInterval(completedLinger)) }
        }
        let future = Set(dates.filter { $0 > now }.map { $0.timeIntervalSince1970.rounded() })
        return Array(future.sorted().prefix(limit)).map(Date.init(timeIntervalSince1970:))
    }
}

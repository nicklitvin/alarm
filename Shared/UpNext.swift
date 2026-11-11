import Foundation

/// What matters right now, most urgent first: for the smart "Up Next" widget.
struct UpNextItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Rings within the hour; can be dismissed.
        case alarmSoon(AlarmItem, Date)
        /// Its next ring was dismissed; can be undone until then.
        case alarmDismissed(AlarmItem, Date)
        case timer(TimerItem)
        case todo(TodoItem)
        /// The next alarm, when it's more than an hour away.
        case nextAlarm(AlarmItem, Date)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .alarmSoon(let a, _): "soon-\(a.id)"
        case .alarmDismissed(let a, _): "dismissed-\(a.id)"
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

    static func items(alarms: [AlarmItem], todos: [TodoItem], timers: [TimerItem], now: Date) -> [UpNextItem] {
        var result: [UpNextItem] = []
        let headsUp = AlarmItem.headsUpInterval

        // 1. Alarms ringing within the hour (or dismissed for this hour).
        var soonAlarmIDs = Set<UUID>()
        var urgentAlarms: [(Date, UpNextItem)] = []
        for alarm in alarms where alarm.isEnabled {
            if let skipped = alarm.skippedOccurrence, skipped > now, skipped.timeIntervalSince(now) <= headsUp {
                urgentAlarms.append((skipped, UpNextItem(kind: .alarmDismissed(alarm, skipped))))
                soonAlarmIDs.insert(alarm.id)
            } else if let next = alarm.nextFireDate(after: now), next.timeIntervalSince(now) <= headsUp {
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

        // 3–4. Overdue to-dos, then ones due soon.
        let open = todos.filter { !$0.isDone }.sortedForDisplay
        let overdue = open.filter { $0.isOverdue(at: now) }
        let dueSoon = open.filter { todo in
            guard let due = todo.due, due > now else { return false }
            return due.timeIntervalSince(now) <= todoSoonWindow
        }
        result += (overdue + dueSoon).map { UpNextItem(kind: .todo($0)) }

        // 5. The next alarm, if it isn't already shown above.
        if let next = alarms.filter({ !soonAlarmIDs.contains($0.id) }).nextFire(after: now),
           next.date.timeIntervalSince(now) <= nextAlarmWindow {
            result.append(UpNextItem(kind: .nextAlarm(next.alarm, next.date)))
        }

        // 6. Everything else on the to-do list.
        let shownTodoIDs = Set((overdue + dueSoon).map(\.id))
        result += open.filter { !shownTodoIDs.contains($0.id) }.map { UpNextItem(kind: .todo($0)) }
        return result
    }

    /// Moments when the list above changes, so the widget can refresh exactly then.
    static func changeDates(alarms: [AlarmItem], todos: [TodoItem], timers: [TimerItem], now: Date, limit: Int = 20) -> [Date] {
        var dates: [Date] = []
        for alarm in alarms where alarm.isEnabled {
            for ring in alarm.upcomingFireDates(after: now, limit: 2) {
                dates += [ring.addingTimeInterval(-AlarmItem.headsUpInterval), ring, ring.addingTimeInterval(-nextAlarmWindow)]
            }
            if let skipped = alarm.skippedOccurrence {
                dates += [skipped.addingTimeInterval(-AlarmItem.headsUpInterval), skipped]
            }
        }
        for timer in timers where timer.state == .running {
            dates.append(timer.fireDate)
        }
        for todo in todos where !todo.isDone {
            if let due = todo.due { dates += [due.addingTimeInterval(-todoSoonWindow), due] }
        }
        let future = Set(dates.filter { $0 > now }.map { $0.timeIntervalSince1970.rounded() })
        return Array(future.sorted().prefix(limit)).map(Date.init(timeIntervalSince1970:))
    }
}

import Foundation

/// User settings that affect notifications and sorting. Stored in the App Group so the widget and
/// background intents see the same values. Views edit them with `@AppStorage(key, store: AppSettings.store)`.
enum AppSettings {
    static var store: UserDefaults { AlarmStorage.defaults }

    // MARK: Alarms

    static let alarmHeadsUpEnabledKey = "settings.alarm.headsUpEnabled"
    static let alarmHeadsUpMinutesKey = "settings.alarm.headsUpMinutes"
    static let alarmHeadsUpChoices = [15, 30, 60, 120]

    /// Notification before each alarm, with a Dismiss button.
    static var alarmHeadsUpEnabled: Bool { bool(alarmHeadsUpEnabledKey, default: true) }
    /// How long before an alarm the heads-up arrives and the Dismiss button appears.
    static let alarmTapToDismissKey = "settings.alarm.tapToDismiss"
    /// Tapping the heads-up notification dismisses that ring (off by default). Swiping the
    /// notification away never does.
    static var alarmTapToDismiss: Bool { bool(alarmTapToDismissKey, default: false) }

    static var alarmHeadsUpMinutes: Int {
        let value = int(alarmHeadsUpMinutesKey, default: 60)
        return alarmHeadsUpChoices.contains(value) ? value : 60
    }

    // MARK: To-dos

    static let todoDueAlertEnabledKey = "settings.todo.dueAlertEnabled"
    static let todoEarlyReminderMinutesKey = "settings.todo.earlyReminderMinutes"
    static let todoEarlyReminderChoices = [0, 5, 15, 30, 60, 1440]
    /// Notification at the deadline.
    static var todoDueAlertEnabled: Bool { bool(todoDueAlertEnabledKey, default: true) }
    /// An extra reminder this long before the deadline (0 = off).
    static var todoEarlyReminderMinutes: Int { int(todoEarlyReminderMinutesKey, default: 0) }

    /// Quick times for deadlines, as minutes after midnight, stored as "480,840,1260".
    static let todoQuickTimesKey = "settings.todo.quickTimes"
    /// 8 AM, 2 PM and 9 PM: morning, afternoon and night.
    static let defaultTodoQuickTimes = [8 * 60, 14 * 60, 21 * 60]
    /// There are always exactly this many quick times; you change them, not add or remove them.
    static let quickTimeCount = 3
    static var todoQuickTimes: [Int] { parseQuickTimes(store.string(forKey: todoQuickTimesKey)) }

    /// Exactly three times, sorted and without duplicates. Missing ones are filled in from the
    /// defaults; anything unreadable gives the defaults.
    static func parseQuickTimes(_ text: String?) -> [Int] {
        let values = (text ?? "").split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (0..<1440).contains($0) }
        var unique = Array(Array(Set(values)).sorted().prefix(quickTimeCount))
        for fallback in defaultTodoQuickTimes where unique.count < quickTimeCount && !unique.contains(fallback) {
            unique.append(fallback)
        }
        return unique.sorted()
    }

    static func formatQuickTimes(_ minutes: [Int]) -> String {
        minutes.map(String.init).joined(separator: ",")
    }

    // MARK: Widget (Up Next)

    static let widgetShowsAlarmsKey = "settings.widget.alarms"
    static let widgetShowsTimedTodosKey = "settings.widget.timedTodos"
    static let widgetShowsUntimedTodosKey = "settings.widget.untimedTodos"
    static var widgetShowsAlarms: Bool { bool(widgetShowsAlarmsKey, default: true) }
    static var widgetShowsTimedTodos: Bool { bool(widgetShowsTimedTodosKey, default: true) }
    static var widgetShowsUntimedTodos: Bool { bool(widgetShowsUntimedTodosKey, default: true) }

    // MARK: Notes

    static let notesSortKey = "settings.notes.sort"

    // MARK: Helpers

    /// "15 min", "1 hour", "2 hours", "1 day".
    static func leadTimeName(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Off"
        case 1440: "1 day"
        case let m where m % 60 == 0: m == 60 ? "1 hour" : "\(m / 60) hours"
        default: "\(minutes) min"
        }
    }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        store.object(forKey: key) as? Bool ?? value
    }

    private static func int(_ key: String, default value: Int) -> Int {
        store.object(forKey: key) as? Int ?? value
    }
}

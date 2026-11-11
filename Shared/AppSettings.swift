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
    static var alarmHeadsUpMinutes: Int {
        let value = int(alarmHeadsUpMinutesKey, default: 60)
        return alarmHeadsUpChoices.contains(value) ? value : 60
    }

    // MARK: Timers

    static let timerWarningMinutesKey = "settings.timer.warningMinutes"
    static let timerWarningChoices = [0, 1, 5]
    /// Notification shortly before a timer ends (0 = off).
    static var timerWarningMinutes: Int { int(timerWarningMinutesKey, default: 0) }

    // MARK: To-dos

    static let todoDueAlertEnabledKey = "settings.todo.dueAlertEnabled"
    static let todoEarlyReminderMinutesKey = "settings.todo.earlyReminderMinutes"
    static let todoEarlyReminderChoices = [0, 5, 15, 30, 60, 1440]
    /// Notification at the deadline.
    static var todoDueAlertEnabled: Bool { bool(todoDueAlertEnabledKey, default: true) }
    /// An extra reminder this long before the deadline (0 = off).
    static var todoEarlyReminderMinutes: Int { int(todoEarlyReminderMinutesKey, default: 0) }

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

import Foundation

/// Persists alarms in the shared App Group so the lock screen widget can read them.
enum AlarmStorage {
    static let widgetKind = "NextAlarmWidget"
    private static let key = "alarms.v1"

    static var appGroupIdentifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String) ?? "group.com.example.alarm"
    }

    /// UserDefaults shared between the app and the widget extension.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func load() -> [AlarmItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AlarmItem].self, from: data)) ?? []
    }

    static func save(_ alarms: [AlarmItem]) {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        defaults.set(data, forKey: key)
    }
}

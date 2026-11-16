import Foundation

/// Persists alarms in the shared App Group so the lock screen widget can read them.
enum AlarmStorage {
    static let widgetKind = "NextAlarmWidget"
    private static let key = "alarms.v1"

    /// The App Group shared by the app and its widgets. Normally the one in Info.plist; if this
    /// build can't open that one but can open `group.<app bundle ID>`, that one is used instead.
    static let appGroupIdentifier: String = {
        let configured = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
        var candidates = [configured].compactMap { $0 }.filter { !$0.isEmpty && !$0.contains("$(") }
        if let bundleID = Bundle.main.bundleIdentifier {
            // The widget's ID is "<app ID>.widget": the group is named after the app.
            let appID = [".widget", ".menubar"].reduce(bundleID) { id, suffix in
                id.hasSuffix(suffix) ? String(id.dropLast(suffix.count)) : id
            }
            candidates.append("group.\(appID)")
        }
        #if canImport(Darwin)
        if let reachable = candidates.first(where: {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }) { return reachable }
        #endif
        return candidates.first ?? "group.com.example.alarm"
    }()

    /// UserDefaults shared between the app and the widget extension.
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard

    static func load() -> [AlarmItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AlarmItem].self, from: data)) ?? []
    }

    static func save(_ alarms: [AlarmItem]) {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        defaults.set(data, forKey: key)
    }
}

import Foundation

struct TimerItem: Identifiable, Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case running, paused, ringing
    }

    var id: UUID
    var label: String
    var duration: TimeInterval
    var state: State
    /// When it goes off (meaningful while running).
    var fireDate: Date
    /// Time left (meaningful while paused).
    var remaining: TimeInterval

    var title: String { label.isEmpty ? TimeFormat.durationName(duration) : label }

    func timeLeft(at date: Date) -> TimeInterval {
        switch state {
        case .running: max(0, fireDate.timeIntervalSince(date))
        case .paused: remaining
        case .ringing: 0
        }
    }
}

/// Timers live in the App Group so the widget can show them.
enum TimerStorage {
    private static let key = "timers.v1"

    static func load() -> [TimerItem] {
        let decoder = JSONDecoder()
        if let data = AlarmStorage.defaults.data(forKey: key),
           let timers = try? decoder.decode([TimerItem].self, from: data) {
            return timers
        }
        // Versions before 1.6 kept timers in the app's own storage.
        if let data = UserDefaults.standard.data(forKey: key),
           let timers = try? decoder.decode([TimerItem].self, from: data) {
            return timers
        }
        return []
    }

    static func save(_ timers: [TimerItem]) {
        guard let data = try? JSONEncoder().encode(timers) else { return }
        AlarmStorage.defaults.set(data, forKey: key)
    }
}

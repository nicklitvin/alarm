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

/// A timer you've used before, shown under Recents so it can be started again with one tap.
struct RecentTimer: Codable, Hashable, Identifiable, Sendable {
    var duration: TimeInterval
    var label: String

    var id: String { "\(Int(duration))|\(label)" }
    var title: String { label.isEmpty ? TimeFormat.durationName(duration) : label }

    /// Newest first, without duplicates, at most `limit`.
    static func adding(_ timer: RecentTimer, to recents: [RecentTimer], limit: Int = 12) -> [RecentTimer] {
        Array(([timer] + recents.filter { $0.id != timer.id }).prefix(limit))
    }
}

enum RecentTimerStorage {
    private static let key = "timers.recents.v1"

    static func load() -> [RecentTimer] {
        guard let data = AlarmStorage.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RecentTimer].self, from: data)) ?? []
    }

    static func save(_ recents: [RecentTimer]) {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        AlarmStorage.defaults.set(data, forKey: key)
    }
}

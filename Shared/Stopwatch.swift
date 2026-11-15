import Foundation

/// The stopwatch on the Timers tab. Kept as times rather than a ticking counter, so it keeps
/// counting while the app is closed.
struct Stopwatch: Codable, Hashable, Sendable {
    /// When the current run started (nil while paused or reset).
    var startedAt: Date?
    /// Time counted before the current run.
    var accumulated: TimeInterval = 0
    /// Lap times: the total elapsed time at each Lap press, oldest first.
    var laps: [TimeInterval] = []

    var isRunning: Bool { startedAt != nil }
    /// Never started, or reset.
    var isReset: Bool { startedAt == nil && accumulated == 0 && laps.isEmpty }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        accumulated + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    mutating func start(at now: Date = Date()) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    mutating func pause(at now: Date = Date()) {
        guard startedAt != nil else { return }
        accumulated = elapsed(at: now)
        startedAt = nil
    }

    mutating func lap(at now: Date = Date()) {
        guard isRunning else { return }
        laps.append(elapsed(at: now))
    }

    mutating func reset() {
        self = Stopwatch()
    }

    /// Each lap's own length (time since the lap before), newest first, numbered from 1.
    func lapSplits() -> [(number: Int, split: TimeInterval)] {
        var previous: TimeInterval = 0
        var splits: [(Int, TimeInterval)] = []
        for (index, total) in laps.enumerated() {
            splits.append((index + 1, total - previous))
            previous = total
        }
        return splits.reversed()
    }

    /// "0:42.07", "12:03.50" or "1:02:03.50".
    static func format(_ seconds: TimeInterval) -> String {
        let hundredths = Int((max(0, seconds) * 100 + 0.0001).rounded(.down)) // the nudge avoids 65.07 → 1:05.06
        let h = hundredths / 360_000, m = (hundredths / 6000) % 60, s = (hundredths / 100) % 60, cs = hundredths % 100
        return h > 0 ? String(format: "%d:%02d:%02d.%02d", h, m, s, cs) : String(format: "%d:%02d.%02d", m, s, cs)
    }
}

enum StopwatchStorage {
    private static let key = "stopwatch.v1"

    static func load() -> Stopwatch {
        guard let data = AlarmStorage.defaults.data(forKey: key),
              let stopwatch = try? JSONDecoder().decode(Stopwatch.self, from: data) else { return Stopwatch() }
        return stopwatch
    }

    static func save(_ stopwatch: Stopwatch) {
        if let data = try? JSONEncoder().encode(stopwatch) { AlarmStorage.defaults.set(data, forKey: key) }
    }
}

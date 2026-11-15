import Foundation
import Observation

/// The stopwatch on the Timers tab. Saved after every change, so it keeps counting (and keeps its
/// laps) while the app is closed.
@MainActor
@Observable
final class StopwatchController {
    static let shared = StopwatchController()

    private(set) var stopwatch: Stopwatch

    private init() {
        stopwatch = StopwatchStorage.load()
    }

    func start() { change { $0.start() } }
    func pause() { change { $0.pause() } }
    func lap() { change { $0.lap() } }
    func reset() { change { $0.reset() } }

    private func change(_ edit: (inout Stopwatch) -> Void) {
        edit(&stopwatch)
        StopwatchStorage.save(stopwatch)
    }
}

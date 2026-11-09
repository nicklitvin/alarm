import AlarmKit
import AppIntents
import Foundation

/// Actions on a running timer, triggered from its Live Activity (lock screen / Dynamic Island).
/// The intents run in the app's process. The app installs `handler` so its timer list stays
/// in sync. Without a handler, the AlarmKit call is made directly.
enum TimerAction: Sendable {
    case pause, resume, cancel
}

enum TimerIntentRunner {
    @MainActor static var handler: ((TimerAction, UUID) -> Void)?

    static func run(_ action: TimerAction, timerID: String) async {
        guard let id = UUID(uuidString: timerID) else { return }
        await MainActor.run {
            if let handler {
                handler(action, id)
                return
            }
            switch action {
            case .pause: try? AlarmManager.shared.pause(id: id)
            case .resume: try? AlarmManager.shared.resume(id: id)
            case .cancel: try? AlarmManager.shared.cancel(id: id)
            }
        }
    }
}

struct PauseTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Timer"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Timer ID") var timerID: String

    init() { timerID = "" }
    init(timerID: UUID) { self.timerID = timerID.uuidString }

    func perform() async throws -> some IntentResult {
        await TimerIntentRunner.run(.pause, timerID: timerID)
        return .result()
    }
}

struct ResumeTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Timer"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Timer ID") var timerID: String

    init() { timerID = "" }
    init(timerID: UUID) { self.timerID = timerID.uuidString }

    func perform() async throws -> some IntentResult {
        await TimerIntentRunner.run(.resume, timerID: timerID)
        return .result()
    }
}

struct CancelTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Cancel Timer"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Timer ID") var timerID: String

    init() { timerID = "" }
    init(timerID: UUID) { self.timerID = timerID.uuidString }

    func perform() async throws -> some IntentResult {
        await TimerIntentRunner.run(.cancel, timerID: timerID)
        return .result()
    }
}

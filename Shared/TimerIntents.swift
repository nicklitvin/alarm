#if !targetEnvironment(macCatalyst)
import AlarmKit
#endif
import AppIntents
import Foundation

/// Actions on a running timer, triggered from its Live Activity (lock screen / Dynamic Island).
/// The intents run in the app's process. The app installs `handler` so its timer list stays
/// in sync. Without a handler, the AlarmKit call is made directly.
enum TimerAction: Sendable {
    case pause, resume, cancel
    /// Adds time: 1, 5 or 15 minutes (the Live Activity's long-press buttons).
    case extend(TimeInterval)
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
            #if !targetEnvironment(macCatalyst)
            switch action {
            case .pause: try? AlarmManager.shared.pause(id: id)
            case .resume: try? AlarmManager.shared.resume(id: id)
            case .cancel: try? AlarmManager.shared.cancel(id: id)
            case .extend: break // needs the app's timer list (the handler is always set once it runs)
            }
            #endif
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

/// "+1 min", "+5 min", "+15 min" in the timer's Live Activity (touch and hold the Dynamic Island).
struct ExtendTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add Time to Timer"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Timer ID") var timerID: String
    @Parameter(title: "Minutes") var minutes: Int

    init() { timerID = ""; minutes = 1 }
    init(timerID: UUID, minutes: Int) { self.timerID = timerID.uuidString; self.minutes = minutes }

    func perform() async throws -> some IntentResult {
        await TimerIntentRunner.run(.extend(TimeInterval(minutes * 60)), timerID: timerID)
        return .result()
    }
}

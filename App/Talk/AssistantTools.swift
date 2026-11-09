import Foundation
import FoundationModels

/// Lets the on-device model start a timer in the Timers tab.
struct SetTimerTool: Tool {
    let name = "setTimer"
    let description = "Starts a countdown timer in the app. Use it whenever the user asks for a timer or to be reminded in a set amount of time."

    @Generable
    struct Arguments {
        @Guide(description: "Total length of the timer in seconds. For example 300 for 5 minutes, 5400 for 1.5 hours.")
        var seconds: Int

        @Guide(description: "A short name for the timer if the user gave one, like \"Pasta\". Otherwise an empty string.")
        var label: String
    }

    func call(arguments: Arguments) async throws -> String {
        let seconds = min(max(arguments.seconds, 1), 24 * 3600)
        let label = arguments.label.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let timer = try await TimerController.shared.start(duration: TimeInterval(seconds), label: label)
            await TalkModel.shared.addEvent("Timer set · \(timer.title) · \(TimeFormat.clock(timer.duration))", systemImage: "timer")
            return "Started a \(TimeFormat.durationName(timer.duration)) timer\(label.isEmpty ? "" : " called \(label)")."
        } catch {
            return "The timer couldn't be started: \(error.localizedDescription)"
        }
    }
}

/// Lets the model answer "how long is left on my timer?".
struct ListTimersTool: Tool {
    let name = "listTimers"
    let description = "Lists the timers that are currently running or paused, with the time left on each."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let timers = await TimerController.shared.timers
        guard !timers.isEmpty else { return "There are no timers running." }
        let now = Date()
        return timers.map { timer in
            switch timer.state {
            case .ringing: "\(timer.title): finished and ringing"
            case .paused: "\(timer.title): paused with \(TimeFormat.durationName(timer.remaining)) left"
            case .running: "\(timer.title): \(TimeFormat.durationName(timer.timeLeft(at: now))) left"
            }
        }.joined(separator: "\n")
    }
}

/// Lets the model cancel one timer by name, or all of them.
struct CancelTimersTool: Tool {
    let name = "cancelTimers"
    let description = "Cancels timers. Pass the timer's name to cancel just that one, or an empty string to cancel all timers."

    @Generable
    struct Arguments {
        @Guide(description: "Name of the timer to cancel, or an empty string to cancel every timer.")
        var label: String
    }

    func call(arguments: Arguments) async throws -> String {
        let label = arguments.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cancelled: [String] = await MainActor.run {
            let controller = TimerController.shared
            let matches = controller.timers.filter { label.isEmpty || $0.title.lowercased().contains(label) }
            matches.forEach { controller.cancel($0.id) }
            return matches.map(\.title)
        }
        guard !cancelled.isEmpty else { return "No matching timer was found." }
        await TalkModel.shared.addEvent("Cancelled \(cancelled.joined(separator: ", "))", systemImage: "xmark.circle")
        return "Cancelled: \(cancelled.joined(separator: ", "))."
    }
}

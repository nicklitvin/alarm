import AppIntents
import Foundation

/// Connects the Control Center buttons (compiled into both the app and the widget) to the
/// assistant, which only exists in the app. The app installs these handlers at launch.
enum AssistantBridge {
    @MainActor static var ask: ((String) async -> String)?
    @MainActor static var openLiveTalk: (() -> Void)?
}

/// "Ask Assistant": iOS shows a small prompt at the top of the screen. Type, or dictate with the
/// keyboard's mic, and the reply pops up right there, without opening the app.
///
/// Conforming to `LiveActivityIntent` makes iOS run it inside the app (in the background), where
/// the on-device model and your alarms, to-dos and timers live.
struct AskAssistantIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Ask Assistant"
    static let description = IntentDescription("Ask the on-device assistant to set alarms, to-dos and timers, or anything else.")

    @Parameter(title: "Request", requestValueDialog: "What can I do for you?")
    var request: String

    init() {}

    init(request: String) {
        self.request = request
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            text = try await $request.requestValue("What can I do for you?")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return .result(dialog: "Okay, never mind.") }

        let reply: String
        if let ask = await AssistantBridge.ask {
            reply = await ask(text)
        } else {
            reply = "Open Alarmie once, then try again."
        }
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

/// "Live Talk": opens the app on the Talk tab and starts listening straight away.
struct StartLiveTalkIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Live Talk"
    static let description = IntentDescription("Opens the assistant and starts listening.")
    static var openAppWhenRun: Bool { true }

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { AssistantBridge.openLiveTalk?() }
        return .result()
    }
}

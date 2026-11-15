import AppIntents
import Foundation

/// Connects the Control Center buttons (compiled into both the app and the widget) to the
/// assistant, which only exists in the app. The app installs these handlers at launch.
enum AssistantBridge {
    @MainActor static var ask: ((String) async -> String)?
    @MainActor static var openLiveTalk: (() -> Void)?
}

/// The Control Center button (and Siri/Shortcuts "Ask Alarmie"): like the Reminders app's quick
/// add, iOS shows a small text box at the top of the screen. Type (or dictate with the keyboard's
/// mic) and the assistant's reply appears right there, without opening the app.
///
/// Conforming to `LiveActivityIntent` makes iOS run it inside the app (in the background, starting
/// the app if needed), where the on-device model and your alarms, to-dos and timers live.
struct AskAssistantIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Ask Alarmie"
    static let description = IntentDescription("Type a request to the on-device assistant and get the reply right away, without opening the app.")
    static var openAppWhenRun: Bool { false }

    /// Optional, so running it with nothing filled in (as Control Center does) never fails
    /// before `perform`; the text box is then asked for below.
    @Parameter(title: "Request", requestValueDialog: "What can I do for you?")
    var request: String?

    /// iOS only shows the text box for a parameter that's part of the summary
    /// (otherwise `requestValue` silently does nothing).
    static var parameterSummary: some ParameterSummary {
        Summary("Ask Alarmie \(\.$request)")
    }

    init() {}

    init(request: String) {
        self.request = request
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var text = (request ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            let asked: String? = try await $request.requestValue("What can I do for you?")
            text = (asked ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return .result(dialog: "Okay, never mind.") }

        // When iOS starts the app just for this, its launch code may still be connecting the
        // assistant: give it a moment.
        var ask = await AssistantBridge.ask
        for _ in 0..<20 where ask == nil {
            try? await Task.sleep(for: .milliseconds(100))
            ask = await AssistantBridge.ask
        }
        let reply = await ask?(text) ?? "Open Alarmie once, then try again."
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

import AppIntents
import Foundation
import SwiftUI

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

// MARK: - Control Center popup

/// The Control Center "Live Talk" button: a popup at the top of the screen with the latest
/// messages and a button to type a new one. The app doesn't open.
///
/// `LiveActivityIntent` runs it inside the app in the background, like Ask Assistant.
struct TalkPopupIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Talk to Alarmie"
    static let description = IntentDescription("Shows your conversation with the assistant and lets you type to it, without opening the app.")

    init() {}

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        .result(snippetIntent: TalkSnippetIntent())
    }
}

/// Draws the popup. iOS runs it again after "Type a Message", so new replies appear.
struct TalkSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Talk Conversation"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: TalkSnippetView(messages: TalkSnapshot.load()))
    }
}

/// "Type a Message" in the popup: iOS asks for the text, the assistant answers, and the popup
/// shows the reply.
struct MessageTalkIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Message Alarmie"
    static let isDiscoverable = false

    @Parameter(title: "Message", requestValueDialog: "Message Alarmie")
    var message: String?

    init() {}

    func perform() async throws -> some IntentResult {
        var text = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            let asked: String? = try await $message.requestValue("Message Alarmie")
            text = (asked ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return .result() }
        if let ask = await AssistantBridge.ask {
            _ = await ask(text)
        } else {
            TalkSnapshot.save(TalkSnapshot.load() + [
                TalkSnapshotMessage(role: .user, text: text),
                TalkSnapshotMessage(role: .error, text: "Open Alarmie once, then try again."),
            ])
        }
        return .result()
    }
}

/// The popup: the last few messages as bubbles, then Type a Message and Live Talk.
struct TalkSnippetView: View {
    let messages: [TalkSnapshotMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Alarmie", systemImage: "waveform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            if messages.isEmpty {
                Text("Ask me anything: “wake me up at 7 on weekdays” or “remind me to call mom at 6”.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(messages.suffix(4)) { message in
                    bubble(message)
                }
            }

            HStack(spacing: 8) {
                Button(intent: MessageTalkIntent()) {
                    Label("Type a Message", systemImage: "keyboard")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button(intent: StartLiveTalkIntent()) {
                    Image(systemName: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityLabel("Live Talk in the app")
            }
            .padding(.top, 2)
        }
        .padding()
    }

    @ViewBuilder
    private func bubble(_ message: TalkSnapshotMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        case .assistant, .error:
            HStack {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(message.role == .error ? Color.red : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer(minLength: 40)
            }
        case .event:
            Text(message.text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

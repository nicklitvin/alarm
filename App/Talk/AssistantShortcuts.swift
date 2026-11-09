import AppIntents

/// Also makes the assistant available to Siri, Spotlight, Shortcuts and the Action button.
struct AssistantShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskAssistantIntent(),
            phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) assistant"],
            shortTitle: "Ask Assistant",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: StartLiveTalkIntent(),
            phrases: ["Start \(.applicationName) Live Talk", "Talk to \(.applicationName)"],
            shortTitle: "Live Talk",
            systemImageName: "waveform"
        )
    }
}

import AppIntents
import SwiftUI
import WidgetKit

/// Control Center button: type or dictate a request; the reply pops up at the top of the screen.
struct AskAssistantControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "AskAssistantControl") {
            ControlWidgetButton(action: AskAssistantIntent()) {
                Label("Ask Assistant", systemImage: "sparkles")
            }
        }
        .displayName("Ask Assistant")
        .description("Type or dictate a request: alarms, to-dos, timers and more.")
    }
}

/// Control Center button: opens the app and starts hands-free Live Talk.
struct LiveTalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LiveTalkControl") {
            ControlWidgetButton(action: StartLiveTalkIntent()) {
                Label("Live Talk", systemImage: "waveform")
            }
        }
        .displayName("Live Talk")
        .description("Open the assistant and start talking.")
    }
}

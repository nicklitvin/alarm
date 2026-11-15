import AppIntents
import SwiftUI
import WidgetKit

/// Control Center button: like the Reminders quick add, a text box at the top of the screen to
/// type to the assistant, with its reply shown right there. The app doesn't open.
/// (Same kind as before, so a button already in Control Center switches over by itself.)
struct LiveTalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LiveTalkControl") {
            ControlWidgetButton(action: AskAssistantIntent()) {
                Label("Ask Alarmie", systemImage: "waveform")
            }
        }
        .displayName("Ask Alarmie")
        .description("Type to the assistant from Control Center and get the reply without opening the app.")
    }
}

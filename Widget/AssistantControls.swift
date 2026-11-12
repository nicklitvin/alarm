import AppIntents
import SwiftUI
import WidgetKit

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

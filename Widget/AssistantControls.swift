import AppIntents
import SwiftUI
import WidgetKit

/// Control Center button: a popup at the top of the screen with your conversation and a
/// button to type to the assistant, without opening the app.
struct LiveTalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LiveTalkControl") {
            ControlWidgetButton(action: TalkPopupIntent()) {
                Label("Live Talk", systemImage: "waveform")
            }
        }
        .displayName("Live Talk")
        .description("See your conversation and type to the assistant without opening the app.")
    }
}

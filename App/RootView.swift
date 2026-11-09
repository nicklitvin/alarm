import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Alarms", systemImage: "alarm.fill") {
                AlarmListView()
            }
            Tab("Timers", systemImage: "timer") {
                TimersView()
            }
            Tab("Talk", systemImage: "waveform") {
                TalkView()
            }
        }
        .tint(.orange)
    }
}

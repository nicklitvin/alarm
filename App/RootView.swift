import Observation
import SwiftUI

enum AppTab: Hashable {
    case alarms, timers, todos, talk
}

/// Which tab is showing. Notifications use it to open the right tab.
@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()
    var tab: AppTab = .alarms
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = AppNavigation.shared

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Alarms", systemImage: "alarm.fill", value: AppTab.alarms) {
                AlarmListView()
            }
            Tab("Timers", systemImage: "timer", value: AppTab.timers) {
                TimersView()
            }
            Tab("To-Do", systemImage: "checklist", value: AppTab.todos) {
                TodoListView()
            }
            Tab("Talk", systemImage: "waveform", value: AppTab.talk) {
                TalkView()
            }
        }
        .tint(.orange)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { TodoController.shared.reload() }
        }
    }
}

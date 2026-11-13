import Observation
import SwiftUI

enum AppTab: Hashable {
    case alarms, timers, todos, notes, talk
}

/// Something in the app a chat message can point to: the same places widgets link to.
typealias ChatLink = DeepLink

/// Which tab is showing, and which item to open. Notifications and chat links use it.
@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()
    var tab: AppTab = .alarms
    /// Set to open that item's editor; the tab clears it once shown.
    var pendingAlarmID: UUID?
    var pendingTodoID: UUID?
    var pendingNoteID: UUID?

    func open(_ link: DeepLink) {
        switch link {
        case .alarms:
            tab = .alarms
        case .alarm(let id):
            tab = .alarms
            pendingAlarmID = id
        case .timers:
            tab = .timers
        case .todos:
            tab = .todos
        case .todo(let id):
            tab = .todos
            pendingTodoID = id
        case .notes:
            tab = .notes
        case .talk:
            tab = .talk
        case .note(let id):
            tab = .notes
            pendingNoteID = id
        }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = AppNavigation.shared
    @State private var updates = UpdateChecker.shared

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
            Tab("Notes", systemImage: "note.text", value: AppTab.notes) {
                NotesListView()
            }
            Tab("Talk", systemImage: "waveform", value: AppTab.talk) {
                TalkView()
            }
        }
        .tint(.orange)
        .sheet(item: $updates.updatePrompt) { release in
            UpdatePromptView(release: release)
        }
        .sheet(isPresented: Binding(
            get: { !updates.whatsNew.isEmpty },
            set: { if !$0 { updates.whatsNew = [] } }
        )) {
            WhatsNewView(releases: updates.whatsNew)
        }
        .onOpenURL { url in
            // Taps on widgets: open exactly what was tapped.
            if let link = DeepLink(url: url) { navigation.open(link) }
        }
        .task {
            updates.showWhatsNewIfUpdated()
            updates.checkIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                TodoController.shared.reload()
                Task { await NotificationScheduler.removeDeliveredForRungAlarms() }
                updates.checkIfNeeded()
            }
        }
    }
}

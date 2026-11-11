import Observation
import SwiftUI

enum AppTab: Hashable {
    case alarms, timers, todos, notes, talk
}

/// Something in the app a chat message can point to.
enum ChatLink: Hashable {
    case alarm(UUID)
    case todo(UUID)
    case note(UUID)
    case timers
}

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

    func open(_ link: ChatLink) {
        switch link {
        case .alarm(let id):
            tab = .alarms
            pendingAlarmID = id
        case .todo(let id):
            tab = .todos
            pendingTodoID = id
        case .note(let id):
            tab = .notes
            pendingNoteID = id
        case .timers:
            tab = .timers
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
        .task {
            updates.showWhatsNewIfUpdated()
            updates.checkIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                TodoController.shared.reload()
                updates.checkIfNeeded()
            }
        }
    }
}

import Observation
import SwiftUI
import UIKit
import WidgetKit

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
    /// Set to start a new note (Notes) or open New Timer (Timers); the tab clears it.
    var pendingNewNote = false
    var pendingNewTimer = false
    /// Goes up every time a link is opened (a widget tap, a notification, a chat event). Open
    /// sheets (settings, editors) watch it and close, so the tab underneath shows.
    private(set) var linkOpenCount = 0

    func open(_ link: DeepLink) {
        linkOpenCount += 1
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
        case .liveTalk:
            tab = .talk
            TalkModel.shared.startLive()
        case .note(let id):
            tab = .notes
            pendingNoteID = id
        case .newNote:
            tab = .notes
            pendingNewNote = true
        case .newTimer:
            tab = .timers
            pendingNewTimer = true
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
        // A tab bar on iPhone; a sidebar on iPad and the Mac, where there's room for one.
        .tabViewStyle(.sidebarAdaptable)
        .tint(.orange)
        .onAppear(perform: MacWindow.configure)
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
            // Taps on widgets: open exactly what was tapped. Other apps can open these links too
            // (alarmapp://livetalk starts Live Talk).
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
            if phase == .background {
                Backups.backUpNow()
                WidgetCenter.shared.reloadAllTimelines() // widgets always match what you just did
            }
        }
    }
}

/// The Mac app's window: big enough for the wide layouts (sidebar plus two columns), and the
/// iPhone-style title bar hidden since every tab draws its own header.
enum MacWindow {
    static func configure() {
        #if targetEnvironment(macCatalyst)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = CGSize(width: 820, height: 560)
            scene.titlebar?.titleVisibility = .hidden
            scene.titlebar?.toolbar = nil
        }
        #endif
    }
}

import SwiftUI
import UserNotifications

@main
struct AlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Before anything loads: if the storage is brand new but a backup has data (a reinstall,
        // or a copy signed without the App Group), put the backup back.
        Backups.restoreIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AlarmController.shared)
                .environment(TimerController.shared)
                .environment(TodoController.shared)
                .environment(NotesController.shared)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationScheduler.registerCategories()
        Task { await TimerNotifications.removeLegacyWarnings() }
        BackgroundRefresh.register()
        _ = TimerController.shared
        _ = AlarmController.shared
        _ = TodoController.shared

        // Control Center buttons, Siri and Shortcuts reach the assistant through these.
        AssistantBridge.ask = { request in
            await TalkModel.shared.respond(to: request) ?? "Sorry, I couldn't do that."
        }
        AlarmIntentBridge.dismiss = { id in await AlarmController.shared.dismissNextRing(of: id) }
        AssistantBridge.openLiveTalk = {
            AppNavigation.shared.tab = .talk
            TalkModel.shared.startLive()
        }
        // The Mac app's menu bar item (does nothing on iPhone and iPad).
        MenuBarBridge.install()
        return true
    }

    /// Show the heads-up banner even while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Handles notification taps and actions. Action buttons run with the app in the background.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let userInfo = content.userInfo

        switch response.actionIdentifier {
        case NotificationScheduler.dismissActionID:
            guard let id = (userInfo[NotificationScheduler.alarmIDKey] as? String).flatMap(UUID.init(uuidString:)) else { return }
            await AlarmController.shared.dismissNextRing(of: id, referenceDate: response.notification.date)

        case TodoReminders.doneActionID:
            guard let id = (userInfo[TodoReminders.todoIDKey] as? String).flatMap(UUID.init(uuidString:)) else { return }
            await TodoController.shared.setDone(true, for: id)

        case TodoReminders.snoozeActionID:
            guard let id = (userInfo[TodoReminders.todoIDKey] as? String).flatMap(UUID.init(uuidString:)) else { return }
            await TodoController.shared.snooze(id)

        case TodoReminders.snoozeDayActionID:
            guard let id = (userInfo[TodoReminders.todoIDKey] as? String).flatMap(UUID.init(uuidString:)) else { return }
            await TodoController.shared.snooze(id, by: 24 * 3600)

        case UNNotificationDefaultActionIdentifier:
            // Tapping opens the app: the alarm heads-up opens the Alarms tab, where the Dismiss
            // card is already showing; a to-do's opens that to-do.
            let todoID = (userInfo[TodoReminders.todoIDKey] as? String).flatMap(UUID.init(uuidString:))
            await MainActor.run {
                if content.categoryIdentifier == TodoReminders.categoryID {
                    AppNavigation.shared.open(todoID.map(DeepLink.todo) ?? .todos)
                } else {
                    AppNavigation.shared.open(.alarms)
                }
            }

        default:
            break
        }
    }
}

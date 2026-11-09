import SwiftUI
import UserNotifications

@main
struct AlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AlarmController.shared)
                .environment(TimerController.shared)
                .environment(TodoController.shared)
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
        BackgroundRefresh.register()
        _ = TimerController.shared
        _ = AlarmController.shared
        _ = TodoController.shared
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

        case UNNotificationDefaultActionIdentifier:
            await MainActor.run {
                AppNavigation.shared.tab = content.categoryIdentifier == TodoReminders.categoryID ? .todos : .alarms
            }

        default:
            break
        }
    }
}

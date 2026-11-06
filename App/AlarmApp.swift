import SwiftUI
import UserNotifications

@main
struct AlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AlarmListView()
                .environment(AlarmController.shared)
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
        _ = AlarmController.shared
        return true
    }

    /// Show the heads-up banner even while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Handles "Dismiss Alarm" on the heads-up notification. The app runs in the background for this.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == NotificationScheduler.dismissActionID else { return }
        let userInfo = response.notification.request.content.userInfo
        guard let idString = userInfo[NotificationScheduler.alarmIDKey] as? String,
              let id = UUID(uuidString: idString) else { return }
        let deliveredAt = response.notification.date
        await AlarmController.shared.dismissNextRing(of: id, referenceDate: deliveredAt)
    }
}

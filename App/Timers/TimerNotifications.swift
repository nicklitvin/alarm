import Foundation
import UserNotifications

/// Timers have no notifications of their own any more (they ring through AlarmKit). This only
/// clears "1 minute left" warnings that older versions scheduled.
enum TimerNotifications {
    private static let prefix = "timer-warning."

    static func removeLegacyWarnings() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }
}

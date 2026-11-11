import Foundation
import UserNotifications

/// Optional "1 minute left" style notification before a timer ends (Timers settings).
/// The timer itself rings through AlarmKit; this is only an early nudge.
enum TimerNotifications {
    private static let prefix = "timer-warning."

    static func sync(_ timers: [TimerItem], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let minutes = AppSettings.timerWarningMinutes
        guard minutes > 0 else { return }
        let lead = TimeInterval(minutes * 60)

        for timer in timers where timer.state == .running {
            let when = timer.fireDate.addingTimeInterval(-lead)
            // Only useful when the timer is noticeably longer than the warning.
            guard when > now.addingTimeInterval(5), timer.duration > lead * 2 else { continue }

            let content = UNMutableNotificationContent()
            content.title = timer.title
            content.body = "\(AppSettings.leadTimeName(minutes)) left"
            content.sound = .default
            content.threadIdentifier = "timers"
            content.interruptionLevel = .timeSensitive

            let request = UNNotificationRequest(
                identifier: prefix + timer.id.uuidString,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: when.timeIntervalSince(now), repeats: false)
            )
            try? await center.add(request)
        }
    }
}

import Foundation
import UserNotifications

/// Schedules a heads-up notification 1 hour before each alarm, with a "Dismiss Alarm" action.
enum NotificationScheduler {
    static let categoryID = "ALARM_HEADS_UP"
    static let dismissActionID = "DISMISS_NEXT_ALARM"
    static let alarmIDKey = "alarmID"
    private static let idPrefix = "heads-up."

    static func registerCategories() {
        let dismiss = UNNotificationAction(
            identifier: dismissActionID,
            title: "Dismiss Alarm",
            options: [.destructive],
            icon: UNNotificationActionIcon(systemImageName: "alarm")
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [dismiss],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category, TodoReminders.category])
    }

    static func sync(_ alarms: [AlarmItem], now: Date = .now) async {
        let center = UNUserNotificationCenter.current()

        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        )

        for alarm in alarms where alarm.isEnabled {
            for request in requests(for: alarm, now: now) {
                do { try await center.add(request) } catch { print("Notification scheduling failed: \(error)") }
            }
        }
    }

    /// Clears an already-delivered heads-up for an alarm (e.g. after dismissing it in the app).
    static func removeDelivered(for alarmID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.deliveredNotifications()
            .filter { ($0.request.content.userInfo[alarmIDKey] as? String) == alarmID.uuidString }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: - Private

    private static func requests(for alarm: AlarmItem, now: Date, calendar: Calendar = .current) -> [UNNotificationRequest] {
        let content = makeContent(for: alarm)
        let leadMinutes = Int(AlarmItem.headsUpInterval / 60)

        if alarm.isRepeating {
            // One repeating trigger per weekday, 1 hour earlier (rolling back a day past midnight).
            return alarm.weekdays.map { day in
                var minutes = alarm.hour * 60 + alarm.minute - leadMinutes
                var weekday = day.rawValue
                if minutes < 0 {
                    minutes += 24 * 60
                    weekday = weekday == 1 ? 7 : weekday - 1
                }
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60, weekday: weekday),
                    repeats: true
                )
                return UNNotificationRequest(
                    identifier: "\(idPrefix)\(alarm.id.uuidString).\(day.rawValue)",
                    content: content,
                    trigger: trigger
                )
            }
        }

        guard let fireDate = alarm.oneTimeDate else { return [] }
        let headsUp = fireDate.addingTimeInterval(-AlarmItem.headsUpInterval)
        guard headsUp > now else { return [] }
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: headsUp),
            repeats: false
        )
        return [UNNotificationRequest(identifier: "\(idPrefix)\(alarm.id.uuidString).once", content: content, trigger: trigger)]
    }

    private static func makeContent(for alarm: AlarmItem) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Alarm in 1 hour"
        if !alarm.label.trimmingCharacters(in: .whitespaces).isEmpty {
            content.subtitle = alarm.title
        }
        content.body = "Rings at \(alarm.timeString). Touch and hold to dismiss it."
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.threadIdentifier = "alarm-heads-up"
        content.interruptionLevel = .timeSensitive
        content.userInfo = [alarmIDKey: alarm.id.uuidString]
        return content
    }
}

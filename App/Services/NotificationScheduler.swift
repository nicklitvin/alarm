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

    /// Schedules all heads-ups. Returns whether notifications are allowed.
    @discardableResult
    static func sync(_ alarms: [AlarmItem], now: Date = .now) async -> Bool {
        let center = UNUserNotificationCenter.current()

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        let allowed = [.authorized, .provisional, .ephemeral].contains(status)

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        )

        // Heads-ups can be turned off in Alarm settings.
        guard AppSettings.alarmHeadsUpEnabled else { return allowed }

        for alarm in alarms where alarm.isEnabled {
            for request in requests(for: alarm, now: now) {
                do { try await center.add(request) } catch { print("Notification scheduling failed: \(error)") }
            }
        }

        await sendMissedHeadsUps(for: alarms, now: now, center: center)
        return allowed
    }

    /// The regular heads-up fires exactly 1 hour before. An alarm created (or turned on, or moved)
    /// less than an hour before it rings would never get one, so send it right away instead.
    /// Each ring only ever gets one heads-up.
    private static func sendMissedHeadsUps(for alarms: [AlarmItem], now: Date, center: UNUserNotificationCenter) async {
        let defaults = UserDefaults.standard
        var sent = Set(defaults.stringArray(forKey: sentKey) ?? [])
        let delivered = await center.deliveredNotifications()

        for alarm in alarms where alarm.isEnabled {
            guard let ring = alarm.nextFireDate(after: now) else { continue }
            let lead = ring.timeIntervalSince(now)
            guard lead > 60, lead <= AlarmItem.headsUpInterval else { continue }

            let key = "\(alarm.id.uuidString)|\(Int(ring.timeIntervalSince1970))"
            guard !sent.contains(key) else { continue }
            sent.insert(key)

            // The scheduled heads-up already showed for this ring.
            let alreadyShown = delivered.contains {
                ($0.request.content.userInfo[alarmIDKey] as? String) == alarm.id.uuidString
                    && $0.date >= ring.addingTimeInterval(-AlarmItem.headsUpInterval - 120)
            }
            guard !alreadyShown else { continue }

            let content = makeContent(for: alarm)
            let minutes = max(1, Int((lead / 60).rounded(.up)))
            content.title = "Alarm in \(minutes) min"
            let request = UNNotificationRequest(
                identifier: "\(immediatePrefix)\(alarm.id.uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            try? await center.add(request)
        }
        // Forget rings that are long past.
        let cutoff = now.addingTimeInterval(-24 * 3600).timeIntervalSince1970
        let recent = sent.filter { key in
            key.split(separator: "|").last.flatMap { Double($0) }.map { $0 > cutoff } ?? false
        }
        defaults.set(Array(recent), forKey: sentKey)
    }

    /// Separate prefix so a sync a moment later doesn't cancel it before it shows.
    private static let immediatePrefix = "heads-up-now."
    private static let sentKey = "notifications.immediateHeadsUpsSent"

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
        content.title = "Alarm in \(AppSettings.leadTimeName(AppSettings.alarmHeadsUpMinutes))"
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

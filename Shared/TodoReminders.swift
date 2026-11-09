import Foundation
import UserNotifications

/// A notification at each to-do's deadline, with "Done" and "Remind Me in 1 Hour" actions.
/// Shared so the widget can update a reminder when a to-do is checked off there.
enum TodoReminders {
    static let categoryID = "TODO_DUE"
    static let doneActionID = "TODO_DONE"
    static let snoozeActionID = "TODO_SNOOZE"
    static let todoIDKey = "todoID"
    private static let idPrefix = "todo."
    /// iOS allows 64 pending notifications per app; leave plenty of room for alarms.
    private static let maxPending = 30

    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryID,
            actions: [
                UNNotificationAction(identifier: doneActionID, title: "Mark as Done", options: [],
                                     icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")),
                UNNotificationAction(identifier: snoozeActionID, title: "Remind Me in 1 Hour", options: [],
                                     icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath")),
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    static func identifier(for id: UUID) -> String { idPrefix + id.uuidString }

    /// Replaces all to-do reminders with ones for the soonest open to-dos.
    static func sync(_ todos: [TodoItem], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        )
        let upcoming = todos
            .filter { !$0.isDone && ($0.due ?? .distantPast) > now }
            .sorted { $0.due! < $1.due! }
            .prefix(maxPending)
        for todo in upcoming {
            if let request = request(for: todo, now: now) {
                try? await center.add(request)
            }
        }
    }

    /// Updates the reminder for a single to-do.
    static func update(_ todo: TodoItem, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: todo.id)])
        center.removeDeliveredNotifications(withIdentifiers: [identifier(for: todo.id)])
        if let request = request(for: todo, now: now) {
            try? await center.add(request)
        }
    }

    private static func request(for todo: TodoItem, now: Date) -> UNNotificationRequest? {
        guard !todo.isDone, let due = todo.due, due > now else { return nil }

        let content = UNMutableNotificationContent()
        content.title = todo.title
        content.body = "Due now · \(TimeFormat.string(for: due))"
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.threadIdentifier = "todos"
        content.interruptionLevel = .timeSensitive
        content.userInfo = [todoIDKey: todo.id.uuidString]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
        return UNNotificationRequest(
            identifier: identifier(for: todo.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }
}

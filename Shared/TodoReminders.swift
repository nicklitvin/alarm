import Foundation
import UserNotifications

/// A notification at each to-do's deadline, with "Done", "Remind Me in 1 Hour" and "Remind Me Tomorrow" actions.
/// Shared so the widget can update a reminder when a to-do is checked off there.
enum TodoReminders {
    static let categoryID = "TODO_DUE"
    static let doneActionID = "TODO_DONE"
    static let snoozeActionID = "TODO_SNOOZE"
    static let snoozeDayActionID = "TODO_SNOOZE_DAY"
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
                UNNotificationAction(identifier: snoozeDayActionID, title: "Remind Me Tomorrow", options: [],
                                     icon: UNNotificationActionIcon(systemImageName: "sunrise")),
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
            // Each to-do can use two notifications when early reminders are on.
            .prefix(AppSettings.todoEarlyReminderMinutes > 0 ? maxPending / 2 : maxPending)
        for todo in upcoming {
            for request in requests(for: todo, now: now) {
                try? await center.add(request)
            }
        }
    }

    /// Updates the reminder for a single to-do.
    static func update(_ todo: TodoItem, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let ids = [identifier(for: todo.id), earlyIdentifier(for: todo.id)]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        for request in requests(for: todo, now: now) {
            try? await center.add(request)
        }
    }

    private static func earlyIdentifier(for id: UUID) -> String { identifier(for: id) + ".early" }

    /// The at-deadline alert and the optional earlier reminder, per To-Do settings.
    private static func requests(for todo: TodoItem, now: Date) -> [UNNotificationRequest] {
        guard !todo.isDone, let due = todo.due, due > now else { return [] }
        var result: [UNNotificationRequest] = []

        if AppSettings.todoDueAlertEnabled {
            result.append(request(id: identifier(for: todo.id), todo: todo, at: due,
                                  body: "Due now · \(TimeFormat.string(for: due))"))
        }
        let early = AppSettings.todoEarlyReminderMinutes
        if early > 0 {
            let when = due.addingTimeInterval(-TimeInterval(early * 60))
            if when > now {
                result.append(request(id: earlyIdentifier(for: todo.id), todo: todo, at: when,
                                      body: "Due in \(AppSettings.leadTimeName(early)) · \(TimeFormat.dueDescription(due, relativeTo: when))"))
            }
        }
        return result
    }

    private static func request(id: String, todo: TodoItem, at date: Date, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = todo.title
        content.body = todo.trimmedDetails.isEmpty ? body : "\(body)\n\(todo.trimmedDetails)"
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.threadIdentifier = "todos"
        content.interruptionLevel = .timeSensitive
        content.userInfo = [todoIDKey: todo.id.uuidString]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }
}

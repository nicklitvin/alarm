import BackgroundTasks
import Foundation

/// Asks iOS for background time just after a dismissed ring, so that day's weekly alarm
/// is restored right away, without the user opening the app.
enum BackgroundRefresh {
    static var taskID: String { (Bundle.main.bundleIdentifier ?? "alarm") + ".refresh" }

    /// Must be called before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            let work = Task { @MainActor in
                await NotificationScheduler.removeDeliveredForRungAlarms()
                await AlarmController.shared.reconcile()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Schedules (or clears, when `date` is nil) the next refresh.
    static func schedule(at date: Date?) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
        guard let date else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = date
        do { try BGTaskScheduler.shared.submit(request) } catch { print("Background refresh not scheduled: \(error)") }
    }
}

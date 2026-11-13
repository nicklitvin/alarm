import AlarmKit
import AppIntents
import Foundation

/// Runs in the app's process when the user taps Stop on a ringing alarm.
/// Besides stopping it, this re-syncs everything. That brings back the weekly alarm
/// for a day whose ring was dismissed, and turns off one-time alarms that just rang.
struct StopAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Alarm"
    static let description = IntentDescription("Stops a ringing alarm.")
    static var isDiscoverable: Bool { false }

    /// The AlarmKit alarm ID (not the app's own alarm ID).
    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() { alarmID = "" }

    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: id)
        }
        await NotificationScheduler.removeDeliveredForRungAlarms()
        await AlarmController.shared.reconcile()
        return .result()
    }
}

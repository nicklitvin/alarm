import AppIntents
import Foundation

/// Dismiss the next ring of an alarm from the widget.
/// `LiveActivityIntent` makes iOS run these inside the app, where AlarmKit scheduling lives.
enum AlarmIntentBridge {
    @MainActor static var dismiss: ((UUID) async -> Void)?
}

struct DismissNextAlarmIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Dismiss Next Alarm"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID") var alarmID: String

    init() { alarmID = "" }
    init(alarmID: UUID) { self.alarmID = alarmID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID), let dismiss = await AlarmIntentBridge.dismiss else { return .result() }
        await dismiss(id)
        return .result()
    }
}

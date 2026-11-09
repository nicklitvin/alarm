import AlarmKit
import Foundation

/// Metadata attached to every AlarmKit alarm and timer we schedule.
/// Shared with the widget extension, which shows timers as Live Activities.
struct AlarmPayload: AlarmMetadata {
    var alarmID: UUID
    var label: String = ""
    var isTimer: Bool = false
}

import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

/// Metadata attached to every system alarm we schedule.
struct AlarmPayload: AlarmMetadata {
    var alarmID: UUID
}

/// Mirrors the app's alarms into AlarmKit, so they ring like real Clock alarms
/// (full-screen on the lock screen, through Silent mode and Focus).
@MainActor
final class AlarmKitScheduler {
    private let manager = AlarmManager.shared

    func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await manager.requestAuthorization()) == .authorized
        @unknown default:
            return false
        }
    }

    /// Makes the system's scheduled alarms match `alarms`. Returns whether AlarmKit is authorized.
    @discardableResult
    func sync(_ alarms: [AlarmItem], now: Date = .now) async -> Bool {
        guard await requestAuthorization() else { return false }

        let plan = AlarmPlan.make(for: alarms, now: now)
        let existing = (try? manager.alarms) ?? []

        // Cancel anything no longer wanted, but never interrupt an alarm that is ringing right now.
        for alarm in existing where plan[alarm.id] == nil && alarm.state != .alerting {
            do { try manager.cancel(id: alarm.id) } catch { print("AlarmKit cancel failed: \(error)") }
        }

        let existingIDs = Set(existing.map(\.id))
        for (id, planned) in plan where !existingIDs.contains(id) {
            do {
                _ = try await manager.schedule(id: id, configuration: configuration(for: planned, id: id))
            } catch {
                print("AlarmKit schedule failed for \(planned.key): \(error)")
            }
        }
        return true
    }

    private func configuration(for planned: PlannedAlarm, id: UUID) -> AlarmManager.AlarmConfiguration<AlarmPayload> {
        let item = planned.item

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: item.title),
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let attributes = AlarmAttributes<AlarmPayload>(
            presentation: AlarmPresentation(alert: alert),
            metadata: AlarmPayload(alarmID: item.id),
            tintColor: .orange
        )

        let schedule: Alarm.Schedule
        switch planned.kind {
        case .weekly(let day):
            schedule = .relative(Alarm.Schedule.Relative(
                time: Alarm.Schedule.Relative.Time(hour: item.hour, minute: item.minute),
                repeats: .weekly([day.localeWeekday])
            ))
        case .once(let date):
            schedule = .fixed(date)
        }

        return AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id),
            secondaryIntent: nil,
            sound: .default
        )
    }
}

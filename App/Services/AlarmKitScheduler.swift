#if !targetEnvironment(macCatalyst)
import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

/// Mirrors the app's alarms into AlarmKit, so they ring like real Clock alarms
/// (full-screen on the lock screen, through Silent mode and Focus).
@MainActor
final class AlarmKitScheduler {
    private let manager = AlarmManager.shared

    func requestAuthorization() async -> Bool {
        await Self.ensureAuthorized()
    }

    /// Asks for AlarmKit permission if needed. Shared by alarms and timers.
    static func ensureAuthorized() async -> Bool {
        let manager = AlarmManager.shared
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

        // Cancel alarms no longer wanted. Only ever touch ones that are waiting to ring: never one
        // that is ringing right now, and never a timer (timers are always counting down or paused).
        let timerIDs = TimerController.shared.timerIDs
        for alarm in existing where plan[alarm.id] == nil && alarm.state == .scheduled && !timerIDs.contains(alarm.id) {
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
            metadata: AlarmPayload(alarmID: item.id, label: item.title, isTimer: false),
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
            sound: item.sound.fileName.map { .named($0) } ?? .default
        )
    }
}
#else
import Foundation
import UserNotifications

/// The Mac (Catalyst) build has no AlarmKit, so alarms ring as time-sensitive notifications with
/// the alarm's sound, scheduled from the same plan (including a dismissed ring). They show while
/// the Mac is awake; a sleeping Mac won't wake up for them, so the iPhone stays the alarm clock.
@MainActor
final class AlarmKitScheduler {
    private static let prefix = "alarmie.ring."

    func requestAuthorization() async -> Bool {
        await Self.ensureAuthorized()
    }

    /// Asks for notification permission if needed. Shared by alarms and timers.
    static func ensureAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    /// Makes the scheduled alarm notifications match `alarms`. Returns whether notifications are allowed.
    @discardableResult
    func sync(_ alarms: [AlarmItem], now: Date = .now) async -> Bool {
        guard await requestAuthorization() else { return false }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        for (id, planned) in AlarmPlan.make(for: alarms, now: now) {
            let item = planned.item
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = "Alarm · \(item.timeString)"
            content.interruptionLevel = .timeSensitive
            content.sound = item.sound.fileName.map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
            let trigger: UNNotificationTrigger
            switch planned.kind {
            case .weekly(let day):
                trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: item.hour, minute: item.minute, weekday: day.rawValue), repeats: true)
            case .once(let date):
                trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
            }
            try? await center.add(UNNotificationRequest(identifier: Self.prefix + id.uuidString, content: content, trigger: trigger))
        }
        return true
    }
}
#endif

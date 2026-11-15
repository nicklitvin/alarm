#if !targetEnvironment(macCatalyst)
import ActivityKit
import AlarmKit
#endif
import Foundation
import UserNotifications
import Observation
import SwiftUI
import WidgetKit

enum TimerError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        #if targetEnvironment(macCatalyst)
        "Allow notifications for Alarmie in System Settings so timers can ring."
        #else
        "Allow alarms for this app in Settings so timers can ring."
        #endif
    }
}

/// Countdown timers backed by AlarmKit, so they ring through Silent mode and show a
/// Live Activity on the lock screen and Dynamic Island. The Mac (Catalyst) build has no AlarmKit:
/// there a timer is a notification with sound at its end (see the `MacTimers` extension).
@MainActor
@Observable
final class TimerController {
    static let shared = TimerController()

    private(set) var timers: [TimerItem]
    /// Timers used before, newest first (the Recents list).
    private(set) var recents: [RecentTimer]

    #if !targetEnvironment(macCatalyst)
    @ObservationIgnored private let manager = AlarmManager.shared
    #endif
    @ObservationIgnored private var pendingIDs: Set<UUID> = []
    @ObservationIgnored private var observation: Task<Void, Never>?

    var timerIDs: Set<UUID> { Set(timers.map(\.id)) }

    private init() {
        timers = TimerStorage.load()
        recents = RecentTimerStorage.load()

        TimerIntentRunner.handler = { [weak self] action, id in
            guard let self else { return }
            switch action {
            case .pause: self.pause(id)
            case .resume: self.resume(id)
            case .cancel: self.cancel(id)
            }
        }

        #if targetEnvironment(macCatalyst)
        // No AlarmKit to report a finished timer: check once a second.
        observation = Task { [weak self] in
            while !Task.isCancelled {
                self?.markFinishedTimers()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        #else
        observation = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                self?.reconcile(with: alarms)
                // An alarm started ringing: its "Alarm in 1 hour" heads-up is out of date.
                if alarms.contains(where: { $0.state == .alerting }) {
                    await NotificationScheduler.removeDeliveredForRungAlarms()
                }
            }
        }
        #endif
    }

    // MARK: - Actions

    @discardableResult
    func start(duration: TimeInterval, label: String = "") async throws -> TimerItem {
        guard await AlarmKitScheduler.ensureAuthorized() else { throw TimerError.notAuthorized }

        let duration = max(1, duration.rounded())
        let item = TimerItem(
            id: UUID(),
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            state: .running,
            fireDate: Date().addingTimeInterval(duration),
            remaining: duration
        )

        pendingIDs.insert(item.id)
        defer { pendingIDs.remove(item.id) }
        timers.append(item)
        save()

        do {
            #if targetEnvironment(macCatalyst)
            try await MacTimers.schedule(item)
            #else
            _ = try await manager.schedule(id: item.id, configuration: Self.configuration(for: item))
            #endif
        } catch {
            timers.removeAll { $0.id == item.id }
            save()
            throw error
        }
        recents = RecentTimer.adding(RecentTimer(duration: item.duration, label: item.label), to: recents)
        RecentTimerStorage.save(recents)
        return item
    }

    func pause(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), timers[index].state == .running else { return }
        #if targetEnvironment(macCatalyst)
        MacTimers.unschedule(id)
        #else
        try? manager.pause(id: id)
        #endif
        timers[index].remaining = timers[index].timeLeft(at: .now)
        timers[index].state = .paused
        save()
    }

    func resume(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), timers[index].state == .paused else { return }
        #if !targetEnvironment(macCatalyst)
        try? manager.resume(id: id)
        #endif
        timers[index].fireDate = Date().addingTimeInterval(timers[index].remaining)
        timers[index].state = .running
        #if targetEnvironment(macCatalyst)
        let resumed = timers[index]
        Task { try? await MacTimers.schedule(resumed) }
        #endif
        save()
    }

    /// Cancels a running or paused timer, or silences one that is ringing.
    func cancel(_ id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        #if targetEnvironment(macCatalyst)
        _ = timer
        MacTimers.unschedule(id)
        #else
        if timer.state == .ringing {
            try? manager.stop(id: id)
        } else {
            try? manager.cancel(id: id)
        }
        #endif
        timers.removeAll { $0.id == id }
        save()
    }

    /// The last three different times used, for the New Timer sheet. Filled in with
    /// 5, 10 and 15 minutes until you've used three.
    var recentTimes: [RecentTimer] { RecentTimer.latestTimes(from: recents) }

    /// What New Timer offers: the quick times, or the recent times (Timer settings).
    var newTimerChoices: [RecentTimer] {
        RecentTimer.newTimerChoices(recents: recents, quickTimes: AppSettings.timerQuickTimes,
                                    useRecent: AppSettings.timerUsesRecentTimes)
    }

    func removeRecent(_ recent: RecentTimer) {
        recents.removeAll { $0.id == recent.id }
        RecentTimerStorage.save(recents)
    }

    /// Settings → Delete All Timers: cancels running timers and clears Recents.
    func deleteAll() {
        cancelAll()
        recents = []
        RecentTimerStorage.save(recents)
    }

    func cancelAll() {
        timers.map(\.id).forEach(cancel)
    }

    // MARK: - Sync with AlarmKit

    #if !targetEnvironment(macCatalyst)
    /// Mirrors state changes made outside the app (Live Activity buttons, timer finishing, Stop tapped).
    private func reconcile(with alarms: [Alarm]) {
        let byID = Dictionary(alarms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let now = Date()
        var updated: [TimerItem] = []

        for var timer in timers {
            guard let alarm = byID[timer.id] else {
                // Gone from AlarmKit: finished and stopped, or cancelled. Keep it if it's still being scheduled.
                if pendingIDs.contains(timer.id) { updated.append(timer) }
                continue
            }
            switch alarm.state {
            case .countdown where timer.state != .running:
                timer.fireDate = now.addingTimeInterval(timer.timeLeft(at: now))
                timer.state = .running
            case .paused where timer.state != .paused:
                timer.remaining = timer.timeLeft(at: now)
                timer.state = .paused
            case .alerting:
                timer.state = .ringing
            default:
                break
            }
            updated.append(timer)
        }

        if updated != timers {
            timers = updated
            save()
        }
    }

    #endif

    private func save() {
        TimerStorage.save(timers)
        WidgetCenter.shared.reloadAllTimelines()
    }

    #if !targetEnvironment(macCatalyst)
    private static func configuration(for item: TimerItem) -> AlarmManager.AlarmConfiguration<AlarmPayload> {
        let title = LocalizedStringResource(stringLiteral: item.title)

        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let countdown = AlarmPresentation.Countdown(
            title: title,
            pauseButton: AlarmButton(text: "Pause", textColor: .orange, systemImageName: "pause.fill")
        )
        let paused = AlarmPresentation.Paused(
            title: "Paused",
            resumeButton: AlarmButton(text: "Resume", textColor: .orange, systemImageName: "play.fill")
        )
        let attributes = AlarmAttributes<AlarmPayload>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
            metadata: AlarmPayload(alarmID: item.id, label: item.title, isTimer: true),
            tintColor: .orange
        )

        return AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: item.duration, postAlert: nil),
            schedule: nil,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: item.id),
            secondaryIntent: nil,
            sound: .default
        )
    }
    #endif
}

#if targetEnvironment(macCatalyst)
/// Timers on the Mac: a notification with sound when the time is up (no AlarmKit there).
@MainActor
private enum MacTimers {
    static func identifier(_ id: UUID) -> String { "alarmie.timer.\(id.uuidString)" }

    static func schedule(_ item: TimerItem) async throws {
        guard await AlarmKitScheduler.ensureAuthorized() else { throw TimerError.notAuthorized }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = "Time's up"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let seconds = max(1, item.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier(item.id), content: content, trigger: trigger))
    }

    static func unschedule(_ id: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(id)])
        center.removeDeliveredNotifications(withIdentifiers: [identifier(id)])
    }
}

extension TimerController {
    /// Running timers whose time is up show as ringing ("Time's up") until you stop them.
    fileprivate func markFinishedTimers() {
        let now = Date()
        guard timers.contains(where: { $0.state == .running && $0.fireDate <= now }) else { return }
        for index in timers.indices where timers[index].state == .running && timers[index].fireDate <= now {
            timers[index].state = .ringing
        }
        save() // private, but reachable from an extension in this file

    }
}
#endif

import ActivityKit
import AlarmKit
import Foundation
import Observation
import SwiftUI
import WidgetKit

enum TimerError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        "Allow alarms for this app in Settings so timers can ring."
    }
}

/// Countdown timers backed by AlarmKit, so they ring through Silent mode and show a
/// Live Activity on the lock screen and Dynamic Island.
@MainActor
@Observable
final class TimerController {
    static let shared = TimerController()

    private(set) var timers: [TimerItem]
    /// Timers used before, newest first (the Recents list).
    private(set) var recents: [RecentTimer]

    @ObservationIgnored private let manager = AlarmManager.shared
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

        observation = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                self?.reconcile(with: alarms)
                // An alarm started ringing: its "Alarm in 1 hour" heads-up is out of date.
                if alarms.contains(where: { $0.state == .alerting }) {
                    await NotificationScheduler.removeDeliveredForRungAlarms()
                }
            }
        }
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
            _ = try await manager.schedule(id: item.id, configuration: Self.configuration(for: item))
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
        try? manager.pause(id: id)
        timers[index].remaining = timers[index].timeLeft(at: .now)
        timers[index].state = .paused
        save()
    }

    func resume(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), timers[index].state == .paused else { return }
        try? manager.resume(id: id)
        timers[index].fireDate = Date().addingTimeInterval(timers[index].remaining)
        timers[index].state = .running
        save()
    }

    /// Cancels a running or paused timer, or silences one that is ringing.
    func cancel(_ id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        if timer.state == .ringing {
            try? manager.stop(id: id)
        } else {
            try? manager.cancel(id: id)
        }
        timers.removeAll { $0.id == id }
        save()
    }

    /// The last three different times used, for the New Timer sheet. Filled in with
    /// 5, 10 and 15 minutes until you've used three.
    var recentTimes: [RecentTimer] { RecentTimer.latestTimes(from: recents) }

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

    private func save() {
        TimerStorage.save(timers)
        WidgetCenter.shared.reloadAllTimelines()
    }

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
}

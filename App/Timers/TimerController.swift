import ActivityKit
import AlarmKit
import Foundation
import Observation
import SwiftUI

struct TimerItem: Identifiable, Codable, Hashable {
    enum State: String, Codable {
        case running, paused, ringing
    }

    var id: UUID
    var label: String
    var duration: TimeInterval
    var state: State
    /// When it goes off (meaningful while running).
    var fireDate: Date
    /// Time left (meaningful while paused).
    var remaining: TimeInterval

    var title: String { label.isEmpty ? TimeFormat.durationName(duration) : label }

    func timeLeft(at date: Date) -> TimeInterval {
        switch state {
        case .running: max(0, fireDate.timeIntervalSince(date))
        case .paused: remaining
        case .ringing: 0
        }
    }
}

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

    @ObservationIgnored private let manager = AlarmManager.shared
    @ObservationIgnored private var pendingIDs: Set<UUID> = []
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private static let storageKey = "timers.v1"

    var timerIDs: Set<UUID> { Set(timers.map(\.id)) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([TimerItem].self, from: data) {
            timers = saved
        } else {
            timers = []
        }

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
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
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

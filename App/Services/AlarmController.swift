import Foundation
import Observation
import WidgetKit

/// A ring that is less than an hour away (or was dismissed and would have been).
struct SoonAlarm: Identifiable, Hashable {
    let alarm: AlarmItem
    let date: Date
    let isDismissed: Bool
    var id: UUID { alarm.id }
}

/// Holds the alarm list. Every change is saved and synced to AlarmKit,
/// the heads-up notifications and the lock screen widget.
@MainActor
@Observable
final class AlarmController {
    static let shared = AlarmController()

    private(set) var alarms: [AlarmItem]
    private(set) var isAuthorized = true

    @ObservationIgnored private let scheduler = AlarmKitScheduler()
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    private init() {
        alarms = AlarmStorage.load()
        refresh()
    }

    var sortedAlarms: [AlarmItem] {
        alarms.sorted { ($0.hour, $0.minute, $0.label) < ($1.hour, $1.minute, $1.label) }
    }

    func nextFire(now: Date) -> UpcomingAlarm? {
        alarms.nextFire(after: now)
    }

    /// Alarms ringing within the next hour — these get a Dismiss button in the app.
    func soonAlarms(now: Date) -> [SoonAlarm] {
        alarms.compactMap { alarm -> SoonAlarm? in
            guard alarm.isEnabled else { return nil }
            if let skipped = alarm.skippedOccurrence, skipped > now,
               skipped.timeIntervalSince(now) <= AlarmItem.headsUpInterval {
                return SoonAlarm(alarm: alarm, date: skipped, isDismissed: true)
            }
            if let next = alarm.nextFireDate(after: now), next.timeIntervalSince(now) <= AlarmItem.headsUpInterval {
                return SoonAlarm(alarm: alarm, date: next, isDismissed: false)
            }
            return nil
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Editing

    func save(_ alarm: AlarmItem) {
        var alarm = alarm
        alarm.isEnabled = true
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            let old = alarms[index]
            if old.hour != alarm.hour || old.minute != alarm.minute || old.weekdays != alarm.weekdays {
                alarm.skippedOccurrence = nil
            }
            alarms[index] = prepared(alarm)
        } else {
            alarms.append(prepared(alarm))
        }
        commit()
    }

    func delete(_ id: UUID) {
        alarms.removeAll { $0.id == id }
        commit()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].isEnabled = enabled
        alarms[index].skippedOccurrence = nil
        alarms[index] = prepared(alarms[index])
        commit()
    }

    // MARK: - Dismissing the next ring

    /// Cancels the next ring of an alarm if it is within the next hour.
    ///
    /// - Parameter referenceDate: when the request was made. For the notification action this is
    ///   the time the heads-up was delivered, so a late tap never skips the *following* ring.
    func dismissNextRing(of id: UUID, referenceDate: Date = .now) async {
        let now = Date()
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        let alarm = alarms[index]
        guard alarm.isEnabled,
              let ring = alarm.nextFireDate(after: min(referenceDate, now)),
              ring > now,
              ring.timeIntervalSince(referenceDate) <= AlarmItem.headsUpInterval + 60
        else { return }

        if alarm.isRepeating {
            alarms[index].skippedOccurrence = ring
        } else {
            alarms[index].isEnabled = false
            alarms[index].oneTimeDate = nil
        }
        await commit().value
        await NotificationScheduler.removeDelivered(for: id)
    }

    func undoDismiss(of id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }),
              alarms[index].skippedOccurrence != nil else { return }
        alarms[index].skippedOccurrence = nil
        commit()
    }

    // MARK: - Housekeeping

    /// Clears dismissals that have passed, turns off one-time alarms that already rang,
    /// and re-syncs everything. Called on launch, when the app comes to the foreground,
    /// when an alarm is stopped and on background refresh.
    @discardableResult
    func refresh(now: Date = .now) -> Task<Void, Never> {
        for index in alarms.indices {
            if let skipped = alarms[index].skippedOccurrence, skipped <= now {
                alarms[index].skippedOccurrence = nil
            }
            if alarms[index].isEnabled, !alarms[index].isRepeating,
               (alarms[index].oneTimeDate ?? .distantPast) <= now {
                alarms[index].isEnabled = false
                alarms[index].oneTimeDate = nil
            }
        }
        return commit()
    }

    /// `refresh()` that waits until AlarmKit and notifications are fully synced.
    func reconcile() async {
        await refresh().value
    }

    private func prepared(_ alarm: AlarmItem, now: Date = .now) -> AlarmItem {
        var alarm = alarm
        if alarm.isRepeating || !alarm.isEnabled {
            alarm.oneTimeDate = nil
        } else {
            alarm.oneTimeDate = AlarmItem.nextTime(hour: alarm.hour, minute: alarm.minute, after: now)
        }
        return alarm
    }

    /// Saves and pushes the current state to AlarmKit, notifications and the widget.
    /// Syncs run one at a time, each using the latest state.
    @discardableResult
    private func commit() -> Task<Void, Never> {
        AlarmStorage.save(alarms)
        WidgetCenter.shared.reloadTimelines(ofKind: AlarmStorage.widgetKind)
        BackgroundRefresh.schedule(at: AlarmPlan.nextRestoreDate(for: alarms, now: .now))

        let previous = syncTask
        let task = Task { @MainActor in
            await previous?.value
            let snapshot = self.alarms
            let now = Date()
            self.isAuthorized = await self.scheduler.sync(snapshot, now: now)
            await NotificationScheduler.sync(snapshot, now: now)
        }
        syncTask = task
        return task
    }
}

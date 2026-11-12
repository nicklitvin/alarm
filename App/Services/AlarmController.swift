import Foundation
import Observation
import WidgetKit

/// A ring within the heads-up window, which can still be dismissed.
struct SoonAlarm: Identifiable, Hashable {
    let alarm: AlarmItem
    let date: Date
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
    private(set) var notificationsAllowed = true

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
            // Once dismissed, the ring is gone from here (nextFireDate skips it).
            guard alarm.isEnabled, let next = alarm.nextFireDate(after: now),
                  next.timeIntervalSince(now) <= AlarmItem.headsUpInterval else { return nil }
            return SoonAlarm(alarm: alarm, date: next)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Editing

    func save(_ alarm: AlarmItem) {
        var alarm = alarm
        alarm.isEnabled = true
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            let old = alarms[index]
            if old.hour != alarm.hour || old.minute != alarm.minute || old.weekdays != alarm.weekdays || !old.isEnabled {
                // A changed alarm is a new alarm: forget today's dismissal and use a brand-new
                // system alarm, so it can ring at its new time even if it already rang today.
                alarm.skippedOccurrence = nil
                alarm.revision = old.revision + 1
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

    /// Settings → Delete All Alarms.
    func deleteAll() {
        alarms.removeAll()
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
        WidgetCenter.shared.reloadAllTimelines()
        BackgroundRefresh.schedule(at: AlarmPlan.nextRestoreDate(for: alarms, now: .now))

        let previous = syncTask
        let task = Task { @MainActor in
            await previous?.value
            let snapshot = self.alarms
            let now = Date()
            self.isAuthorized = await self.scheduler.sync(snapshot, now: now)
            self.notificationsAllowed = await NotificationScheduler.sync(snapshot, now: now)
        }
        syncTask = task
        return task
    }
}

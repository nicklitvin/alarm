import Foundation

/// One system alarm that should exist in AlarmKit.
struct PlannedAlarm: Equatable {
    enum Kind: Equatable {
        /// Rings every week on this day.
        case weekly(Weekday)
        /// Rings once at this exact moment.
        case once(Date)
    }

    let item: AlarmItem
    let kind: Kind

    /// Stable description of this system alarm. Any change (time, label, day, sound) yields a new key → new ID.
    var key: String {
        // The sound is only part of the key when it isn't the default, so alarms from older versions keep their IDs.
        let sound = item.sound == .default ? "" : "|s:\(item.sound.rawValue)"
        let base = "\(item.id.uuidString)|r\(item.revision)|\(item.hour):\(item.minute)|\(item.title)\(sound)"
        switch kind {
        case .weekly(let day):
            return base + "|weekly|" + String(day.rawValue)
        case .once(let date):
            return base + "|once|" + String(Int(date.timeIntervalSince1970))
        }
    }

    /// Deterministic ID derived from `key`, so syncing can diff against what's already scheduled.
    var id: UUID { Self.stableUUID(for: key) }

    private static func stableUUID(for key: String) -> UUID {
        // Two independent 64-bit FNV-1a hashes → 128 bits.
        func fnv1a(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in key.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            return hash
        }
        let hi = fnv1a(0xcbf29ce484222325), lo = fnv1a(0x84222325cbf29ce4)
        var b = (0..<8).map { UInt8(truncatingIfNeeded: hi >> (56 - 8 * $0)) }
            + (0..<8).map { UInt8(truncatingIfNeeded: lo >> (56 - 8 * $0)) }
        b[6] = (b[6] & 0x0F) | 0x50 // name-based version
        b[8] = (b[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

/// Works out which system alarms should exist for the user's alarms.
///
/// Every weekday of a repeating alarm is its own weekly system alarm, so dismissing one
/// ring only touches that day. AlarmKit can't skip a single occurrence, so the dismissed
/// day is temporarily swapped for a one-time alarm on the same day next week. Its other
/// days keep ringing untouched.
///
/// The first sync after the dismissed time puts the weekly alarm back. Syncs run when any
/// of our alarms is stopped (`StopAlarmIntent`), on a background refresh, when the app opens
/// and on notification actions. The swap is a one-time alarm, so even if nothing ran
/// sooner, stopping it next week brings the weekly alarm back. Nothing can fall through.
enum AlarmPlan {
    static func make(for alarms: [AlarmItem], now: Date, calendar: Calendar = .current) -> [UUID: PlannedAlarm] {
        var plan: [UUID: PlannedAlarm] = [:]
        func add(_ item: AlarmItem, _ kind: PlannedAlarm.Kind) {
            let planned = PlannedAlarm(item: item, kind: kind)
            plan[planned.id] = planned
        }

        for item in alarms where item.isEnabled {
            if item.isRepeating {
                let skipped = item.skippedOccurrence.flatMap { $0 > now ? $0 : nil }
                let skippedDay = skipped.flatMap { Weekday(date: $0, calendar: calendar) }

                for day in item.weekdays {
                    if day == skippedDay, let skipped,
                       let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: skipped) {
                        add(item, .once(nextWeek))
                    } else {
                        add(item, .weekly(day))
                    }
                }
            } else if let date = item.oneTimeDate, date > now {
                add(item, .once(date))
            }
        }
        return plan
    }

    /// When the next background refresh should run to restore a dismissed day's weekly alarm.
    static func nextRestoreDate(for alarms: [AlarmItem], now: Date) -> Date? {
        alarms
            .filter { $0.isEnabled && $0.isRepeating }
            .compactMap(\.skippedOccurrence)
            .filter { $0 > now }
            .min()
            .map { $0.addingTimeInterval(60) }
    }
}

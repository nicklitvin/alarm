import Foundation

/// One system alarm that should exist in AlarmKit.
struct PlannedAlarm: Equatable {
    enum Kind: Equatable {
        case weekly(Set<Weekday>)
        case once(Date)
    }

    let item: AlarmItem
    let kind: Kind

    /// Stable description of this system alarm. Any change (time, label, days) yields a new key → new ID.
    var key: String {
        let base = "\(item.id.uuidString)|\(item.hour):\(item.minute)|\(item.title)"
        switch kind {
        case .weekly(let days):
            return base + "|weekly|" + days.sorted().map { String($0.rawValue) }.joined(separator: ",")
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
/// Dismissing a single ring of a repeating alarm works like this. Say a Mon–Fri 7:00
/// alarm is dismissed for Tuesday. It becomes a weekly Mon/Wed/Thu/Fri alarm plus
/// one-off alarms for the next several Tuesdays. Once the dismissed Tuesday has
/// passed, the next sync (on app open, or any change) folds it back into one Mon–Fri alarm.
enum AlarmPlan {
    /// How many weeks of replacement one-off rings to schedule for a dismissed weekday.
    static let coverageWeeks = 8

    static func make(for alarms: [AlarmItem], now: Date, calendar: Calendar = .current) -> [UUID: PlannedAlarm] {
        var plan: [UUID: PlannedAlarm] = [:]
        func add(_ item: AlarmItem, _ kind: PlannedAlarm.Kind) {
            let planned = PlannedAlarm(item: item, kind: kind)
            plan[planned.id] = planned
        }

        for item in alarms where item.isEnabled {
            if item.isRepeating {
                if let skipped = item.skippedOccurrence, skipped > now,
                   let skippedDay = Weekday(date: skipped, calendar: calendar),
                   item.weekdays.contains(skippedDay) {
                    let otherDays = item.weekdays.subtracting([skippedDay])
                    if !otherDays.isEmpty { add(item, .weekly(otherDays)) }
                    for week in 1...coverageWeeks {
                        if let date = calendar.date(byAdding: .weekOfYear, value: week, to: skipped) {
                            add(item, .once(date))
                        }
                    }
                } else {
                    add(item, .weekly(item.weekdays))
                }
            } else if let date = item.oneTimeDate, date > now {
                add(item, .once(date))
            }
        }
        return plan
    }
}

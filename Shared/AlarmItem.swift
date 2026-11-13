import Foundation

/// Days of the week, numbered the same way as `Calendar` (Sunday = 1).
enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable, Hashable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    init?(date: Date, calendar: Calendar = .current) {
        self.init(rawValue: calendar.component(.weekday, from: date))
    }

    var initial: String { Calendar.current.veryShortWeekdaySymbols[rawValue - 1] }
    var shortName: String { Calendar.current.shortWeekdaySymbols[rawValue - 1] }
    var fullName: String { Calendar.current.weekdaySymbols[rawValue - 1] }

    /// All weekdays in the order the user's region shows them (e.g. Mon…Sun or Sun…Sat).
    static var localeOrdered: [Weekday] {
        let first = Calendar.current.firstWeekday
        return (0..<7).compactMap { Weekday(rawValue: (first - 1 + $0) % 7 + 1) }
    }

    static let workdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekend: Set<Weekday> = [.saturday, .sunday]

    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }
}

/// A user-created alarm.
struct AlarmItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    var label: String = ""
    /// Days the alarm repeats on. Empty means it rings once.
    var weekdays: Set<Weekday> = []
    var isEnabled: Bool = true
    /// A single upcoming ring of a repeating alarm that the user dismissed ahead of time.
    var skippedOccurrence: Date? = nil
    /// For one-time alarms: the exact moment it will ring.
    var oneTimeDate: Date? = nil
    /// Bumped whenever the time or days change. The system alarm is then a brand-new one, so an
    /// alarm that already rang (or was dismissed) today can ring again at its new time today.
    var revision: Int = 0
    /// What it rings with.
    var sound: AlarmSound = .default

    init(id: UUID = UUID(), hour: Int, minute: Int, label: String = "", weekdays: Set<Weekday> = [],
         isEnabled: Bool = true, skippedOccurrence: Date? = nil, oneTimeDate: Date? = nil, revision: Int = 0,
         sound: AlarmSound = .default) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.label = label
        self.weekdays = weekdays
        self.isEnabled = isEnabled
        self.skippedOccurrence = skippedOccurrence
        self.oneTimeDate = oneTimeDate
        self.revision = revision
        self.sound = sound
    }

    // Tolerates alarms saved by older versions (e.g. without `revision`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hour = try c.decode(Int.self, forKey: .hour)
        minute = try c.decode(Int.self, forKey: .minute)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        weekdays = try c.decodeIfPresent(Set<Weekday>.self, forKey: .weekdays) ?? []
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        skippedOccurrence = try c.decodeIfPresent(Date.self, forKey: .skippedOccurrence)
        oneTimeDate = try c.decodeIfPresent(Date.self, forKey: .oneTimeDate)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        sound = (try? c.decodeIfPresent(AlarmSound.self, forKey: .sound)) ?? .default
    }

    /// How long before an alarm the heads-up notification and the Dismiss button appear (a setting).
    static var headsUpInterval: TimeInterval { TimeInterval(AppSettings.alarmHeadsUpMinutes * 60) }

    var isRepeating: Bool { !weekdays.isEmpty }

    var title: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Alarm" : trimmed
    }

    var timeString: String { TimeFormat.string(hour: hour, minute: minute) }

    var repeatSummary: String {
        switch weekdays {
        case []: "Once"
        case Set(Weekday.allCases): "Every day"
        case Weekday.workdays: "Weekdays"
        case Weekday.weekend: "Weekends"
        default:
            Weekday.localeOrdered.filter(weekdays.contains).map(\.shortName).joined(separator: ", ")
        }
    }

    /// The next time this alarm is set for, strictly after `date`, ignoring any dismissal.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        if isRepeating {
            return weekdays.compactMap { day in
                calendar.nextDate(
                    after: date,
                    matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: day.rawValue),
                    matchingPolicy: .nextTime
                )
            }.min()
        }
        guard let oneTimeDate, oneTimeDate > date else { return nil }
        return oneTimeDate
    }

    /// The upcoming times this alarm will actually ring, honoring a dismissed occurrence.
    func upcomingFireDates(after date: Date, limit: Int, calendar: Calendar = .current) -> [Date] {
        guard isEnabled else { return [] }
        var result: [Date] = []
        var cursor = date
        while result.count < limit, let next = nextOccurrence(after: cursor, calendar: calendar) {
            if !isSkipped(next) { result.append(next) }
            cursor = next
        }
        return result
    }

    func nextFireDate(after date: Date, calendar: Calendar = .current) -> Date? {
        upcomingFireDates(after: date, limit: 1, calendar: calendar).first
    }

    func isSkipped(_ occurrence: Date) -> Bool {
        guard let skippedOccurrence else { return false }
        return abs(skippedOccurrence.timeIntervalSince(occurrence)) < 1
    }

    /// Next date at `hour:minute` after `date` — used to pin down when a one-time alarm rings.
    static func nextTime(hour: Int, minute: Int, after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime
        )
    }
}

/// A specific upcoming ring of an alarm.
struct UpcomingAlarm: Hashable, Sendable {
    var alarm: AlarmItem
    var date: Date
}

extension Sequence where Element == AlarmItem {
    /// The next `limit` rings across all alarms, soonest first.
    func upcomingFires(after date: Date, limit: Int) -> [UpcomingAlarm] {
        let all = flatMap { alarm in
            alarm.upcomingFireDates(after: date, limit: limit).map { UpcomingAlarm(alarm: alarm, date: $0) }
        }
        return Array(all.sorted { $0.date < $1.date }.prefix(limit))
    }

    func nextFire(after date: Date) -> UpcomingAlarm? {
        upcomingFires(after: date, limit: 1).first
    }
}

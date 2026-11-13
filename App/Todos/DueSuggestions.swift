import Foundation

/// Quick deadline choices that make sense for the current time of day.
enum DueSuggestions {
    struct Suggestion: Identifiable, Hashable {
        let title: String
        let date: Date
        var id: String { title }
    }

    static func make(now: Date = Date(), calendar: Calendar = .current) -> [Suggestion] {
        var result: [Suggestion] = []
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let minutesNow = hour * 60 + minute

        func today(_ h: Int, _ m: Int = 0) -> Date? {
            calendar.date(bySettingHour: h, minute: m, second: 0, of: now)
        }
        func tomorrow(_ h: Int) -> Date? {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                .flatMap { calendar.date(bySettingHour: h, minute: 0, second: 0, of: $0) }
        }

        // In 1 hour, rounded up to the next 5 minutes.
        let inAnHour = now.addingTimeInterval(3600)
        let roundUp = (5 - calendar.component(.minute, from: inAnHour) % 5) % 5
        if let rounded = calendar.date(byAdding: .minute, value: roundUp, to: inAnHour),
           let clean = calendar.date(bySetting: .second, value: 0, of: rounded) {
            result.append(Suggestion(title: "In 1 hour", date: clean))
        }

        if minutesNow < 12 * 60, let d = today(15) { result.append(Suggestion(title: "This afternoon", date: d)) }
        if minutesNow < 16 * 60, let d = today(18) { result.append(Suggestion(title: "This evening", date: d)) }
        if minutesNow < 20 * 60 + 30, let d = today(21) { result.append(Suggestion(title: "Tonight", date: d)) }
        if let d = tomorrow(9) { result.append(Suggestion(title: "Tomorrow morning", date: d)) }
        if minutesNow >= 16 * 60, let d = tomorrow(18) { result.append(Suggestion(title: "Tomorrow evening", date: d)) }

        // This weekend (Saturday 10 AM) from Monday to Thursday; next Monday 9 AM otherwise.
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        let (target, label, hourOfDay) = (2...5).contains(weekday) ? (7, "This weekend", 10) : (2, "Next week", 9)
        if let day = calendar.nextDate(after: now, matching: DateComponents(hour: hourOfDay, minute: 0, weekday: target),
                                       matchingPolicy: .nextTime) {
            result.append(Suggestion(title: label, date: day))
        }
        return result
    }
}

/// A quick time for a deadline (To-Do settings → Quick Times): one tap sets the time and keeps
/// the chosen day. Shown as just the time, e.g. "9 AM" or "21:00".
struct QuickTime: Hashable, Identifiable, Sendable {
    /// Minutes after midnight.
    let minutes: Int

    init(minutes: Int) { self.minutes = ((minutes % 1440) + 1440) % 1440 }
    init(hour: Int, minute: Int = 0) { self.init(minutes: hour * 60 + minute) }

    var id: Int { minutes }
    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    /// "9 AM", "9:30 AM" or "21:00", following the 12/24-hour system setting.
    var label: String {
        let parts = TimeFormat.parts(hour: hour, minute: minute)
        guard let period = parts.period else { return parts.time }
        let time = minute == 0 ? parts.time.replacingOccurrences(of: ":00", with: "") : parts.time
        return "\(time) \(period)"
    }

    /// The times the chips show: from settings, or the defaults (morning, afternoon, night).
    static var current: [QuickTime] { AppSettings.todoQuickTimes.map(QuickTime.init(minutes:)) }

    /// `date`'s day at this time. If that's already past (only possible today), the next day.
    func apply(to date: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        var result = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? date
        if result <= now, let next = calendar.date(byAdding: .day, value: 1, to: result) {
            result = next
        }
        return result
    }

    /// The option a deadline currently matches, for highlighting.
    static func matching(_ date: Date, in options: [QuickTime], calendar: Calendar = .current) -> QuickTime? {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return options.first { $0.hour == c.hour && $0.minute == c.minute }
    }
}

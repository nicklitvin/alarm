import Foundation

enum TimeFormat {
    /// Whether the user's region/settings use a 12-hour clock.
    static var uses12HourClock: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return format.contains("a")
    }

    /// Splits a time into the digits and the AM/PM marker (nil on 24-hour clocks).
    static func parts(hour: Int, minute: Int) -> (time: String, period: String?) {
        if uses12HourClock {
            let calendar = Calendar.current
            let displayHour = hour % 12 == 0 ? 12 : hour % 12
            return (String(format: "%d:%02d", displayHour, minute), hour < 12 ? calendar.amSymbol : calendar.pmSymbol)
        }
        return (String(format: "%02d:%02d", hour, minute), nil)
    }

    static func parts(for date: Date) -> (time: String, period: String?) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return parts(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    static func string(hour: Int, minute: Int) -> String {
        let p = parts(hour: hour, minute: minute)
        return p.period.map { "\(p.time) \($0)" } ?? p.time
    }

    static func string(for date: Date) -> String {
        let p = parts(for: date)
        return p.period.map { "\(p.time) \($0)" } ?? p.time
    }

    /// "Today", "Tomorrow", or the weekday name.
    static func dayDescription(for date: Date, relativeTo now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }

    /// Timer display like "4:05" or "1:02:03".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Spoken-style duration like "5 minutes", "1 hour 30 minutes" or "45 seconds".
    static func durationName(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        func unit(_ n: Int, _ name: String) -> String? { n > 0 ? "\(n) \(name)\(n == 1 ? "" : "s")" : nil }
        let parts = [unit(h, "hour"), unit(m, "minute"), unit(s, "second")].compactMap { $0 }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    /// Short preset label like "5 min", "1 hr" or "30 sec".
    static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600, total % 3600 == 0 { return "\(total / 3600) hr" }
        if total >= 60, total % 60 == 0 { return "\(total / 60) min" }
        if total < 60 { return "\(total) sec" }
        return clock(seconds)
    }

    /// Compact countdown like "7h 12m" or "42m".
    static func countdown(from now: Date, to date: Date) -> String {
        let total = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let days = total / 1440, hours = (total % 1440) / 60, minutes = total % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}

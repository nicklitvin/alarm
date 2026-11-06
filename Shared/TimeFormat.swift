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

    /// Compact countdown like "7h 12m" or "42m".
    static func countdown(from now: Date, to date: Date) -> String {
        let total = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let days = total / 1440, hours = (total % 1440) / 60, minutes = total % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}

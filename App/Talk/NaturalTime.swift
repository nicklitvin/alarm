import Foundation

/// Turns the loose time/day strings the assistant produces ("5pm", "17:30", "tomorrow",
/// "friday", "2026-11-14") into concrete dates.
enum NaturalTime {
    struct Clock: Equatable {
        var hour: Int
        var minute: Int
        /// Whether AM/PM (or noon/midnight) was stated, i.e. the hour isn't ambiguous.
        var isExplicit: Bool
    }

    /// Parses a time of day: "7", "7:30", "7am", "7:30 p.m.", "19:30", "0730", "noon", "midnight".
    static func parseClock(_ text: String) -> Clock? {
        let s = text.lowercased().replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.contains("noon") { return Clock(hour: 12, minute: 0, isExplicit: true) }
        if s.contains("midnight") { return Clock(hour: 0, minute: 0, isExplicit: true) }

        let isPM = s.contains("pm")
        let isAM = !isPM && s.contains("am")
        let digits = s.filter { $0.isNumber || $0 == ":" }
        let parts = digits.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, !first.isEmpty, let firstValue = Int(first) else { return nil }

        var hour = firstValue, minute = 0
        if parts.count >= 2 {
            guard let m = Int(parts[1]) else { return nil }
            minute = m
        } else if first.count >= 3 {
            hour = firstValue / 100
            minute = firstValue % 100
        }
        guard (0...59).contains(minute) else { return nil }

        if isPM || isAM {
            guard (1...12).contains(hour) else { return nil }
            if isPM, hour < 12 { hour += 12 }
            if isAM, hour == 12 { hour = 0 }
            return Clock(hour: hour, minute: minute, isExplicit: true)
        }
        guard (0...23).contains(hour) else { return nil }
        return Clock(hour: hour, minute: minute, isExplicit: hour == 0 || hour > 12 || first.count == 2 && first.hasPrefix("0"))
    }

    struct Day {
        var start: Date
        /// Time to use when none is given ("tonight" → 9 PM, otherwise 9 AM).
        var defaultHour: Int
        /// Named by weekday, so a time already past today means next week.
        var isWeekday: Bool
    }

    /// Parses a day: "today", "tonight", "tomorrow", "day after tomorrow", "friday", "next friday",
    /// "in 3 days", "2026-11-14", "November 14", "11/14".
    static func parseDay(_ text: String, now: Date, calendar: Calendar = .current) -> Day? {
        let s = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        func offset(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: today)! }

        if s.contains("day after tomorrow") { return Day(start: offset(2), defaultHour: 9, isWeekday: false) }
        if s.contains("tomorrow") || s == "tmrw" {
            return Day(start: offset(1), defaultHour: hint(for: s) ?? 9, isWeekday: false)
        }
        if s.contains("today") || s.contains("tonight") || s.hasPrefix("this ") && hint(for: s) != nil {
            return Day(start: today, defaultHour: hint(for: s) ?? 9, isWeekday: false)
        }
        if s.hasPrefix("in "), let n = Int(s.filter(\.isNumber)), s.contains("day") {
            return Day(start: offset(n), defaultHour: 9, isWeekday: false)
        }
        if s.hasPrefix("in "), let n = Int(s.filter(\.isNumber)), s.contains("week") {
            return Day(start: offset(7 * n), defaultHour: 9, isWeekday: false)
        }

        let current = calendar.component(.weekday, from: now)
        if s.contains("weekend") {
            let ahead = current == 1 ? 0 : 7 - current // Saturday (or today if it's Sunday)
            return Day(start: offset(ahead), defaultHour: 10, isWeekday: false)
        }
        if s.contains("next week") {
            return Day(start: offset((2 - current + 7) % 7 == 0 ? 7 : (2 - current + 7) % 7), defaultHour: 9, isWeekday: false)
        }

        let names = calendar.weekdaySymbols.map { $0.lowercased() }
        for (index, name) in names.enumerated() where s.contains(name) || s.split(separator: " ").contains(Substring(name.prefix(3))) {
            var ahead = (index + 1 - current + 7) % 7
            if s.contains("next") && ahead == 0 { ahead = 7 }
            return Day(start: offset(ahead), defaultHour: hint(for: s) ?? 9, isWeekday: true)
        }

        // Explicit dates.
        let formats = ["yyyy-MM-dd", "MMMM d yyyy", "MMMM d", "MMM d yyyy", "MMM d", "M/d/yyyy", "M/d"]
        let cleaned = s.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: #"(\d+)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for format in formats {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: format.hasPrefix("yyyy") ? s : cleaned) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: parsed)
            if !format.contains("yyyy") {
                // No year given: the next time this date comes around.
                components.year = calendar.component(.year, from: now)
                if let candidate = calendar.date(from: components), candidate < today {
                    components.year! += 1
                }
            }
            if let date = calendar.date(from: components) {
                return Day(start: calendar.startOfDay(for: date), defaultHour: 9, isWeekday: false)
            }
        }
        return nil
    }

    /// Works out a deadline from whatever pieces were given. Nil when nothing usable was given.
    static func resolveDue(day: String?, time: String?, minutesFromNow: Int?, now: Date, calendar: Calendar = .current) -> Date? {
        if let minutes = minutesFromNow, minutes > 0 {
            return now.addingTimeInterval(TimeInterval(minutes * 60))
        }
        let clock = time.flatMap(parseClock)
        let parsedDay = day.flatMap { parseDay($0, now: now, calendar: calendar) }

        func at(_ start: Date, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start)!
        }

        switch (parsedDay, clock) {
        case (nil, nil):
            return nil

        case (nil, let clock?):
            // Just a time: the next time it comes around ("at 5" in the afternoon means 5 PM).
            let today = calendar.startOfDay(for: now)
            var candidate = at(today, clock.hour, clock.minute)
            if candidate <= now, !clock.isExplicit, clock.hour < 12 {
                let evening = at(today, clock.hour + 12, clock.minute)
                if evening > now { return evening }
            }
            if candidate <= now { candidate = calendar.date(byAdding: .day, value: 1, to: candidate)! }
            return candidate

        case (let day?, nil):
            let candidate = at(day.start, day.defaultHour, 0)
            if candidate <= now, calendar.isDate(day.start, inSameDayAs: now) {
                // "today" with no time and it's already past 9: an hour from now.
                return now.addingTimeInterval(3600)
            }
            return day.isWeekday && candidate <= now ? calendar.date(byAdding: .day, value: 7, to: candidate)! : candidate

        case (let day?, let clock?):
            var hour = clock.hour
            // "tonight at 8" → 8 PM.
            if !clock.isExplicit, hour < 12, day.defaultHour >= 17 { hour += 12 }
            let candidate = at(day.start, hour, clock.minute)
            return day.isWeekday && candidate <= now ? calendar.date(byAdding: .day, value: 7, to: candidate)! : candidate
        }
    }

    /// Default hour implied by words like "morning" or "tonight".
    private static func hint(for text: String) -> Int? {
        if text.contains("morning") { return 9 }
        if text.contains("noon") { return 12 }
        if text.contains("afternoon") { return 15 }
        if text.contains("evening") { return 18 }
        if text.contains("tonight") || text.contains("night") { return 21 }
        return nil
    }
}

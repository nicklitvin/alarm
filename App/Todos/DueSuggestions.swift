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

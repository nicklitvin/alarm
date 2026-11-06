import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { print("✓ \(msg)") } else { failures += 1; print("✗ \(msg) (line \(line))") }
}
let cal = Calendar.current
func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int, _ min: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min))!
}
let fmt = DateFormatter(); fmt.dateFormat = "EEE yyyy-MM-dd HH:mm zzz"
func s(_ d: Date?) -> String { d.map(fmt.string) ?? "nil" }

// Mon–Fri 7:00. Fri Oct 30 2026, 06:30 (US DST ends Sun Nov 1).
var a = AlarmItem(hour: 7, minute: 0, label: "Gym", weekdays: Weekday.workdays)
let now = d(2026, 10, 30, 6, 30)
check(Weekday(date: now) == .friday, "Oct 30 2026 is a Friday")
let next = a.nextFireDate(after: now)
check(next == d(2026, 10, 30, 7, 0), "next fire is today 7:00 → \(s(next))")
check(a.repeatSummary == "Weekdays", "repeat summary Weekdays")

// Dismiss Friday's ring.
a.skippedOccurrence = next
let afterSkip = a.upcomingFireDates(after: now, limit: 3)
check(afterSkip == [d(2026, 11, 2, 7, 0), d(2026, 11, 3, 7, 0), d(2026, 11, 4, 7, 0)],
      "after skip: Mon/Tue/Wed (across DST) → \(afterSkip.map(s))")
check([a].nextFire(after: now)?.date == d(2026, 11, 2, 7, 0), "widget next fire honors skip")

// Plan while skip active.
let plan = AlarmPlan.make(for: [a], now: now)
let weekly = plan.values.compactMap { if case .weekly(let w) = $0.kind { return w } else { return nil } }
let onces = plan.values.compactMap { if case .once(let dt) = $0.kind { return dt } else { return nil } }.sorted()
check(weekly == [[.monday, .tuesday, .wednesday, .thursday]], "weekly Mon–Thu while Friday is skipped")
check(onces.count == AlarmPlan.coverageWeeks, "\(AlarmPlan.coverageWeeks) one-off Fridays")
check(onces.first == d(2026, 11, 6, 7, 0), "first one-off is next Friday 7:00 local (post-DST) → \(s(onces.first))")
check(onces.allSatisfy { cal.component(.hour, from: $0) == 7 && Weekday(date: $0) == .friday }, "all one-offs Fri 7:00 local")

// Plan after skip passed → single weekly alarm again.
let later = d(2026, 10, 30, 7, 1)
let plan2 = AlarmPlan.make(for: [a], now: later)
check(plan2.count == 1 && plan2.values.first?.kind == .weekly(Weekday.workdays), "after skipped time passes: back to one Mon–Fri alarm")

// Stable IDs.
check(Set(AlarmPlan.make(for: [a], now: now).keys) == Set(plan.keys), "IDs stable across syncs")
var renamed = a; renamed.label = "Run"
check(Set(AlarmPlan.make(for: [renamed], now: now).keys).isDisjoint(with: plan.keys), "rename → new IDs")
check(plan.keys.allSatisfy { $0.uuidString.dropFirst(14).first == "5" }, "UUID version nibble set")

// Skip only one day of a single-day alarm.
var sat = AlarmItem(hour: 9, minute: 30, weekdays: [.saturday])
sat.skippedOccurrence = sat.nextOccurrence(after: now)
let plan3 = AlarmPlan.make(for: [sat], now: now)
check(plan3.count == AlarmPlan.coverageWeeks && plan3.values.allSatisfy { if case .once = $0.kind { true } else { false } },
      "single-day alarm skip → only one-offs")
check(sat.nextFireDate(after: now) == d(2026, 11, 7, 9, 30), "Sat alarm next after skip = Nov 7 → \(s(sat.nextFireDate(after: now)))")

// One-time alarm.
var once = AlarmItem(hour: 5, minute: 15)
once.oneTimeDate = AlarmItem.nextTime(hour: 5, minute: 15, after: now)
check(once.oneTimeDate == d(2026, 10, 31, 5, 15), "one-time 5:15 → tomorrow")
check(once.repeatSummary == "Once", "once summary")
check(AlarmPlan.make(for: [once], now: now).values.first?.kind == .once(d(2026, 10, 31, 5, 15)), "one-time planned as fixed")
check(AlarmPlan.make(for: [once], now: d(2026, 10, 31, 6, 0)).isEmpty, "one-time in past not planned")
check(once.upcomingFireDates(after: now, limit: 5).count == 1, "one-time yields single fire")
var off = a; off.isEnabled = false
check(AlarmPlan.make(for: [off], now: now).isEmpty && off.nextFireDate(after: now) == nil, "disabled alarm ignored")

// Merged upcoming fires (widget timeline).
let fires = [a, once, sat].upcomingFires(after: now, limit: 4).map(\.date)
check(fires == [d(2026, 10, 31, 5, 15), d(2026, 11, 2, 7, 0), d(2026, 11, 3, 7, 0), d(2026, 11, 4, 7, 0)],
      "merged upcoming fires → \(fires.map(s))")

// Formatting.
check(TimeFormat.string(hour: 0, minute: 5) == "12:05 AM" || TimeFormat.string(hour: 0, minute: 5) == "00:05", "time format → \(TimeFormat.string(hour: 0, minute: 5))")
check(TimeFormat.dayDescription(for: d(2026, 10, 31, 1, 0), relativeTo: now) == "Tomorrow", "Tomorrow")
check(TimeFormat.dayDescription(for: d(2026, 11, 2, 7, 0), relativeTo: now) == "Monday", "weekday name")
check(TimeFormat.countdown(from: now, to: d(2026, 10, 30, 13, 42)) == "7h 12m", "countdown → \(TimeFormat.countdown(from: now, to: d(2026, 10, 30, 13, 42)))")

// Codable round trip.
let data = try! JSONEncoder().encode([a, once])
check(try! JSONDecoder().decode([AlarmItem].self, from: data) == [a, once], "Codable round trip")

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)

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

// Plan while skip active: each day is its own weekly alarm; only Friday is swapped for next Friday.
func kinds(_ plan: [UUID: PlannedAlarm]) -> (weekly: Set<Weekday>, once: [Date]) {
    var w = Set<Weekday>(), o: [Date] = []
    for p in plan.values {
        switch p.kind { case .weekly(let day): w.insert(day); case .once(let dt): o.append(dt) }
    }
    return (w, o.sorted())
}
let normalPlan = AlarmPlan.make(for: [AlarmItem(id: a.id, hour: 7, minute: 0, label: "Gym", weekdays: Weekday.workdays)], now: now)
check(normalPlan.count == 5 && kinds(normalPlan).weekly == Weekday.workdays, "no skip: one weekly alarm per day (5)")

let plan = AlarmPlan.make(for: [a], now: now)
let k = kinds(plan)
check(k.weekly == [.monday, .tuesday, .wednesday, .thursday], "skip Friday: Mon–Thu weekly alarms untouched")
check(k.once == [d(2026, 11, 6, 7, 0)], "skip Friday: single one-off next Friday 7:00 local (post-DST) → \(k.once.map(s))")
check(Set(plan.keys).subtracting(normalPlan.keys).count == 1, "skip changes exactly one system alarm")
check(AlarmPlan.nextRestoreDate(for: [a], now: now) == d(2026, 10, 30, 7, 1), "background refresh requested 1 min after the skipped ring")

// Restore path 1: something runs right after the skipped ring (background refresh, app open, other alarm stopped).
let afterSkippedRing = d(2026, 10, 30, 7, 1)
check(Set(AlarmPlan.make(for: [a], now: afterSkippedRing).keys) == Set(normalPlan.keys), "after skipped ring passes: back to all 5 weekly alarms (same IDs as before)")
check(AlarmPlan.nextRestoreDate(for: [a], now: afterSkippedRing) == nil, "no further background refresh needed")

// Restore path 2: nothing ran all week; the one-off rings next Friday and its Stop intent re-syncs.
let afterReplacementStopped = d(2026, 11, 6, 7, 2)
check(Set(AlarmPlan.make(for: [a], now: afterReplacementStopped).keys) == Set(normalPlan.keys), "stopping next Friday's one-off restores weekly Friday")
var restored = a; restored.skippedOccurrence = nil
check(restored.nextFireDate(after: afterReplacementStopped) == d(2026, 11, 9, 7, 0), "and the alarm carries on Monday as normal")

// Stable IDs.
check(Set(AlarmPlan.make(for: [a], now: now).keys) == Set(plan.keys), "IDs stable across syncs")
var renamed = a; renamed.label = "Run"
check(Set(AlarmPlan.make(for: [renamed], now: now).keys).isDisjoint(with: plan.keys), "rename → new IDs")
check(plan.keys.allSatisfy { $0.uuidString.dropFirst(14).first == "5" }, "UUID version nibble set")

// Skip the only day of a single-day alarm.
var sat = AlarmItem(hour: 9, minute: 30, weekdays: [.saturday])
sat.skippedOccurrence = sat.nextOccurrence(after: now)
let plan3 = AlarmPlan.make(for: [sat], now: now)
check(plan3.count == 1 && plan3.values.first?.kind == .once(d(2026, 11, 7, 9, 30)), "single-day alarm skip → one one-off next week")
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

// Wake word.
let wake = "Hey Alarm"
check(WakeWord.strip(wake, from: "Hey alarm, set a timer for 5 minutes") == "set a timer for 5 minutes", "wake word stripped")
check(WakeWord.strip(wake, from: "Hey, alarm. What time is it?") == "What time is it?", "punctuation between/after wake word, keeps trailing ?")
check(WakeWord.strip(wake, from: "hey Alarm.") == "", "wake word alone → empty (wait for follow-up)")
check(WakeWord.strip(wake, from: "Heyalarm what's up") == "what's up", "run-together wake word")
check(WakeWord.strip(wake, from: "Hey alarms stop the timer") == "stop the timer", "one-letter slip tolerated")
check(WakeWord.strip(wake, from: "Héy ALARM start") == "start", "case/accents ignored")
check(WakeWord.strip(wake, from: "Set a timer for 5 minutes") == nil, "no wake word → ignored")
check(WakeWord.strip(wake, from: "Hey Alan set a timer") == nil, "different name → ignored")
check(WakeWord.strip(wake, from: "Okay alarm set a timer") == nil, "different greeting → ignored")
check(WakeWord.strip(wake, from: "I said hey alarm") == nil, "wake word must be at the start")
check(WakeWord.strip(wake, from: "") == nil, "empty utterance → ignored")
check(WakeWord.strip("Jarvis", from: "Jervis, timer 10 minutes") == "timer 10 minutes", "single-word wake word w/ slip")
check(WakeWord.strip("Max", from: "Mix timer") == nil, "short wake words must match exactly")
check(WakeWord.strip("", from: "anything") == "anything", "empty wake word lets everything through")

// Timer formatting.
check(TimeFormat.clock(65) == "1:05" && TimeFormat.clock(3723) == "1:02:03" && TimeFormat.clock(0) == "0:00", "clock format")
check(TimeFormat.durationName(300) == "5 minutes" && TimeFormat.durationName(5400) == "1 hour 30 minutes" && TimeFormat.durationName(61) == "1 minute 1 second", "duration names")
check(TimeFormat.compactDuration(300) == "5 min" && TimeFormat.compactDuration(3600) == "1 hr" && TimeFormat.compactDuration(30) == "30 sec", "preset labels")

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)

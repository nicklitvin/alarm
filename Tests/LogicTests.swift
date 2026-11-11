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

// Natural time parsing (assistant tool arguments).
func clock(_ t: String) -> String { NaturalTime.parseClock(t).map { "\($0.hour):\($0.minute)" } ?? "nil" }
check(clock("7") == "7:0" && clock("7:30") == "7:30" && clock("7am") == "7:0" && clock("7:30 p.m.") == "19:30", "parse 7 / 7:30 / 7am / 7:30 p.m.")
check(clock("19:30") == "19:30" && clock("0730") == "7:30" && clock("12am") == "0:0" && clock("12 PM") == "12:0", "parse 24h / 0730 / 12am / 12pm")
check(clock("noon") == "12:0" && clock("midnight") == "0:0" && clock("25:00") == "nil" && clock("") == "nil" && clock("soon") == "nil", "parse noon / midnight / invalid")

let thu = d(2026, 11, 12, 15, 0)   // Thursday 3 PM
check(Weekday(date: thu) == .thursday, "Nov 12 2026 is Thursday")
func due(_ day: String?, _ time: String?, _ mins: Int? = nil, now: Date = thu) -> String { s(NaturalTime.resolveDue(day: day, time: time, minutesFromNow: mins, now: now)) }
check(due(nil, nil) == "nil", "nothing → no deadline")
check(due(nil, nil, 30) == s(d(2026, 11, 12, 15, 30)), "in 30 minutes")
check(due(nil, "17:00") == s(d(2026, 11, 12, 17, 0)), "time only, later today")
check(due(nil, "5") == s(d(2026, 11, 12, 17, 0)), "bare '5' in the afternoon → 5 PM")
check(due(nil, "9am") == s(d(2026, 11, 13, 9, 0)), "9am already passed → tomorrow")
check(due("tomorrow", nil) == s(d(2026, 11, 13, 9, 0)), "tomorrow → 9 AM")
check(due("tomorrow evening", nil) == s(d(2026, 11, 13, 18, 0)), "tomorrow evening → 6 PM")
check(due("tonight", "8") == s(d(2026, 11, 12, 20, 0)), "tonight at 8 → 8 PM")
check(due("today", nil) == s(d(2026, 11, 12, 16, 0)), "today, no time, past 9 → in an hour")
check(due("friday", "14:00") == s(d(2026, 11, 13, 14, 0)), "friday 2pm")
check(due("thursday", "10am") == s(d(2026, 11, 19, 10, 0)), "this weekday but time passed → next week")
check(due("next thursday", nil) == s(d(2026, 11, 19, 9, 0)), "next thursday")
check(due("mon", nil) == s(d(2026, 11, 16, 9, 0)), "3-letter weekday")
check(due("this weekend", nil) == s(d(2026, 11, 14, 10, 0)), "this weekend → Sat 10 AM")
check(due("next week", nil) == s(d(2026, 11, 16, 9, 0)), "next week → Monday 9 AM")
check(due("in 3 days", "18:30") == s(d(2026, 11, 15, 18, 30)), "in 3 days at 18:30")
check(due("2026-12-01", "8:15am") == s(d(2026, 12, 1, 8, 15)), "ISO date")
check(due("August 3rd", nil) == s(d(2027, 8, 3, 9, 0)), "month name with ordinal, next occurrence → \(due("August 3rd", nil))")
check(due("Nov 20", "noon") == s(d(2026, 11, 20, 12, 0)), "short month")
check(due("gibberish", nil) == "nil", "unparseable day → nil")

// Deadline suggestions.
let sugThu = DueSuggestions.make(now: thu).map(\.title)
check(sugThu == ["In 1 hour", "This evening", "Tonight", "Tomorrow morning", "This weekend"], "suggestions Thu 3 PM → \(sugThu)")
let sugMorning = DueSuggestions.make(now: d(2026, 11, 13, 8, 7))
check(sugMorning.map(\.title) == ["In 1 hour", "This afternoon", "This evening", "Tonight", "Tomorrow morning", "Next week"], "suggestions Fri 8 AM → \(sugMorning.map(\.title))")
check(sugMorning.first?.date == d(2026, 11, 13, 9, 10), "in 1 hour rounds up to 5 min → \(s(sugMorning.first?.date))")
let sugLate = DueSuggestions.make(now: d(2026, 11, 12, 22, 0)).map(\.title)
check(sugLate == ["In 1 hour", "Tomorrow morning", "Tomorrow evening", "This weekend"], "suggestions late → \(sugLate)")

// To-dos.
var t1 = TodoItem(title: "A", due: d(2026, 11, 13, 9, 0)), t2 = TodoItem(title: "B", due: d(2026, 11, 12, 16, 0))
let t3 = TodoItem(title: "C"); var t4 = TodoItem(title: "D", due: d(2026, 11, 12, 10, 0)); t4.setDone(true)
check([t1, t3, t4, t2].sortedForDisplay.map(\.title) == ["B", "A", "C", "D"], "todo sort: due soonest, no deadline, done last")
check(t2.isOverdue(at: d(2026, 11, 12, 16, 1)) && !t4.isOverdue(at: thu) && !t3.isOverdue(at: thu), "overdue logic")
t1.setDone(true); check(t1.completedAt != nil, "completedAt set"); t1.setDone(false); check(t1.completedAt == nil, "completedAt cleared")
check(TimeFormat.dueDescription(d(2026, 11, 12, 17, 0), relativeTo: thu) == "5:00 PM", "due today")
check(TimeFormat.dueDescription(d(2026, 11, 13, 9, 0), relativeTo: thu) == "Tomorrow 9:00 AM", "due tomorrow")
check(TimeFormat.dueDescription(d(2026, 11, 16, 9, 0), relativeTo: thu) == "Mon 9:00 AM", "due this week")
check(TimeFormat.dueDescription(d(2026, 12, 1, 9, 0), relativeTo: thu) == "Dec 1, 9:00 AM", "due later")
check(TimeFormat.dueDescription(d(2026, 11, 11, 9, 0), relativeTo: thu) == "Yesterday 9:00 AM", "overdue yesterday")
_ = t2; t2.title = "B"

// Assistant matching.
check(AssistantMatching.weekdays(from: ["weekdays"]) == Weekday.workdays, "days: weekdays")
check(AssistantMatching.weekdays(from: ["Monday", "wed", "Fri."]) == [.monday, .wednesday, .friday], "days: names/abbrevs")
check(AssistantMatching.weekdays(from: ["every day"]) == Set(Weekday.allCases) && AssistantMatching.weekdays(from: ["weekends"]) == Weekday.weekend, "days: every day / weekends")
check(AssistantMatching.weekdays(from: ["tues", "thu", "sat"]) == [.tuesday, .thursday, .saturday], "days: tues/thu/sat")
check(AssistantMatching.weekdays(from: []).isEmpty && AssistantMatching.meansOneTime(["once"]), "days: empty = once")

func found<T>(_ m: AssistantMatching.Match<T>) -> T? { if case .found(let x) = m { return x } else { return nil } }
func isAmbiguous<T>(_ m: AssistantMatching.Match<T>) -> Bool { if case .ambiguous = m { return true } else { return false } }
let gym = AlarmItem(hour: 7, minute: 0, label: "Gym", weekdays: Weekday.workdays)
let lazy = AlarmItem(hour: 9, minute: 30, label: "Lazy Sunday", weekdays: [.sunday])
let pm7 = AlarmItem(hour: 19, minute: 0, label: "Meds")
let alarmsList = [gym, lazy, pm7]
check(found(AssistantMatching.alarm(matching: "7:00 AM", in: alarmsList))?.id == gym.id, "alarm by explicit 7 AM")
check(found(AssistantMatching.alarm(matching: "19:00", in: alarmsList))?.id == pm7.id, "alarm by 19:00")
check(isAmbiguous(AssistantMatching.alarm(matching: "7", in: alarmsList)), "bare 7 matches 7 AM and 7 PM → ask")
check(found(AssistantMatching.alarm(matching: "7 gym", in: alarmsList))?.id == gym.id, "time + label disambiguates")
check(found(AssistantMatching.alarm(matching: "the gym alarm", in: alarmsList))?.id == gym.id, "alarm by label")
check(found(AssistantMatching.alarm(matching: "sunday", in: alarmsList))?.id == lazy.id, "alarm by label word")
check(found(AssistantMatching.alarm(matching: "9:30", in: alarmsList))?.id == lazy.id, "alarm 9:30")
if case .none = AssistantMatching.alarm(matching: "6am", in: alarmsList) { check(true, "no 6am alarm") } else { check(false, "no 6am alarm") }
check(found(AssistantMatching.alarm(matching: "my alarm", in: [gym]))?.id == gym.id, "only alarm → 'my alarm'")

let milk = TodoItem(title: "Buy milk"), mom = TodoItem(title: "Call mom about Sunday dinner")
var oldMilk = TodoItem(title: "Buy milk"); oldMilk.setDone(true)
let todosList = [oldMilk, milk, mom]
check(found(AssistantMatching.todo(matching: "buy milk", in: todosList))?.id == milk.id, "todo exact, prefers open over done")
check(found(AssistantMatching.todo(matching: "milk", in: todosList))?.id == milk.id, "todo contains")
check(found(AssistantMatching.todo(matching: "the call with mom", in: todosList))?.id == mom.id, "todo word overlap")
if case .none = AssistantMatching.todo(matching: "laundry", in: todosList) { check(true, "todo none") } else { check(false, "todo none") }

// Versioning.
check(AppVersion("1.10.0")! > AppVersion("1.9.2")!, "1.10.0 > 1.9.2")
check(AppVersion("1.5")! == AppVersion("1.5.0")! && AppVersion("v2.0")! > AppVersion("1.99.99")!, "1.5 == 1.5.0, v-prefix")
check(AppVersion("1.5.1")! > AppVersion("1.5")! && AppVersion("abc") == nil && AppVersion("") == nil, "patch bump, invalid")
check(Set([AppVersion("1.5")!, AppVersion("1.5.0")!]).count == 1, "hash agrees with ==")

let sample = try! Changelog.decode(Data("""
{"releases":[{"version":"1.2.0","date":"2026-01-02","notes":["b"]},{"version":"1.10.0","date":"2026-02-01","title":"Big","notes":["c"]},{"version":"1.0.0","date":"2025-12-01","notes":["a"]}]}
""".utf8))
check(sample.releases.map(\.version) == ["1.10.0", "1.2.0", "1.0.0"], "changelog sorted newest first")
check(sample.releases(newerThan: AppVersion("1.2.0")!).map(\.version) == ["1.10.0"], "pending releases")
check(sample.releases(after: AppVersion("1.0.0")!, upTo: AppVersion("1.10.0")!).map(\.version) == ["1.10.0", "1.2.0"], "what's new range")
let remoteSample = Changelog(releases: [Release(version: "1.11.0", build: 9, date: "2026-03-01", title: nil, notes: ["d"]),
                                        Release(version: "1.10.0", build: 8, date: "2026-02-01", title: "Big (edited)", notes: ["c"])])
check(sample.merged(with: remoteSample).releases.map(\.version) == ["1.11.0", "1.10.0", "1.2.0", "1.0.0"]
      && sample.merged(with: remoteSample).releases[1].title == "Big (edited)", "merge prefers fetched notes")
check(sample.releases[1].displayDate.hasSuffix("2, 2026"), "display date → \(sample.releases[1].displayDate)")

// The real CHANGELOG.json must be valid and match project.yml.
if let data = FileManager.default.contents(atPath: "CHANGELOG.json"), let log = try? Changelog.decode(data),
   let yml = try? String(contentsOfFile: "project.yml", encoding: .utf8) {
    func setting(_ key: String) -> String? {
        yml.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(key + ":") }
            .map { $0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
    }
    let latest = log.latest!
    check(setting("MARKETING_VERSION") == latest.version, "project.yml MARKETING_VERSION (\(setting("MARKETING_VERSION") ?? "?")) == newest changelog version (\(latest.version))")
    check(setting("CURRENT_PROJECT_VERSION") == latest.build.map(String.init), "project.yml build (\(setting("CURRENT_PROJECT_VERSION") ?? "?")) == newest changelog build")
    let versions = log.releases.compactMap(\.appVersion)
    check(versions.count == log.releases.count && Set(versions).count == versions.count, "changelog versions valid and unique")
    let builds = log.releases.compactMap(\.build)
    check(builds.count == log.releases.count && builds == builds.sorted(by: >) && Set(builds).count == builds.count, "build numbers present and increasing")
    check(log.releases.allSatisfy { !$0.notes.isEmpty && $0.date.split(separator: "-").count == 3 }, "every release has notes and a YYYY-MM-DD date")
} else {
    check(false, "CHANGELOG.json and project.yml readable and valid")
}

// Day parsing for chat edits (bug: "change which days my alarm is on").
func days(_ t: String) -> String { AssistantMatching.parseDays(t).map { $0.sorted().map { $0.shortName }.joined(separator: ",") } ?? "nil" }
check(days("monday, wednesday and friday") == "Mon,Wed,Fri", "one string with commas/and → \(days("monday, wednesday and friday"))")
check(days("every weekday") == "Mon,Tue,Wed,Thu,Fri", "every weekday")
check(days("Mon-Fri") == "Mon,Tue,Wed,Thu,Fri" && days("monday to friday") == "Mon,Tue,Wed,Thu,Fri", "ranges")
check(days("friday through monday") == "Sun,Mon,Fri,Sat", "wrapping range")
check(days("every day except sunday") == "Mon,Tue,Wed,Thu,Fri,Sat", "except")
check(days("weekends and wednesday") == "Sun,Wed,Sat", "weekend + day")
check(days("Tuesdays and Thursdays") == "Tue,Thu" && days("tues thurs") == "Tue,Thu", "plurals/abbrevs")
check(days("[\"Monday\",\"Friday\"]") == "Mon,Fri", "JSON-ish list")
check(days("all weekdays") == "Mon,Tue,Wed,Thu,Fri", "'all weekdays' isn't every day")
check(days("daily") == "Sun,Mon,Tue,Wed,Thu,Fri,Sat", "daily")
check(days("once") == "" && days("never") == "" && days("one-time") == "", "one-time")
check(days("purple") == "nil" && days("") == "nil", "unrecognized → nil (not one-time)")
check(days("the weekend") == "Sun,Sat", "'the' isn't Thursday")

// Saved data from older versions still loads.
let oldTodoJSON = #"[{"id":"7D5C2B1A-1111-4222-8333-944455556666","title":"Old","isDone":false,"createdAt":700000000}]"#
let decodedOld = try? JSONDecoder().decode([TodoItem].self, from: Data(oldTodoJSON.utf8))
check(decodedOld?.first?.title == "Old" && decodedOld?.first?.details == "", "to-do without details decodes")
var withDetails = TodoItem(title: "T", details: "Aisle 4"); withDetails.setDone(true)
check((try? JSONDecoder().decode(TodoItem.self, from: JSONEncoder().encode(withDetails))) == withDetails, "to-do round trip with details")
let note = Note(title: "Packing", body: "Socks\nCharger")
check(note.copyText == "Packing\n\nSocks\nCharger" && note.displayTitle == "Packing" && note.preview == "Socks Charger", "note copy/title/preview")
let untitled = Note(body: "Groceries\nMilk\nEggs")
check(untitled.displayTitle == "Groceries" && untitled.preview == "Milk Eggs" && untitled.copyText == "Groceries\nMilk\nEggs", "untitled note uses first line")
check(Note().isEmpty && Note().displayTitle == "New Note", "empty note")
check((try? JSONDecoder().decode(Note.self, from: Data(#"{"title":"x"}"#.utf8)))?.title == "x", "note decodes with missing fields")

// Note matching.
let packing = Note(title: "Packing list", body: "Socks, charger, passport")
let groceries = Note(body: "Groceries\nMilk\nEggs")
let meeting = Note(title: "Meeting with Sam", body: "Budget review and hiring plan")
let notesList = [packing, groceries, meeting]
check(found(AssistantMatching.note(matching: "my packing note", in: notesList))?.id == packing.id, "note by title word")
check(found(AssistantMatching.note(matching: "groceries", in: notesList))?.id == groceries.id, "untitled note by first line")
check(found(AssistantMatching.note(matching: "the meeting notes", in: notesList))?.id == meeting.id, "'the ... notes' filler ignored")
check(found(AssistantMatching.note(matching: "hiring plan", in: notesList))?.id == meeting.id, "note by body text")
if case .none = AssistantMatching.note(matching: "recipes", in: notesList) { check(true, "no note") } else { check(false, "no note") }

// Up Next widget ranking.
let unNow = d(2026, 11, 12, 6, 30)   // Thursday 6:30 AM
let wakeAlarm = AlarmItem(hour: 7, minute: 0, label: "Wake", weekdays: Weekday.workdays)      // in 30 min
let evening = AlarmItem(hour: 21, minute: 0, label: "Wind down", weekdays: Set(Weekday.allCases))
let runningTimer = TimerItem(id: UUID(), label: "Tea", duration: 300, state: .running, fireDate: unNow.addingTimeInterval(120), remaining: 300)
let pausedTimer = TimerItem(id: UUID(), label: "Bread", duration: 600, state: .paused, fireDate: unNow, remaining: 400)
let overdueTodo = TodoItem(title: "Pay bill", due: d(2026, 11, 12, 6, 0))
let soonTodo = TodoItem(title: "Leave for train", due: d(2026, 11, 12, 8, 0))
let laterTodo = TodoItem(title: "Dentist", due: d(2026, 11, 14, 9, 0))
let somedayTodo = TodoItem(title: "Read book")
func kinds(_ items: [UpNextItem]) -> [String] {
    items.map {
        switch $0.kind {
        case .alarmSoon(let a, _): "soon:\(a.label)"
        case .alarmDismissed(let a, _): "dismissed:\(a.label)"
        case .timer(let t): "timer:\(t.label)"
        case .todo(let t): "todo:\(t.title)"
        case .nextAlarm(let a, _): "next:\(a.label)"
        }
    }
}
let upNext = UpNext.items(alarms: [evening, wakeAlarm], todos: [somedayTodo, laterTodo, soonTodo, overdueTodo],
                          timers: [pausedTimer, runningTimer], now: unNow)
check(kinds(upNext) == ["soon:Wake", "timer:Tea", "timer:Bread", "todo:Pay bill", "todo:Leave for train", "next:Wind down", "todo:Dentist", "todo:Read book"],
      "up next order → \(kinds(upNext))")
var skippedWake = wakeAlarm; skippedWake.skippedOccurrence = d(2026, 11, 12, 7, 0)
check(kinds(UpNext.items(alarms: [skippedWake], todos: [], timers: [], now: unNow)) == ["dismissed:Wake"], "dismissed alarm shows with undo")
check(kinds(UpNext.items(alarms: [wakeAlarm], todos: [], timers: [], now: d(2026, 11, 12, 5, 0))) == ["next:Wake"], "alarm 2h away → next alarm, not dismissable")
check(kinds(UpNext.items(alarms: [], todos: [], timers: [], now: unNow)).isEmpty, "nothing → empty")
let changes = UpNext.changeDates(alarms: [wakeAlarm], todos: [soonTodo], timers: [runningTimer], now: unNow)
check(changes.first == unNow.addingTimeInterval(120) && changes.contains(d(2026, 11, 12, 7, 0)) && changes.contains(d(2026, 11, 12, 8, 0))
      && changes.contains(d(2026, 11, 13, 6, 0)), "widget refreshes at timer end, alarm, deadline, next heads-up window")
check(changes == changes.sorted() && changes.allSatisfy { $0 > unNow }, "change dates sorted and in the future")

// Time-of-day deadline options.
let tuesdayNoonish = d(2026, 11, 17, 12, 30)
check(TimeOfDay.evening.apply(to: d(2026, 11, 20, 9, 0), now: tuesdayNoonish) == d(2026, 11, 20, 18, 0), "evening keeps the chosen day")
check(TimeOfDay.afternoon.apply(to: tuesdayNoonish, now: tuesdayNoonish) == d(2026, 11, 17, 15, 0), "afternoon later today")
check(TimeOfDay.morning.apply(to: tuesdayNoonish, now: tuesdayNoonish) == d(2026, 11, 18, 9, 0), "morning already passed today → tomorrow")
check(TimeOfDay.matching(d(2026, 11, 17, 21, 0)) == .night && TimeOfDay.matching(d(2026, 11, 17, 21, 5)) == nil, "matching highlights exact times only")

// Deep links (widget taps).
let someID = UUID()
for link in [DeepLink.alarms, .alarm(someID), .timers, .todos, .todo(someID), .notes, .note(someID)] {
    check(DeepLink(url: link.url) == link, "deep link round trip \(link.url.absoluteString)")
}
check(DeepLink(url: URL(string: "https://example.com/alarm")!) == nil && DeepLink(url: URL(string: "alarmapp://bogus")!) == nil, "foreign/unknown links ignored")
check(UpNextItem(kind: .todo(TodoItem(id: someID, title: "x"))).deepLink == .todo(someID), "widget to-do row opens that to-do")
check(UpNextItem(kind: .nextAlarm(AlarmItem(id: someID, hour: 7, minute: 0), Date())).deepLink == .alarm(someID), "widget alarm row opens that alarm")

// Editing an alarm after it rang/was dismissed makes it a new system alarm.
var rang = AlarmItem(hour: 7, minute: 0, weekdays: Weekday.workdays)
let rangPlanIDs = Set(AlarmPlan.make(for: [rang], now: now).keys)
rang.revision += 1
check(Set(AlarmPlan.make(for: [rang], now: now).keys).isDisjoint(with: rangPlanIDs), "new revision → new AlarmKit IDs even at the same time")
let legacyAlarmJSON = #"{"id":"7D5C2B1A-1111-4222-8333-944455556666","hour":6,"minute":30,"label":"","weekdays":[2,3],"isEnabled":true}"#
let legacyAlarm = try? JSONDecoder().decode(AlarmItem.self, from: Data(legacyAlarmJSON.utf8))
check(legacyAlarm?.revision == 0 && legacyAlarm?.weekdays == [.monday, .tuesday], "alarms saved before revisions still load")
check(AlarmItem.headsUpInterval == 3600, "heads-up defaults to 1 hour")
check(AppSettings.leadTimeName(15) == "15 min" && AppSettings.leadTimeName(60) == "1 hour" && AppSettings.leadTimeName(120) == "2 hours" && AppSettings.leadTimeName(1440) == "1 day", "lead time names")

// Note sorting.
let t0 = d(2026, 11, 1, 9, 0)
let nA = Note(title: "Banana", createdAt: t0, updatedAt: t0.addingTimeInterval(300), sortIndex: 2)
let nB = Note(title: "apple", createdAt: t0.addingTimeInterval(100), updatedAt: t0.addingTimeInterval(100), sortIndex: 0)
let nC = Note(title: "Cherry", createdAt: t0.addingTimeInterval(200), updatedAt: t0.addingTimeInterval(200), isPinned: true, sortIndex: 5)
func titles(_ notes: [Note]) -> [String] { notes.map(\.title) }
check(titles(NotesSort.edited.sorted([nA, nB, nC])) == ["Cherry", "Banana", "apple"], "edited, pinned first")
check(titles(NotesSort.created.sorted([nA, nB, nC])) == ["Cherry", "apple", "Banana"], "created")
check(titles(NotesSort.title.sorted([nA, nB, nC])) == ["Cherry", "apple", "Banana"], "title, case-insensitive")
check(titles(NotesSort.manual.sorted([nA, nB, nC])) == ["Cherry", "apple", "Banana"], "manual uses sortIndex")
let legacyNote = try? JSONDecoder().decode(Note.self, from: Data(#"{"title":"old","createdAt":700000000}"#.utf8))
check(legacyNote?.isPinned == false && legacyNote?.sortIndex == -(Date(timeIntervalSinceReferenceDate: 700000000).timeIntervalSince1970), "old notes load unpinned, newest-first manual order")

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)

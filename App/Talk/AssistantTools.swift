import Foundation
import FoundationModels

// Tools the on-device model can call. Kept few and terse because the model's context is small.
// Every change adds a tappable event to the chat that opens the item.

// MARK: - Look up

struct ListItemsTool: Tool {
    let name = "listItems"
    let description = "Shows the user's current alarms, to-dos, timers, notes or settings. Use before editing if unsure what exists."

    @Generable
    enum Kind {
        case alarms, todos, timers, notes, settings
    }

    @Generable
    struct Arguments {
        @Guide(description: "What to list")
        var kind: Kind
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { () -> String in
            let now = Date()
            switch arguments.kind {
            case .alarms:
                let alarms = AlarmController.shared.sortedAlarms
                guard !alarms.isEmpty else { return "No alarms." }
                return alarms.map(AssistantText.describe).joined(separator: "\n")
            case .todos:
                let open = TodoController.shared.openTodos
                let doneCount = TodoController.shared.completedTodos.count
                guard !open.isEmpty else { return "No open to-dos." + (doneCount > 0 ? " \(doneCount) completed." : "") }
                return open.map { AssistantText.describe($0, now: now) }.joined(separator: "\n")
                    + (doneCount > 0 ? "\n(\(doneCount) completed)" : "")
            case .timers:
                let timers = TimerController.shared.timers
                guard !timers.isEmpty else { return "No timers running." }
                return timers.map { AssistantText.describe($0, now: now) }.joined(separator: "\n")
            case .notes:
                let notes = NotesController.shared.sortedNotes
                guard !notes.isEmpty else { return "No notes." }
                return notes.prefix(15).map { note in
                    let preview = note.preview.prefix(60)
                    return "\"\(note.displayTitle)\"" + (preview.isEmpty ? "" : ": \(preview)")
                }.joined(separator: "\n")
            case .settings:
                return """
                Require wake word: \(TalkSettings.wakeWordEnabled ? "on" : "off")
                Wake word: \(TalkSettings.wakeWord)
                Speak replies: \(TalkSettings.speakReplies ? "on" : "off")
                """
            }
        }
    }
}

// MARK: - Timers

struct SetTimerTool: Tool {
    let name = "setTimer"
    let description = "Starts a countdown timer."

    @Generable
    struct Arguments {
        @Guide(description: "Length in seconds, e.g. 300 for 5 minutes")
        var seconds: Int
        @Guide(description: "Short name like \"Pasta\", or empty")
        var label: String
    }

    func call(arguments: Arguments) async throws -> String {
        let seconds = min(max(arguments.seconds, 1), 24 * 3600)
        let label = arguments.label.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let timer = try await TimerController.shared.start(duration: TimeInterval(seconds), label: label)
            await TalkModel.shared.addEvent("Timer · \(timer.title) · \(TimeFormat.clock(timer.duration))", systemImage: "timer", link: .timers)
            return "Started a timer for \(TimeFormat.durationName(timer.duration))\(label.isEmpty ? "" : " called \(label)")."
        } catch {
            return "Couldn't start the timer: \(error.localizedDescription)"
        }
    }
}

struct CancelTimersTool: Tool {
    let name = "cancelTimers"
    let description = "Cancels a timer by name, or all timers if the name is empty."

    @Generable
    struct Arguments {
        @Guide(description: "Timer name, or empty for all")
        var label: String
    }

    func call(arguments: Arguments) async throws -> String {
        let label = arguments.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cancelled: [String] = await MainActor.run { () -> [String] in
            let controller = TimerController.shared
            let matches = controller.timers.filter { label.isEmpty || $0.title.lowercased().contains(label) }
            matches.forEach { controller.cancel($0.id) }
            return matches.map(\.title)
        }
        guard !cancelled.isEmpty else { return "No matching timer." }
        await TalkModel.shared.addEvent("Cancelled \(cancelled.joined(separator: ", "))", systemImage: "xmark.circle", link: .timers)
        return "Cancelled: \(cancelled.joined(separator: ", "))."
    }
}

// MARK: - Alarms

struct CreateAlarmTool: Tool {
    let name = "createAlarm"
    let description = "Creates a new alarm."

    @Generable
    struct Arguments {
        @Guide(description: "Hour, 24-hour clock (0-23)")
        var hour: Int
        @Guide(description: "Minute (0-59)")
        var minute: Int
        @Guide(description: "Days it repeats in words, e.g. \"weekdays\", \"monday and friday\", \"every day\". Empty for a one-time alarm.")
        var repeatDays: String
        @Guide(description: "Short label, or empty")
        var label: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard (0...23).contains(arguments.hour), (0...59).contains(arguments.minute) else {
            return "That isn't a valid time."
        }
        let daysText = arguments.repeatDays.trimmingCharacters(in: .whitespacesAndNewlines)
        let days: Set<Weekday>
        if daysText.isEmpty {
            days = []
        } else if let parsed = AssistantMatching.parseDays(daysText) {
            days = parsed
        } else {
            return "Not created: couldn't understand the days \"\(daysText)\". Use day names, \"weekdays\", \"weekends\" or \"every day\"."
        }

        let alarm = AlarmItem(
            hour: arguments.hour,
            minute: arguments.minute,
            label: arguments.label.trimmingCharacters(in: .whitespacesAndNewlines),
            weekdays: days
        )
        await MainActor.run { AlarmController.shared.save(alarm) }
        await TalkModel.shared.addEvent("Alarm set · \(alarm.timeString) · \(alarm.repeatSummary)", systemImage: "alarm", link: .alarm(alarm.id))
        return "Created alarm: \(AssistantText.describe(alarm))."
    }
}

struct EditAlarmTool: Tool {
    let name = "editAlarm"
    let description = "Changes an existing alarm (time, days, label, sound), turns it on or off, or deletes it."

    @Generable
    enum Action {
        case change, turnOn, turnOff, delete
    }

    @Generable
    struct Arguments {
        @Guide(description: "Which alarm: its time like \"7:00 AM\" or its label")
        var alarm: String
        @Guide(description: "change for time, days or label edits")
        var action: Action
        @Guide(description: "New hour, 24-hour clock. Only when changing the time.")
        var newHour: Int?
        @Guide(description: "New minute. Only when changing the time.")
        var newMinute: Int?
        @Guide(description: "Replace the days, in words: \"weekdays\", \"tuesday and thursday\", \"every day except sunday\", or \"once\"")
        var newDays: String?
        @Guide(description: "Days to add, in words, e.g. \"saturday\"")
        var addDays: String?
        @Guide(description: "Days to remove, in words, e.g. \"friday\"")
        var removeDays: String?
        @Guide(description: "New label")
        var newLabel: String?
        @Guide(description: "New sound: Default, Chime, Beacon, Pulse, Rise or Bells")
        var newSound: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { () -> String in
            let controller = AlarmController.shared
            let alarm: AlarmItem
            switch AssistantMatching.alarm(matching: arguments.alarm, in: controller.sortedAlarms) {
            case .found(let match):
                alarm = match
            case .none:
                return "No alarm matches \"\(arguments.alarm)\". Alarms: " + AssistantText.alarmList(controller.sortedAlarms)
            case .ambiguous(let matches):
                return "Several alarms match. Which one? " + AssistantText.alarmList(matches)
            }
            let link = ChatLink.alarm(alarm.id)

            switch arguments.action {
            case .delete:
                controller.delete(alarm.id)
                TalkModel.shared.addEvent("Deleted \(alarm.timeString) alarm", systemImage: "trash")
                return "Deleted the \(alarm.timeString) alarm."

            case .turnOn, .turnOff:
                let on: Bool = { if case .turnOn = arguments.action { return true } else { return false } }()
                controller.setEnabled(on, for: alarm.id)
                TalkModel.shared.addEvent("\(alarm.timeString) alarm \(on ? "on" : "off")", systemImage: on ? "alarm" : "bell.slash", link: link)
                return "Turned the \(alarm.timeString) alarm \(on ? "on" : "off")."

            case .change:
                var updated = alarm

                // Time. Passing the same hour keeps the minutes.
                if let hour = arguments.newHour, (0...23).contains(hour) {
                    updated.hour = hour
                    if let minute = arguments.newMinute, (0...59).contains(minute) {
                        updated.minute = minute
                    } else if hour != alarm.hour {
                        updated.minute = 0
                    }
                } else if let minute = arguments.newMinute, (0...59).contains(minute) {
                    updated.minute = minute
                }

                // Days. Anything not understood is reported back instead of silently clearing the days.
                func days(_ text: String?) -> (Set<Weekday>?, String?) {
                    guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return (nil, nil) }
                    guard let parsed = AssistantMatching.parseDays(text) else { return (nil, text) }
                    return (parsed, nil)
                }
                let (replacement, badReplace) = days(arguments.newDays)
                let (added, badAdd) = days(arguments.addDays)
                let (removed, badRemove) = days(arguments.removeDays)
                if let bad = badReplace ?? badAdd ?? badRemove {
                    return "Nothing changed: couldn't understand the days \"\(bad)\". Use day names, \"weekdays\", \"weekends\" or \"every day\"."
                }
                if let replacement { updated.weekdays = replacement }
                if let added { updated.weekdays.formUnion(added) }
                if let removed { updated.weekdays.subtract(removed) }

                if let label = arguments.newLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                    updated.label = label
                }
                if let soundText = arguments.newSound?.trimmingCharacters(in: .whitespacesAndNewlines), !soundText.isEmpty {
                    guard let sound = AlarmSound(name: soundText) else {
                        return "Nothing changed: there's no sound called \"\(soundText)\". Sounds: "
                            + AlarmSound.allCases.map(\.name).joined(separator: ", ") + "."
                    }
                    updated.sound = sound
                }

                guard updated.hour != alarm.hour || updated.minute != alarm.minute || updated.weekdays != alarm.weekdays
                        || updated.label != alarm.label || updated.sound != alarm.sound || !alarm.isEnabled else {
                    return "Nothing to change. Say the new time, days, label or sound."
                }
                controller.save(updated)
                TalkModel.shared.addEvent("Alarm updated · \(updated.timeString) · \(updated.repeatSummary)", systemImage: "alarm", link: link)
                return "Updated alarm: \(AssistantText.describe(updated))."
            }
        }
    }
}

// MARK: - To-dos

struct CreateTodoTool: Tool {
    let name = "createTodo"
    let description = "Adds a to-do or reminder, optionally with a deadline. The user gets a notification at the deadline."

    @Generable
    struct Arguments {
        @Guide(description: "What to do, short")
        var title: String
        @Guide(description: "Optional extra detail shown under the title")
        var details: String?
        @Guide(description: "Deadline day: \"today\", \"tomorrow\", a weekday, or a date like 2026-11-14. Omit if none.")
        var day: String?
        @Guide(description: "Deadline time like \"17:00\". Omit if none.")
        var time: String?
        @Guide(description: "For \"in N minutes\": N. Omit otherwise.")
        var minutesFromNow: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "The to-do needs a title." }
        let now = Date()
        let due = NaturalTime.resolveDue(day: arguments.day, time: arguments.time, minutesFromNow: arguments.minutesFromNow, now: now)
        let todo = await MainActor.run { TodoController.shared.add(title: title, details: arguments.details ?? "", due: due) }

        let when = due.map { " · \(TimeFormat.dueDescription($0, relativeTo: now))" } ?? ""
        await TalkModel.shared.addEvent("To-do added · \(todo.title)\(when)", systemImage: "checklist", link: .todo(todo.id))

        let askedForDeadline = [arguments.day, arguments.time].contains { !($0 ?? "").isEmpty }
        if due == nil && askedForDeadline {
            return "Added \"\(title)\" but couldn't understand the deadline, so it has none."
        }
        return "Added \"\(title)\"" + (due.map { ", due \(TimeFormat.dueDescription($0, relativeTo: now))" } ?? "") + "."
    }
}

struct EditTodoTool: Tool {
    let name = "editTodo"
    let description = "Changes, completes, reopens or deletes an existing to-do."

    @Generable
    enum Action {
        case change, complete, reopen, delete
    }

    @Generable
    struct Arguments {
        @Guide(description: "Which to-do: its title or part of it")
        var todo: String
        var action: Action
        @Guide(description: "New title")
        var newTitle: String?
        @Guide(description: "New extra detail shown under the title")
        var newDetails: String?
        @Guide(description: "New deadline day: \"today\", \"tomorrow\", a weekday, or a date like 2026-11-14")
        var day: String?
        @Guide(description: "New deadline time like \"17:00\"")
        var time: String?
        @Guide(description: "New deadline in N minutes from now")
        var minutesFromNow: Int?
        @Guide(description: "True to remove the deadline")
        var removeDeadline: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { () -> String in
            let controller = TodoController.shared
            var todo: TodoItem
            switch AssistantMatching.todo(matching: arguments.todo, in: controller.todos) {
            case .found(let match):
                todo = match
            case .none:
                return "No to-do matches \"\(arguments.todo)\". To-dos: " + AssistantText.todoList(controller.openTodos)
            case .ambiguous(let matches):
                return "Several to-dos match. Which one? " + AssistantText.todoList(matches)
            }
            let link = ChatLink.todo(todo.id)

            switch arguments.action {
            case .delete:
                controller.delete(todo.id)
                TalkModel.shared.addEvent("Deleted · \(todo.title)", systemImage: "trash")
                return "Deleted \"\(todo.title)\"."
            case .complete, .reopen:
                let done: Bool = { if case .complete = arguments.action { return true } else { return false } }()
                todo.setDone(done)
                controller.update(todo)
                TalkModel.shared.addEvent("\(done ? "Done" : "Reopened") · \(todo.title)", systemImage: done ? "checkmark.circle.fill" : "circle", link: link)
                return "Marked \"\(todo.title)\" as \(done ? "done" : "not done")."
            case .change:
                let now = Date()
                if let title = arguments.newTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    todo.title = title
                }
                if let details = arguments.newDetails {
                    todo.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if arguments.removeDeadline == true {
                    todo.due = nil
                } else if let newDue = Self.newDue(for: todo, arguments: arguments, now: now) {
                    todo.due = newDue
                }
                controller.update(todo)
                TalkModel.shared.addEvent("To-do updated · \(todo.title)" + (todo.due.map { " · \(TimeFormat.dueDescription($0, relativeTo: now))" } ?? ""),
                                          systemImage: "checklist", link: link)
                return "Updated: \(AssistantText.describe(todo, now: now))."
            }
        }
    }

    /// Keeps the existing date when only a time is given (and vice versa).
    private static func newDue(for todo: TodoItem, arguments: Arguments, now: Date) -> Date? {
        var day = arguments.day.flatMap { $0.isEmpty ? nil : $0 }
        var time = arguments.time.flatMap { $0.isEmpty ? nil : $0 }
        if let existing = todo.due, arguments.minutesFromNow == nil {
            let calendar = Calendar.current
            if day == nil, time != nil, existing > now {
                let c = calendar.dateComponents([.year, .month, .day], from: existing)
                day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            }
            if time == nil, day != nil {
                let c = calendar.dateComponents([.hour, .minute], from: existing)
                time = String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0)
            }
        }
        return NaturalTime.resolveDue(day: day, time: time, minutesFromNow: arguments.minutesFromNow, now: now)
    }
}

// MARK: - Notes

struct ReadNoteTool: Tool {
    let name = "readNote"
    let description = "Returns the full text of one of the user's notes, to answer questions about it or use its contents. Lines starting with ☐ are unchecked checklist items, ☑ are checked."

    @Generable
    struct Arguments {
        @Guide(description: "Which note: its title or words from it")
        var note: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { () -> String in
            let notes = NotesController.shared.sortedNotes
            switch AssistantMatching.note(matching: arguments.note, in: notes) {
            case .found(let note):
                TalkModel.shared.addEvent("Read note · \(note.displayTitle)", systemImage: "note.text", link: .note(note.id))
                let body = note.body.count > 2_000 ? String(note.body.prefix(2_000)) + "…" : note.body
                return "Note \"\(note.displayTitle)\":\n\(body)"
            case .none:
                return "No note matches \"\(arguments.note)\". Notes: " + AssistantText.noteList(notes)
            case .ambiguous(let matches):
                return "Several notes match. Which one? " + AssistantText.noteList(matches)
            }
        }
    }
}

struct WriteNoteTool: Tool {
    let name = "writeNote"
    let description = "Creates a note, adds text to the end of a note, replaces a note's text, renames it, or deletes it."

    @Generable
    enum Action {
        case create, append, replace, rename, delete
    }

    @Generable
    struct Arguments {
        var action: Action
        @Guide(description: "For create: the new title. Otherwise: which note, by title or words from it.")
        var note: String
        @Guide(description: "The text to write (create, append, replace) or the new title (rename). For a checklist or to-do list in a note, start each item's line with ☐ (or ☑ when done).")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { () -> String in
            let controller = NotesController.shared
            let text = arguments.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if case .create = arguments.action {
                let note = controller.add(title: arguments.note.trimmingCharacters(in: .whitespacesAndNewlines), body: text)
                TalkModel.shared.addEvent("Note created · \(note.displayTitle)", systemImage: "note.text.badge.plus", link: .note(note.id))
                return "Created the note \"\(note.displayTitle)\"."
            }

            var note: Note
            switch AssistantMatching.note(matching: arguments.note, in: controller.sortedNotes) {
            case .found(let match):
                note = match
            case .none:
                return "No note matches \"\(arguments.note)\". Notes: " + AssistantText.noteList(controller.sortedNotes)
            case .ambiguous(let matches):
                return "Several notes match. Which one? " + AssistantText.noteList(matches)
            }

            switch arguments.action {
            case .create:
                return ""
            case .append:
                guard !text.isEmpty else { return "Nothing to add." }
                // Adding to a checklist adds checklist items.
                note.body = NoteChecklist.appending(text, to: note.body)
            case .replace:
                note.body = text
            case .rename:
                guard !text.isEmpty else { return "The new title is empty." }
                note.title = text
            case .delete:
                controller.delete(note.id)
                TalkModel.shared.addEvent("Deleted note · \(note.displayTitle)", systemImage: "trash")
                return "Deleted the note \"\(note.displayTitle)\"."
            }
            controller.update(note)
            TalkModel.shared.addEvent("Note updated · \(note.displayTitle)", systemImage: "note.text", link: .note(note.id))
            return "Updated the note \"\(note.displayTitle)\"."
        }
    }
}

// MARK: - Settings

struct UpdateSettingsTool: Tool {
    let name = "updateSettings"
    let description = "Changes the user's settings. Only pass the settings to change."

    @Generable
    struct Arguments {
        @Guide(description: "Whether Live Talk only answers sentences starting with the wake word")
        var requireWakeWord: Bool?
        @Guide(description: "The wake word, e.g. \"Hey Alarm\"")
        var wakeWord: String?
        @Guide(description: "Whether replies are spoken aloud in Live Talk")
        var speakReplies: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        let defaults = UserDefaults.standard
        var changes: [String] = []
        if let word = arguments.wakeWord?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty {
            defaults.set(word, forKey: TalkSettings.wakeWordKey)
            changes.append("wake word is now \"\(word)\"")
        }
        if let require = arguments.requireWakeWord {
            defaults.set(require, forKey: TalkSettings.wakeWordEnabledKey)
            changes.append("wake word \(require ? "required" : "not required")")
        }
        if let speak = arguments.speakReplies {
            defaults.set(speak, forKey: TalkSettings.speakRepliesKey)
            changes.append("spoken replies \(speak ? "on" : "off")")
        }
        guard !changes.isEmpty else { return "Nothing was changed." }
        let summary = changes.joined(separator: ", ")
        await TalkModel.shared.addEvent("Settings · \(summary)", systemImage: "gearshape")
        return "Settings updated: \(summary)."
    }
}

// MARK: - Descriptions for the model

enum AssistantText {
    static func describe(_ alarm: AlarmItem) -> String {
        var parts = [alarm.timeString, alarm.repeatSummary]
        if !alarm.label.isEmpty { parts.append("\"\(alarm.label)\"") }
        if alarm.sound != .default { parts.append("sound \(alarm.sound.name)") }
        parts.append(alarm.isEnabled ? "on" : "off")
        return parts.joined(separator: ", ")
    }

    static func describe(_ todo: TodoItem, now: Date) -> String {
        var text = "\"\(todo.title)\""
        if !todo.trimmedDetails.isEmpty { text += " (\(todo.trimmedDetails.prefix(60)))" }
        if todo.isDone { return text + " (done)" }
        if let due = todo.due {
            text += todo.isOverdue(at: now) ? ", overdue since " : ", due "
            text += TimeFormat.dueDescription(due, relativeTo: now)
        }
        return text
    }

    static func describe(_ timer: TimerItem, now: Date) -> String {
        switch timer.state {
        case .ringing: "\(timer.title): finished, ringing"
        case .paused: "\(timer.title): paused, \(TimeFormat.durationName(timer.remaining)) left"
        case .running: "\(timer.title): \(TimeFormat.durationName(timer.timeLeft(at: now))) left"
        }
    }

    static func alarmList(_ alarms: [AlarmItem]) -> String {
        alarms.isEmpty ? "none" : alarms.map(describe).joined(separator: "; ")
    }

    static func todoList(_ todos: [TodoItem]) -> String {
        todos.isEmpty ? "none" : todos.prefix(8).map { describe($0, now: Date()) }.joined(separator: "; ")
    }

    static func noteList(_ notes: [Note]) -> String {
        notes.isEmpty ? "none" : notes.prefix(10).map { "\"\($0.displayTitle)\"" }.joined(separator: ", ")
    }
}

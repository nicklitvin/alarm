import Foundation
import FoundationModels

// Tools the on-device model can call. Kept few and terse because the model's context is small.

// MARK: - Look up

struct ListItemsTool: Tool {
    let name = "listItems"
    let description = "Shows the user's current alarms, to-dos, timers or settings. Use before editing if unsure what exists."

    @Generable
    enum Kind {
        case alarms, todos, timers, settings
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
            await TalkModel.shared.addEvent("Timer · \(timer.title) · \(TimeFormat.clock(timer.duration))", systemImage: "timer")
            return "Started a \(TimeFormat.durationName(timer.duration)) timer\(label.isEmpty ? "" : " called \(label)")."
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
        await TalkModel.shared.addEvent("Cancelled \(cancelled.joined(separator: ", "))", systemImage: "xmark.circle")
        return "Cancelled: \(cancelled.joined(separator: ", "))."
    }
}

// MARK: - Alarms

struct CreateAlarmTool: Tool {
    let name = "createAlarm"
    let description = "Creates an alarm."

    @Generable
    struct Arguments {
        @Guide(description: "Hour, 24-hour clock (0-23)")
        var hour: Int
        @Guide(description: "Minute (0-59)")
        var minute: Int
        @Guide(description: "Repeat days, e.g. [\"monday\",\"friday\"], [\"weekdays\"], [\"weekends\"], [\"every day\"]. Empty for one time.")
        var repeatDays: [String]
        @Guide(description: "Short label, or empty")
        var label: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard (0...23).contains(arguments.hour), (0...59).contains(arguments.minute) else {
            return "That isn't a valid time."
        }
        let alarm = AlarmItem(
            hour: arguments.hour,
            minute: arguments.minute,
            label: arguments.label.trimmingCharacters(in: .whitespacesAndNewlines),
            weekdays: AssistantMatching.weekdays(from: arguments.repeatDays)
        )
        await MainActor.run { AlarmController.shared.save(alarm) }
        let text = AssistantText.describe(alarm)
        await TalkModel.shared.addEvent("Alarm set · \(alarm.timeString) · \(alarm.repeatSummary)", systemImage: "alarm")
        return "Created alarm: \(text)."
    }
}

struct EditAlarmTool: Tool {
    let name = "editAlarm"
    let description = "Changes, turns on/off, or deletes an existing alarm."

    @Generable
    enum Action {
        case change, turnOn, turnOff, delete
    }

    @Generable
    struct Arguments {
        @Guide(description: "Which alarm: its time like \"7:00 AM\" or its label")
        var alarm: String
        var action: Action
        @Guide(description: "New hour, 24-hour clock, only when changing the time")
        var newHour: Int?
        @Guide(description: "New minute, only when changing the time")
        var newMinute: Int?
        @Guide(description: "New repeat days like [\"weekdays\"], or [\"once\"] for one time")
        var newRepeatDays: [String]?
        @Guide(description: "New label")
        var newLabel: String?
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

            switch arguments.action {
            case .delete:
                controller.delete(alarm.id)
                TalkModel.shared.addEvent("Deleted \(alarm.timeString) alarm", systemImage: "trash")
                return "Deleted the \(alarm.timeString) alarm."
            case .turnOn, .turnOff:
                let on: Bool = { if case .turnOn = arguments.action { return true } else { return false } }()
                controller.setEnabled(on, for: alarm.id)
                TalkModel.shared.addEvent("\(alarm.timeString) alarm \(on ? "on" : "off")", systemImage: on ? "alarm" : "bell.slash")
                return "Turned the \(alarm.timeString) alarm \(on ? "on" : "off")."
            case .change:
                var updated = alarm
                if let hour = arguments.newHour, (0...23).contains(hour) {
                    updated.hour = hour
                    updated.minute = arguments.newMinute.flatMap { (0...59).contains($0) ? $0 : nil } ?? 0
                } else if let minute = arguments.newMinute, (0...59).contains(minute) {
                    updated.minute = minute
                }
                if let days = arguments.newRepeatDays, !days.isEmpty {
                    updated.weekdays = AssistantMatching.meansOneTime(days) ? [] : AssistantMatching.weekdays(from: days)
                }
                if let label = arguments.newLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                    updated.label = label
                }
                controller.save(updated)
                TalkModel.shared.addEvent("Alarm updated · \(updated.timeString) · \(updated.repeatSummary)", systemImage: "alarm")
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
        let todo = await MainActor.run { TodoController.shared.add(title: title, due: due) }

        let when = due.map { " · \(TimeFormat.dueDescription($0, relativeTo: now))" } ?? ""
        await TalkModel.shared.addEvent("To-do added · \(todo.title)\(when)", systemImage: "checklist")

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

            switch arguments.action {
            case .delete:
                controller.delete(todo.id)
                TalkModel.shared.addEvent("Deleted · \(todo.title)", systemImage: "trash")
                return "Deleted \"\(todo.title)\"."
            case .complete, .reopen:
                let done: Bool = { if case .complete = arguments.action { return true } else { return false } }()
                todo.setDone(done)
                controller.update(todo)
                TalkModel.shared.addEvent("\(done ? "Done" : "Reopened") · \(todo.title)", systemImage: done ? "checkmark.circle.fill" : "circle")
                return "Marked \"\(todo.title)\" as \(done ? "done" : "not done")."
            case .change:
                let now = Date()
                if let title = arguments.newTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    todo.title = title
                }
                if arguments.removeDeadline == true {
                    todo.due = nil
                } else if let newDue = Self.newDue(for: todo, arguments: arguments, now: now) {
                    todo.due = newDue
                }
                controller.update(todo)
                TalkModel.shared.addEvent("To-do updated · \(todo.title)" + (todo.due.map { " · \(TimeFormat.dueDescription($0, relativeTo: now))" } ?? ""),
                                          systemImage: "checklist")
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
        parts.append(alarm.isEnabled ? "on" : "off")
        return parts.joined(separator: ", ")
    }

    static func describe(_ todo: TodoItem, now: Date) -> String {
        var text = "\"\(todo.title)\""
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
}

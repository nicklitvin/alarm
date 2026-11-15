import SwiftUI
import WidgetKit

/// Settings for one tab (mostly when to notify), plus About & Updates.
struct TabSettingsView: View {
    let tab: AppTab

    var body: some View {
        NavigationStack {
            Form {
                switch tab {
                case .alarms: AlarmSettingsSection()
                case .timers: TimerSettingsSection()
                case .todos: TodoSettingsSection()
                case .notes: NotesSettingsSection()
                case .talk: TalkSettingsSection()
                }

                if tab != .talk {
                    DeleteAllSection(tab: tab)
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack {
                            Label("About & Updates", systemImage: "info.circle")
                            Spacer()
                            if UpdateChecker.shared.updateAvailable {
                                Text("Update")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.red))
                            } else {
                                Text("Version \(UpdateChecker.shared.installedVersionString)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // No Done button: swipe the sheet down to close it.
        }
        .tint(.orange)
    }

    private var title: String {
        switch tab {
        case .alarms: "Alarm Settings"
        case .timers: "Timer Settings"
        case .todos: "To-Do Settings"
        case .notes: "Notes Settings"
        case .talk: "Talk Settings"
        }
    }
}

// MARK: - Delete all

/// "Delete All Alarms / Timers / To-Dos / Notes", with a confirmation.
private struct DeleteAllSection: View {
    let tab: AppTab
    @State private var confirming = false

    var body: some View {
        Section {
            Button(role: .destructive) {
                if count > 0 { confirming = true }
            } label: {
                Label(title, systemImage: "trash")
            }
            .foregroundStyle(.red) // same red on every tab, even when there's nothing to delete
        } footer: {
            Text(footer)
        }
        .alert(question, isPresented: $confirming) {
            Button("Delete All", role: .destructive, action: deleteAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private var count: Int {
        switch tab {
        case .alarms: AlarmController.shared.alarms.count
        case .timers: TimerController.shared.timers.count + TimerController.shared.recents.count
            + (StopwatchController.shared.stopwatch.isReset ? 0 : 1)
        case .todos: TodoController.shared.todos.count
        case .notes: NotesController.shared.notes.count
        case .talk: 0
        }
    }

    private var title: String {
        switch tab {
        case .alarms: "Delete All Alarms"
        case .timers: "Delete All Timers"
        case .todos: "Delete All To-Dos"
        case .notes: "Delete All Notes"
        case .talk: ""
        }
    }

    private var question: String {
        switch tab {
        case .alarms: "Delete all \(count) alarm\(count == 1 ? "" : "s")?"
        case .timers: "Cancel running timers and clear recent times?"
        case .todos: "Delete all \(count) to-do\(count == 1 ? "" : "s"), including completed ones?"
        case .notes: "Delete all \(count) note\(count == 1 ? "" : "s")?"
        case .talk: ""
        }
    }

    private var footer: String {
        switch tab {
        case .timers: "Cancels any running timers, resets the stopwatch and clears your recent times."
        default: "Removes everything on this tab."
        }
    }

    private func deleteAll() {
        switch tab {
        case .alarms: AlarmController.shared.deleteAll()
        case .timers:
            TimerController.shared.deleteAll()
            StopwatchController.shared.reset()
        case .todos: TodoController.shared.deleteAll()
        case .notes: NotesController.shared.deleteAll()
        case .talk: break
        }
    }
}

// MARK: - Alarms

private struct AlarmSettingsSection: View {
    @AppStorage(AppSettings.alarmHeadsUpEnabledKey, store: AppSettings.store) private var headsUpEnabled = true
    @AppStorage(AppSettings.alarmHeadsUpMinutesKey, store: AppSettings.store) private var headsUpMinutes = 60

    var body: some View {
        Section {
            Toggle("Heads-Up Notification", isOn: $headsUpEnabled)
            Picker("Notify Me", selection: $headsUpMinutes) {
                ForEach(AppSettings.alarmHeadsUpChoices, id: \.self) { minutes in
                    Text("\(AppSettings.leadTimeName(minutes)) before").tag(minutes)
                }
            }
            .disabled(!headsUpEnabled)
        } header: {
            Text("Notifications")
        } footer: {
            Text(headsUpEnabled
                 ? "You'll get a notification \(AppSettings.leadTimeName(headsUpMinutes)) before each alarm, with a button to dismiss that ring. The Dismiss button in the app and widget appears at the same time."
                 : "No notification before alarms. You can still dismiss the next ring from the app and widget \(AppSettings.leadTimeName(headsUpMinutes)) before it.")
        }
        .onChange(of: headsUpEnabled) { AlarmController.shared.refresh() }
        .onChange(of: headsUpMinutes) { AlarmController.shared.refresh() }

        WidgetToggles(rows: [
            ("Show Alarms", AppSettings.widgetShowsAlarmsKey),
        ], footer: "Whether alarms appear in the Up Next widget. The Next Alarm widget always shows them.")
    }
}

/// "Widget" section: what the Up Next widget includes.
private struct WidgetToggles: View {
    let rows: [(title: String, key: String)]
    let footer: String

    var body: some View {
        Section {
            ForEach(rows, id: \.key) { row in
                WidgetToggleRow(title: row.title, key: row.key)
            }
        } header: {
            Text("Up Next Widget")
        } footer: {
            Text(footer)
        }
    }
}

private struct WidgetToggleRow: View {
    let title: String
    @AppStorage private var isOn: Bool

    init(title: String, key: String) {
        self.title = title
        _isOn = AppStorage(wrappedValue: true, key, store: AppSettings.store)
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .onChange(of: isOn) { WidgetCenter.shared.reloadAllTimelines() }
    }
}

// MARK: - Timers

/// Timers have no settings of their own (just Delete All and About below).
/// The three one-tap times in New Timer, or "Use Recent Times" to show your last three instead.
/// Tap a time to set it with hour and minute wheels, right below (no extra pop-up).
private struct TimerSettingsSection: View {
    @AppStorage(AppSettings.timerQuickTimesKey, store: AppSettings.store) private var stored = ""
    @AppStorage(AppSettings.timerUsesRecentTimesKey, store: AppSettings.store) private var useRecent = false
    /// The quick time being changed with the wheels.
    @State private var editing: Int?

    private var times: [Int] { AppSettings.parseTimerQuickTimes(stored) }

    var body: some View {
        Section {
            Toggle("Use Recent Times", isOn: $useRecent.animation())
            if !useRecent {
                HStack(spacing: 8) {
                    ForEach(Array(times.enumerated()), id: \.offset) { index, seconds in
                        let selected = editing == index
                        Button {
                            withAnimation(.snappy) { editing = selected ? nil : index }
                        } label: {
                            Text(TimeFormat.compactDuration(TimeInterval(seconds)))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize()
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Color.orange : Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)

                if let index = editing, index < times.count {
                    DurationWheel(hours: component(index, unit: 3600, max: 24),
                                  minutes: component(index, unit: 60, max: 60),
                                  seconds: .constant(0), showsSeconds: false)
                        .transition(.opacity)
                }
            }
        } header: {
            Text("Quick Times")
        } footer: {
            Text(useRecent
                 ? "New Timer shows the last three times you used."
                 : "One-tap times in New Timer. Tap one to change it with the wheels, or turn on Use Recent Times to show your last three times instead.")
        }
    }

    /// The hours or minutes of quick time `index`, for a wheel. Never lets a time become zero.
    private func component(_ index: Int, unit: Int, max: Int) -> Binding<Int> {
        Binding(
            get: { (times[index] / unit) % max },
            set: { newValue in
                var list = times
                let current = list[index]
                let hours = unit == 3600 ? newValue : current / 3600
                let minutes = unit == 60 ? newValue : (current % 3600) / 60
                list[index] = Swift.max(60, hours * 3600 + minutes * 60)
                stored = list.map(String.init).joined(separator: ",")
            }
        )
    }
}

// MARK: - To-dos

private struct TodoSettingsSection: View {
    @AppStorage(AppSettings.todoDueAlertEnabledKey, store: AppSettings.store) private var dueAlert = true
    @AppStorage(AppSettings.todoEarlyReminderMinutesKey, store: AppSettings.store) private var earlyMinutes = 0

    var body: some View {
        Section {
            Toggle("At the Deadline", isOn: $dueAlert)
            Picker("Early Reminder", selection: $earlyMinutes) {
                ForEach(AppSettings.todoEarlyReminderChoices, id: \.self) { minutes in
                    Text(minutes == 0 ? "None" : "\(AppSettings.leadTimeName(minutes)) before").tag(minutes)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(footer)
        }
        .onChange(of: dueAlert) { TodoController.shared.refreshReminders() }
        .onChange(of: earlyMinutes) { TodoController.shared.refreshReminders() }

        QuickTimesSection()

        WidgetToggles(rows: [
            ("To-Dos with a Deadline", AppSettings.widgetShowsTimedTodosKey),
            ("To-Dos without a Deadline", AppSettings.widgetShowsUntimedTodosKey),
        ], footer: "Choose which to-dos appear in the Up Next widget.")
    }

    private var footer: String {
        switch (dueAlert, earlyMinutes) {
        case (false, 0): "No notifications for to-dos. Deadlines still show in the app and widget."
        case (true, 0): "You'll get a notification when a to-do is due."
        case (false, let m): "You'll get a reminder \(AppSettings.leadTimeName(m)) before each deadline."
        case (true, let m): "You'll get a reminder \(AppSettings.leadTimeName(m)) before each deadline, and another when it's due."
        }
    }
}

/// The three quick times shown under a deadline (8 AM, 2 PM and 9 PM by default), stretched
/// across the row like the timer quick times. Tap one to change it with a time wheel right
/// below (no extra pop-up).
private struct QuickTimesSection: View {
    @AppStorage(AppSettings.todoQuickTimesKey, store: AppSettings.store) private var stored = ""
    /// The quick time being changed with the wheel.
    @State private var editing: Int?

    private var times: [Int] { AppSettings.parseQuickTimes(stored) }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(Array(times.enumerated()), id: \.offset) { index, minutes in
                    let selected = editing == index
                    Button {
                        withAnimation(.snappy) { editing = selected ? nil : index }
                    } label: {
                        Text(QuickTime(minutes: minutes).label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? Color.orange : Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            if let index = editing, index < times.count {
                IntervalDatePicker(selection: time(at: index), mode: .time, style: .wheels, minuteInterval: 5)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        } header: {
            Text("Quick Times")
        } footer: {
            Text("One-tap times under a to-do's deadline. Tap one to change it.")
        }
    }

    /// Quick time `index` as a date for the wheel. After a change the list re-sorts, so the
    /// wheel keeps following the time it's changing.
    private func time(at index: Int) -> Binding<Date> {
        Binding(
            get: {
                let minutes = times[index]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let value = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                var list = times
                list[index] = value
                let sorted = AppSettings.parseQuickTimes(AppSettings.formatQuickTimes(list))
                stored = AppSettings.formatQuickTimes(sorted)
                editing = sorted.firstIndex(of: value) ?? index
            }
        )
    }
}

// MARK: - Notes

private struct NotesSettingsSection: View {
    @State private var notes = NotesController.shared

    var body: some View {
        Section {
            Picker("Sort By", selection: Binding(get: { notes.sort }, set: { notes.setSort($0) })) {
                ForEach(NotesSort.allCases) { sort in
                    Text(sort.name).tag(sort)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Sort By")
        } footer: {
            Text("Pinned notes always stay on top.")
        }
    }
}

// MARK: - Talk

private struct TalkSettingsSection: View {
    @AppStorage(TalkSettings.wakeWordEnabledKey) private var wakeWordEnabled = false
    @AppStorage(TalkSettings.wakeWordKey) private var wakeWord = TalkSettings.defaultWakeWord
    @AppStorage(TalkSettings.speakRepliesKey) private var speakReplies = true
    @AppStorage(TalkSettings.customInstructionsKey) private var customInstructions = ""

    var body: some View {
        Section {
            Toggle("Require Wake Word", isOn: $wakeWordEnabled.animation())
            if wakeWordEnabled {
                HStack {
                    Text("Wake Word")
                    TextField(TalkSettings.defaultWakeWord, text: $wakeWord)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }
            }
        } header: {
            Text("Live Talk")
        } footer: {
            Text(wakeWordEnabled
                 ? "Only sentences that start with “\(wakeWord.isEmpty ? TalkSettings.defaultWakeWord : wakeWord)” get a reply. Say it on its own and your next sentence counts too. Typed messages always get a reply."
                 : "Live Talk replies to everything it hears.")
        }

        Section {
            Toggle("Speak Replies", isOn: $speakReplies)
        } footer: {
            Text("Reads replies aloud during Live Talk.")
        }

        Section {
            TextField("e.g. Call me Sam. Keep answers very short.", text: $customInstructions, axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text("Custom Instructions")
        } footer: {
            Text("Applied to every conversation and reply. Everything runs on your iPhone with Apple's on-device model; nothing you say is sent anywhere.")
        }

        WidgetToggles(rows: [
            ("Show Live Talk Button", AppSettings.widgetShowsTalkButtonKey),
        ], footer: "The waveform button in the corner of the medium and large Up Next widget. Without it, the widget fits one more item.")
    }
}

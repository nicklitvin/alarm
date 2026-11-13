import SwiftUI
import WidgetKit

/// Settings for one tab (mostly when to notify), plus About & Updates.
struct TabSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let tab: AppTab

    var body: some View {
        NavigationStack {
            Form {
                switch tab {
                case .alarms: AlarmSettingsSection()
                case .timers: TimerSettingsSection()
                case .todos: TodoSettingsSection()
                case .notes: NotesSettingsSection()
                case .talk: TalkSettingsSection { dismiss() }
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
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
        case .timers: "Cancels any running timers and clears your recent times."
        default: "Removes everything on this tab."
        }
    }

    private func deleteAll() {
        switch tab {
        case .alarms: AlarmController.shared.deleteAll()
        case .timers: TimerController.shared.deleteAll()
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
    @AppStorage(AppSettings.alarmTapToDismissKey, store: AppSettings.store) private var tapToDismiss = false

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

        Section {
            Toggle("Tap Notification to Dismiss", isOn: $tapToDismiss)
                .disabled(!headsUpEnabled)
        } footer: {
            Text(tapToDismiss
                 ? "Tapping the heads-up notification cancels that ring. Swiping the notification away doesn't."
                 : "Touch and hold the heads-up notification, then tap Dismiss Alarm, to cancel that ring.")
        }
        .onChange(of: tapToDismiss) { AlarmController.shared.refresh() } // updates the notification's wording

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

private struct TimerSettingsSection: View {
    var body: some View {
        Section {
            Label("Timers ring when they finish, even in Silent mode.", systemImage: "bell.badge")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
        case (true, 0): "You'll get a notification when a to-do is due. Touch and hold it to mark it done or be reminded in an hour or tomorrow."
        case (false, let m): "You'll get a reminder \(AppSettings.leadTimeName(m)) before each deadline."
        case (true, let m): "You'll get a reminder \(AppSettings.leadTimeName(m)) before each deadline, and another when it's due."
        }
    }
}

/// The three quick times shown under a deadline (8 AM, 2 PM and 9 PM by default), on one row.
/// Tap one to change it.
private struct QuickTimesSection: View {
    @AppStorage(AppSettings.todoQuickTimesKey, store: AppSettings.store) private var stored = ""
    @State private var editing: QuickTimeEdit?

    private var times: [Int] { AppSettings.parseQuickTimes(stored) }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(times, id: \.self) { minutes in
                    Button {
                        editing = QuickTimeEdit(original: minutes)
                    } label: {
                        Text(QuickTime(minutes: minutes).label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(Color.primary)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)

            if times != AppSettings.defaultTodoQuickTimes {
                Button("Reset to 8 AM, 2 PM, 9 PM") { stored = "" }
            }
        } header: {
            Text("Quick Times")
        } footer: {
            Text("One-tap times under a to-do's deadline. Tap one to change it.")
        }
        .sheet(item: $editing) { edit in
            QuickTimeEditor(edit: edit) { result in
                let list = times.map { $0 == edit.original ? result : $0 }
                stored = AppSettings.formatQuickTimes(AppSettings.parseQuickTimes(AppSettings.formatQuickTimes(list)))
            }
            .presentationDetents([.height(320)])
        }
    }
}

private struct QuickTimeEdit: Identifiable {
    /// The time being changed.
    let original: Int
    var id: Int { original }
}

/// Change one quick time.
private struct QuickTimeEditor: View {
    @Environment(\.dismiss) private var dismiss
    let edit: QuickTimeEdit
    /// The new time in minutes after midnight.
    let onDone: (Int) -> Void
    @State private var date: Date

    init(edit: QuickTimeEdit, onDone: @escaping (Int) -> Void) {
        self.edit = edit
        self.onDone = onDone
        let minutes = edit.original
        _date = State(initialValue: Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                IntervalDatePicker(selection: $date, mode: .time, style: .wheels, minuteInterval: 5)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .navigationTitle("Quick Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                        onDone((c.hour ?? 0) * 60 + (c.minute ?? 0))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(.orange)
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
            Text(notes.sort == .manual
                 ? "Press and hold a note, then drag it onto another to move it. Pinned notes always stay on top."
                 : "Pinned notes always stay on top. Press and hold a note and drag it to arrange notes yourself (switches to Manual).")
        }
    }
}

// MARK: - Talk

private struct TalkSettingsSection: View {
    @AppStorage(TalkSettings.wakeWordEnabledKey) private var wakeWordEnabled = false
    @AppStorage(TalkSettings.wakeWordKey) private var wakeWord = TalkSettings.defaultWakeWord
    @AppStorage(TalkSettings.speakRepliesKey) private var speakReplies = true
    @AppStorage(TalkSettings.customInstructionsKey) private var customInstructions = ""
    let onCleared: () -> Void

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
            Text("Applied to every conversation and reply.")
        }

        Section {
            Button(role: .destructive) {
                TalkModel.shared.clear()
                onCleared()
            } label: {
                Label("Clear Conversation", systemImage: "trash")
            }
            .foregroundStyle(.red)
        } footer: {
            Text("Everything runs on your iPhone with Apple's on-device model. Nothing you say is sent anywhere.")
        }
    }
}

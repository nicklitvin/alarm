import AVFoundation
import SwiftUI

struct AlarmEditorView: View {
    @Environment(AlarmController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    private let isNew: Bool
    @State private var draft: AlarmItem
    @State private var time: Date

    init(target: EditorTarget) {
        switch target {
        case .new:
            let start = Date().roundedToMinutes(5)
            let components = Calendar.current.dateComponents([.hour, .minute], from: start)
            isNew = true
            _draft = State(initialValue: AlarmItem(hour: components.hour ?? 7, minute: components.minute ?? 0))
            _time = State(initialValue: start)
        case .edit(let alarm):
            isNew = false
            _draft = State(initialValue: alarm)
            _time = State(initialValue: Calendar.current.date(
                bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: .now) ?? .now)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    IntervalDatePicker(selection: $time, mode: .time, style: .wheels, minuteInterval: 5)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)

                Section {
                    WeekdayPicker(selection: $draft.weekdays)
                        .padding(.vertical, 6)
                } header: {
                    Text("Repeat")
                } footer: {
                    Text(repeatFooter)
                }

                Section {
                    HStack {
                        Text("Label")
                        TextField("Alarm", text: $draft.label)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .submitLabel(.done)
                    }
                    NavigationLink {
                        AlarmSoundPicker(selection: $draft.sound)
                    } label: {
                        LabeledContent("Sound", value: draft.sound.name)
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete Alarm", role: .destructive) {
                            controller.delete(draft.id)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(isNew ? "Add Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(.orange)
    }

    private var repeatFooter: String {
        switch draft.weekdays {
        case []: "Rings once at the next \(TimeFormat.string(for: time))."
        case Set(Weekday.allCases): "Rings every day."
        case Weekday.workdays: "Rings every weekday."
        case Weekday.weekend: "Rings every weekend."
        default: "Rings every \(Weekday.localeOrdered.filter(draft.weekdays.contains).map(\.shortName).formatted(.list(type: .and)))."
        }
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        draft.hour = components.hour ?? 0
        draft.minute = components.minute ?? 0
        controller.save(draft)
        dismiss()
    }
}

/// Seven round day toggles, like S M T W T F S.
struct WeekdayPicker: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Weekday.localeOrdered) { day in
                let isOn = selection.contains(day)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if isOn { selection.remove(day) } else { selection.insert(day) }
                    }
                } label: {
                    Text(day.initial)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(isOn ? Color.orange : Color(.tertiarySystemFill)))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .sensoryFeedback(.selection, trigger: isOn)
                .accessibilityLabel(day.fullName)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Pick the sound an alarm rings with. Tapping a sound plays a few seconds of it.
struct AlarmSoundPicker: View {
    @Binding var selection: AlarmSound
    @State private var player: AVAudioPlayer?

    var body: some View {
        List {
            ForEach(AlarmSound.allCases) { sound in
                Button {
                    selection = sound
                    preview(sound)
                } label: {
                    HStack {
                        Text(sound.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection == sound {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .sensoryFeedback(.selection, trigger: selection)
            }
        }
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player?.stop() }
    }

    /// Plays the first few seconds. The system's default alarm sound can't be played by apps,
    /// so choosing Default just stops any preview.
    private func preview(_ sound: AlarmSound) {
        player?.stop()
        player = nil
        guard let file = sound.fileName,
              let url = Bundle.main.url(forResource: file, withExtension: nil) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
        self.player = player
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if self.player === player { player?.setVolume(0, fadeDuration: 0.5) }
        }
    }
}

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
            let now = Date()
            let components = Calendar.current.dateComponents([.hour, .minute], from: now)
            isNew = true
            _draft = State(initialValue: AlarmItem(hour: components.hour ?? 7, minute: components.minute ?? 0))
            _time = State(initialValue: now)
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
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
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

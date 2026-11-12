import SwiftUI

struct TodoEditorView: View {
    @Environment(TodoController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TodoItem
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var showCustom = false

    init(todo: TodoItem) {
        _draft = State(initialValue: todo)
        _hasDeadline = State(initialValue: todo.due != nil)
        _deadline = State(initialValue: todo.due ?? DueSuggestions.make().first?.date ?? Date().roundedToMinutes(5))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(.body.weight(.medium))
                    TextField("Details (optional)", text: $draft.details, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...6)
                }

                Section {
                    Toggle("Deadline", isOn: $hasDeadline.animation(.snappy))
                    if hasDeadline {
                        SuggestionChips(selection: Binding(
                            get: { deadline },
                            set: { if let date = $0 { deadline = date } }
                        )) { showCustom = true }
                        .padding(.vertical, 4)
                        HStack {
                            Text("Due")
                            Spacer()
                            IntervalDatePicker(selection: $deadline, mode: .dateAndTime, style: .compact, minuteInterval: 5)
                        }
                        TimeOfDayChips(date: $deadline)
                            .padding(.vertical, 2)
                    }
                } footer: {
                    if hasDeadline {
                        Text("You'll get a notification \(TimeFormat.dueDescription(deadline, relativeTo: .now).asDeadlinePhrase).")
                    }
                }

                // Done is an action next to Delete, not a switch.
                Section {
                    // Both actions on one line.
                    HStack(spacing: 0) {
                        Button {
                            draft.setDone(!draft.isDone)
                            save()
                        } label: {
                            Label(draft.isDone ? "Not Done" : "Mark as Done",
                                  systemImage: draft.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        Divider().frame(height: 22)
                        Button(role: .destructive) {
                            controller.delete(draft.id)
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderless) // two separate buttons in one row
                }
            }
            .navigationTitle("Edit To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showCustom) {
                DeadlinePickerSheet(date: deadline) { deadline = $0 }
                    .presentationDetents([.medium])
            }
        }
        .tint(.orange)
    }

    private func save() {
        draft.due = hasDeadline ? deadline : nil
        draft.details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        controller.update(draft)
        dismiss()
    }
}

private extension String {
    /// "5:00 PM" → "at 5:00 PM", "Tomorrow 9:00 AM" → "tomorrow at 9:00 AM",
    /// "Mon 9:00 AM" → "on Mon at 9:00 AM", "Nov 20, 9:00 AM" → "on Nov 20, 9:00 AM".
    var asDeadlinePhrase: String {
        if first?.isNumber == true { return "at \(self)" }
        if contains(",") { return "on \(self)" }
        let parts = split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return self }
        let day = ["Tomorrow", "Yesterday"].contains(parts[0]) ? parts[0].lowercased() : "on \(parts[0])"
        return "\(day) at \(parts[1])"
    }
}

import SwiftUI

/// The calendar-button sheet for a to-do: deadline and the rest. Everything saves on its own;
/// the trash icon deletes the to-do.
struct TodoEditorView: View {
    @Environment(TodoController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TodoItem
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var deleted = false

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
                        HStack {
                            Text("Due")
                            Spacer()
                            IntervalDatePicker(selection: $deadline, mode: .dateAndTime, style: .compact, minuteInterval: 5)
                                .fixedSize() // its natural size, so it isn't clipped top and bottom
                        }
                        .frame(minHeight: 44)
                        TimeOfDayChips(date: $deadline)
                            .padding(.vertical, 4)
                    }
                } footer: {
                    if hasDeadline {
                        Text("You'll get a notification \(TimeFormat.dueDescription(deadline, relativeTo: .now).asDeadlinePhrase).")
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        deleted = true
                        controller.delete(draft.id)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                    .accessibilityLabel("Delete To-Do")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            // Saves as you go: deadline changes right away, typing when the sheet closes.
            .onChange(of: hasDeadline) { save() }
            .onChange(of: deadline) { save() }
            .onDisappear { if !deleted { save() } }
        }
        .tint(.orange)
    }

    private func save() {
        var updated = draft
        let title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = title.isEmpty ? (controller.todos.first { $0.id == draft.id }?.title ?? title) : title
        updated.details = updated.details.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.due = hasDeadline ? deadline : nil
        // Keep done/undone as it is now (it may have been toggled elsewhere).
        if let current = controller.todos.first(where: { $0.id == draft.id }) {
            updated.isDone = current.isDone
            updated.completedAt = current.completedAt
        }
        controller.update(updated)
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

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
        _deadline = State(initialValue: todo.due ?? DueSuggestions.make().first?.date ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(.body.weight(.medium))
                    Toggle("Done", isOn: Binding(
                        get: { draft.isDone },
                        set: { draft.setDone($0) }
                    ))
                }

                Section {
                    Toggle("Deadline", isOn: $hasDeadline.animation(.snappy))
                    if hasDeadline {
                        SuggestionChips(selection: Binding(
                            get: { deadline },
                            set: { if let date = $0 { deadline = date } }
                        )) { showCustom = true }
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 0))
                        DatePicker("Time", selection: $deadline, displayedComponents: .hourAndMinute)
                        DatePicker("Date", selection: $deadline, displayedComponents: .date)
                    }
                } footer: {
                    if hasDeadline {
                        Text("You'll get a notification \(TimeFormat.dueDescription(deadline, relativeTo: .now).lowercasedFirstIfRelative).")
                    }
                }

                Section {
                    Button("Delete To-Do", role: .destructive) {
                        controller.delete(draft.id)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
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
        controller.update(draft)
        dismiss()
    }
}

private extension String {
    /// "at 5:00 PM" style phrasing: "Tomorrow 9:00 AM" → "tomorrow at 9:00 AM", "5:00 PM" → "at 5:00 PM".
    var lowercasedFirstIfRelative: String {
        if first?.isNumber == true { return "at \(self)" }
        if contains(",") { return "on \(self)" }
        let parts = split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return self }
        let day = ["Tomorrow", "Yesterday"].contains(parts[0]) ? parts[0].lowercased() : "on \(parts[0])"
        return "\(day) at \(parts[1])"
    }
}

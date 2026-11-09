import SwiftUI

struct TodoListView: View {
    @Environment(TodoController.self) private var controller
    @State private var editing: TodoItem?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                list(now: context.date)
            }
            .navigationTitle("To-Do")
            .sheet(item: $editing) { todo in
                TodoEditorView(todo: todo)
            }
        }
        .tint(.orange)
    }

    private func list(now: Date) -> some View {
        List {
            Section {
                QuickAddRow()
            }

            ForEach(groups(now: now), id: \.title) { group in
                Section {
                    ForEach(group.items) { todo in
                        row(todo, now: now)
                    }
                } header: {
                    Text(group.title)
                        .foregroundStyle(group.isOverdue ? Color.red : Color.secondary)
                }
            }

            if !controller.completedTodos.isEmpty {
                Section {
                    ForEach(controller.completedTodos) { todo in
                        row(todo, now: now)
                    }
                } header: {
                    HStack {
                        Text("Completed")
                        Spacer()
                        Button("Clear") { withAnimation { controller.clearCompleted() } }
                            .font(.footnote.weight(.semibold))
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if controller.todos.isEmpty {
                ContentUnavailableView {
                    Label("Nothing To Do", systemImage: "checklist")
                } description: {
                    Text("Add a to-do above, or ask in Talk: “remind me to call mom at 6”.")
                }
                .padding(.top, 120)
                .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: controller.todos)
    }

    private func row(_ todo: TodoItem, now: Date) -> some View {
        TodoRow(todo: todo, now: now)
            .contentShape(Rectangle())
            .onTapGesture { editing = todo }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) { controller.delete(todo.id) }
            }
            .swipeActions(edge: .leading) {
                Button(todo.isDone ? "Undo" : "Done", systemImage: todo.isDone ? "arrow.uturn.backward" : "checkmark") {
                    Task { await controller.toggle(todo.id) }
                }
                .tint(.orange)
            }
    }

    private struct TodoGroup {
        let title: String
        let items: [TodoItem]
        var isOverdue = false
    }

    private func groups(now: Date) -> [TodoGroup] {
        let calendar = Calendar.current
        let open = controller.openTodos
        let overdue = open.filter { $0.isOverdue(at: now) }
        let upcoming = open.filter { !$0.isOverdue(at: now) }
        let today = upcoming.filter { $0.due.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        let tomorrow = upcoming.filter { $0.due.map { calendar.isDateInTomorrow($0) } ?? false }
        let later = upcoming.filter { todo in
            guard let due = todo.due else { return false }
            return !calendar.isDate(due, inSameDayAs: now) && !calendar.isDateInTomorrow(due)
        }
        let someday = upcoming.filter { $0.due == nil }

        return [
            TodoGroup(title: "Overdue", items: overdue, isOverdue: true),
            TodoGroup(title: "Today", items: today),
            TodoGroup(title: "Tomorrow", items: tomorrow),
            TodoGroup(title: "Later", items: later),
            TodoGroup(title: "No Deadline", items: someday),
        ].filter { !$0.items.isEmpty }
    }
}

// MARK: - Row

private struct TodoRow: View {
    @Environment(TodoController.self) private var controller
    let todo: TodoItem
    let now: Date

    var body: some View {
        let overdue = todo.isOverdue(at: now)
        HStack(spacing: 12) {
            Button {
                Task { await controller.toggle(todo.id) }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.isDone ? Color.orange : (overdue ? Color.red : Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: todo.isDone) { _, done in done }
            .accessibilityLabel(todo.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                if let due = todo.due, !todo.isDone {
                    Label(TimeFormat.dueDescription(due, relativeTo: now), systemImage: overdue ? "exclamationmark.circle.fill" : "clock")
                        .font(.caption)
                        .foregroundStyle(overdue ? Color.red : Color.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Quick add

/// Type a title, optionally tap a suggested time, and add.
private struct QuickAddRow: View {
    @Environment(TodoController.self) private var controller
    @FocusState private var focused: Bool
    @State private var title = ""
    @State private var due: Date?
    @State private var showCustom = false

    private var isActive: Bool { focused || !title.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                TextField("New To-Do", text: $title)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                if !title.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: add)
                        .fontWeight(.semibold)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            if isActive {
                SuggestionChips(selection: $due) { showCustom = true }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.snappy, value: isActive)
        .animation(.snappy, value: title.isEmpty)
        .sheet(isPresented: $showCustom) {
            DeadlinePickerSheet(date: due ?? DueSuggestions.make().first?.date ?? .now) { picked in
                due = picked
            }
            .presentationDetents([.medium])
        }
    }

    private func add() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { focused = false; return }
        controller.add(title: text, due: due)
        title = ""
        due = nil
    }
}

// MARK: - Suggested times

/// Horizontal chips: suggested deadlines plus "Custom…". Tapping a selected chip clears it.
struct SuggestionChips: View {
    @Binding var selection: Date?
    var onCustom: () -> Void

    var body: some View {
        let now = Date()
        let suggestions = DueSuggestions.make(now: now)
        let isCustom = selection.map { picked in !suggestions.contains { $0.date == picked } } ?? false

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    let selected = selection == suggestion.date
                    Button {
                        selection = selected ? nil : suggestion.date
                    } label: {
                        chip(title: suggestion.title,
                             subtitle: TimeFormat.dueDescription(suggestion.date, relativeTo: now),
                             selected: selected)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onCustom) {
                    chip(title: isCustom ? "Custom" : "Custom…",
                         subtitle: isCustom ? selection.map { TimeFormat.dueDescription($0, relativeTo: now) } ?? "" : "Pick a time",
                         selected: isCustom,
                         systemImage: "calendar")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func chip(title: String, subtitle: String, selected: Bool, systemImage: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)) }
                Text(title).font(.footnote.weight(.semibold))
            }
            Text(subtitle)
                .font(.caption2)
                .opacity(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.orange : Color(.tertiarySystemFill))
        )
    }
}

/// Time first (that's what matters most), date underneath.
struct DeadlinePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var date: Date
    let onPick: (Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                DatePicker("Date", selection: $date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
            }
            .navigationTitle("Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        onPick(date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(.orange)
    }
}

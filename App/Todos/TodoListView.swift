import SwiftUI

struct TodoListView: View {
    @Environment(TodoController.self) private var controller
    @State private var editing: TodoItem?
    @State private var composing = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                list(now: context.date)
            }
            .navigationTitle("To-Do")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                TabHeader(title: "To-Do", tab: .todos) { now in
                    let open = controller.openTodos
                    let overdue = open.filter { $0.isOverdue(at: now) }.count
                    if open.isEmpty { return nil }
                    return overdue > 0 ? "\(overdue) overdue · \(open.count) left" : "\(open.count) left"
                }
            }
            .safeAreaInset(edge: .bottom) {
                if composing {
                    TodoComposer { composing = false }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    BottomActionButton(title: "New To-Do", systemImage: "plus") { composing = true }
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: composing)
            .sheet(item: $editing) { todo in
                TodoEditorView(todo: todo)
            }
            .task(id: AppNavigation.shared.pendingTodoID) {
                // Opened from a chat event: show that to-do.
                guard let id = AppNavigation.shared.pendingTodoID else { return }
                AppNavigation.shared.pendingTodoID = nil
                if let todo = controller.todos.first(where: { $0.id == id }) { editing = todo }
            }
        }
        .tint(.orange)
    }

    private func list(now: Date) -> some View {
        List {
            ForEach(groups(now: now), id: \.title) { group in
                Section {
                    ForEach(group.items) { todo in
                        row(todo, now: now)
                    }
                } header: {
                    if !group.title.isEmpty {
                        Text(group.title)
                            .foregroundStyle(group.isOverdue ? Color.red : Color.secondary)
                    }
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
            if controller.todos.isEmpty && !composing {
                ContentUnavailableView {
                    Label("Nothing To Do", systemImage: "checklist")
                } description: {
                    Text("Tap New To-Do below, or ask in Talk: “remind me to call mom at 6”.")
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: controller.todos)
    }

    private func row(_ todo: TodoItem, now: Date) -> some View {
        TodoRow(todo: todo, now: now) { editing = todo }
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
            TodoGroup(title: "", items: someday), // no heading: no deadline needs no label
        ].filter { !$0.items.isEmpty }
    }
}

// MARK: - Row

/// A to-do you edit right in the list, like Reminders: tap the title to type, the details line
/// sits underneath, and while editing a calendar button opens the deadline settings.
private struct TodoRow: View {
    @Environment(TodoController.self) private var controller
    let todo: TodoItem
    let now: Date
    let onShowDetails: () -> Void

    @State private var title: String
    @State private var details: String
    @FocusState private var focus: Field?

    private enum Field { case title, details }

    init(todo: TodoItem, now: Date, onShowDetails: @escaping () -> Void) {
        self.todo = todo
        self.now = now
        self.onShowDetails = onShowDetails
        _title = State(initialValue: todo.title)
        _details = State(initialValue: todo.details)
    }

    private var isEditing: Bool { focus != nil }

    var body: some View {
        let overdue = todo.isOverdue(at: now)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                Task { await controller.toggle(todo.id) }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.isDone ? Color.orange : (overdue ? Color.red : Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
            .sensoryFeedback(.success, trigger: todo.isDone) { _, done in done }
            .accessibilityLabel(todo.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                TextField("To-Do", text: $title, axis: .vertical)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }

                if isEditing || !todo.trimmedDetails.isEmpty {
                    TextField("Add details", text: $details, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...4)
                        .focused($focus, equals: .details)
                }

                if let due = todo.due, !todo.isDone {
                    Button(action: onShowDetails) {
                        // Icon right next to the time (a Label leaves a wide gap).
                        HStack(spacing: 3) {
                            Image(systemName: overdue ? "exclamationmark.circle.fill" : "clock")
                            Text(TimeFormat.dueDescription(due, relativeTo: now))
                        }
                        .font(.caption)
                        .foregroundStyle(overdue ? Color.red : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Spacer(minLength: 0)

            if isEditing {
                Button {
                    commit()
                    focus = nil
                    onShowDetails()
                } label: {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Deadline and more")
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .animation(.snappy, value: isEditing)
        .onChange(of: focus) { _, newFocus in
            if newFocus == nil { commit() }
        }
        .onChange(of: todo) { _, updated in
            // Changes from elsewhere (widget, assistant, the details sheet) while not typing here.
            if !isEditing {
                title = updated.title
                details = updated.details
            }
        }
    }

    /// Saves typed changes. An emptied title puts the old one back.
    private func commit() {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else {
            title = todo.title
            return
        }
        guard newTitle != todo.title || newDetails != todo.trimmedDetails else { return }
        var updated = todo
        updated.title = newTitle
        updated.details = newDetails
        controller.update(updated)
    }
}

// MARK: - Composer (bottom, within thumb reach)

private struct TodoComposer: View {
    @Environment(TodoController.self) private var controller
    @FocusState private var focus: Field?
    @State private var title = ""
    @State private var details = ""
    @State private var due: Date?
    @State private var showCustom = false
    let onClose: () -> Void

    private enum Field { case title, details }

    private var canAdd: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SuggestionChips(selection: $due) { showCustom = true }

            VStack(alignment: .leading, spacing: 6) {
                TextField("New To-Do", text: $title)
                    .font(.body.weight(.medium))
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .onSubmit(add)
                TextField("Details (optional)", text: $details, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...3)
                    .focused($focus, equals: .details)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 10) {
                Button("Cancel") {
                    focus = nil
                    onClose()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Color.secondary)

                Button(action: add) {
                    Label(due.map { "Add · \(TimeFormat.dueDescription($0, relativeTo: .now))" } ?? "Add", systemImage: "plus")
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(!canAdd)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.bar)
        .onAppear { focus = .title }
        .sheet(isPresented: $showCustom) {
            DeadlinePickerSheet(date: due ?? DueSuggestions.make().first?.date ?? Date().roundedToMinutes(5)) { picked in
                due = picked
            }
            .presentationDetents([.medium])
        }
    }

    /// Adds the to-do and closes the panel.
    private func add() {
        guard canAdd else { return }
        controller.add(title: title, details: details, due: due)
        focus = nil
        onClose()
    }
}

// MARK: - Suggested times

/// Suggested deadlines plus "Custom…", laid out in a grid (no sideways scrolling).
/// Tapping a selected suggestion clears it.
struct SuggestionChips: View {
    @Binding var selection: Date?
    var onCustom: () -> Void

    var body: some View {
        let now = Date()
        let suggestions = DueSuggestions.make(now: now)
        let isCustom = selection.map { picked in !suggestions.contains { $0.date == picked } } ?? false

        // Two columns so titles like "Tomorrow morning" are never cut off.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(suggestions) { suggestion in
                let selected = selection == suggestion.date
                Button {
                    selection = selected ? nil : suggestion.date
                } label: {
                    chip(title: suggestion.title,
                         subtitle: Self.subtitle(for: suggestion, now: now),
                         selected: selected)
                }
                .buttonStyle(.plain)
            }
            Button(action: onCustom) {
                chip(title: "Custom",
                     subtitle: isCustom ? selection.map { TimeFormat.dueDescription($0, relativeTo: now) } ?? "" : "Pick a time",
                     selected: isCustom,
                     systemImage: "calendar")
            }
            .buttonStyle(.plain)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// The time under a suggestion, without repeating the day its title already says
    /// ("Tomorrow morning" → "9:00 AM", "This weekend" → "Sat 10:00 AM").
    private static func subtitle(for suggestion: DueSuggestions.Suggestion, now: Date) -> String {
        let impliesDay = ["Tomorrow", "Tonight", "This afternoon", "This evening", "In "].contains { suggestion.title.hasPrefix($0) }
        return impliesDay ? TimeFormat.string(for: suggestion.date) : TimeFormat.dueDescription(suggestion.date, relativeTo: now)
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
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.orange : Color(.tertiarySystemFill))
        )
    }
}

/// Time first (in 5-minute steps), date underneath.
struct DeadlinePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var date: Date
    let onPick: (Date) -> Void

    init(date: Date, onPick: @escaping (Date) -> Void) {
        _date = State(initialValue: date.roundedToMinutes(5))
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            Form {
                TimeOfDayChips(date: $date)
                IntervalDatePicker(selection: $date, mode: .time, style: .wheels, minuteInterval: 5)
                    .frame(maxWidth: .infinity)
                HStack {
                    Text("Date")
                    Spacer()
                    IntervalDatePicker(selection: $date, mode: .date, style: .compact,
                                       minimumDate: Calendar.current.startOfDay(for: .now))
                }
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

/// Morning · Noon · Afternoon · Evening · Night — one tap sets the deadline's time.
struct TimeOfDayChips: View {
    @Binding var date: Date

    var body: some View {
        let selected = TimeOfDay.matching(date)
        HStack(spacing: 6) {
            ForEach(TimeOfDay.allCases) { option in
                let isSelected = option == selected
                Button {
                    date = option.apply(to: date)
                } label: {
                    VStack(spacing: 1) {
                        Text(option.title)
                            .font(.caption.weight(.semibold))
                        Text(Self.shortTime(option.hour))
                            .font(.caption2)
                            .opacity(0.8)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.orange : Color(.tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.title), \(TimeFormat.string(hour: option.hour, minute: 0))")
            }
        }
        .sensoryFeedback(.selection, trigger: date)
    }

    /// "9 AM" / "21:00".
    private static func shortTime(_ hour: Int) -> String {
        let parts = TimeFormat.parts(hour: hour, minute: 0)
        guard let period = parts.period else { return parts.time }
        return "\(parts.time.replacingOccurrences(of: ":00", with: "")) \(period)"
    }
}

import SwiftUI

/// Which text field is being typed in. One focus for the whole list, so tapping off or pressing
/// Return ends editing everywhere.
enum TodoField: Hashable {
    case title(UUID), details(UUID)
    case newTitle, newDetails

    var todoID: UUID? {
        switch self {
        case .title(let id), .details(let id): id
        case .newTitle, .newDetails: nil
        }
    }
}

struct TodoListView: View {
    @Environment(TodoController.self) private var controller
    @State private var editing: TodoItem?
    /// True while a new, not yet saved to-do is being typed at the end of the list.
    @State private var addingNew = false
    @FocusState private var focus: TodoField?

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
                if focus == nil {
                    // Like Reminders: adds an empty row at the end of the list, ready to type.
                    BottomActionButton(title: "New To-Do", systemImage: "plus", action: startNew)
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: focus == nil)
            .sheet(item: $editing) { todo in
                TodoEditorView(todo: todo)
            }
            .task(id: AppNavigation.shared.pendingTodoID) {
                // Opened from a widget, notification or chat event: show that to-do.
                guard let id = AppNavigation.shared.pendingTodoID else { return }
                AppNavigation.shared.pendingTodoID = nil
                focus = nil
                if let todo = controller.todos.first(where: { $0.id == id }) { editing = todo }
            }
        }
        .tint(.orange)
    }

    private func startNew() {
        addingNew = true
        focus = .newTitle
    }

    private func list(now: Date) -> some View {
        ScrollViewReader { proxy in
            List {
                // Open to-dos: soonest deadline first, then the ones without a deadline. No sections.
                ForEach(controller.openTodos) { todo in
                    row(todo, now: now)
                }

                if addingNew {
                    NewTodoRow(focus: $focus) { addingNew = false }
                        .id("new")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if !controller.completedTodos.isEmpty {
                    Section {
                        ForEach(controller.completedTodos) { todo in
                            row(todo, now: now, compact: true)
                        }
                    } header: {
                        HStack {
                            Text("Completed")
                            Spacer()
                            Button("Clear") { withAnimation { controller.clearCompleted() } }
                                .font(.footnote.weight(.semibold))
                                .textCase(nil)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                    }
                }

                // Empty space below the rows: tapping it stops editing.
                Color.clear
                    .frame(height: 240)
                    .contentShape(Rectangle())
                    .onTapGesture { focus = nil }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .environment(\.defaultMinListRowHeight, 0)
            .scrollDismissesKeyboard(.immediately)
            .overlay {
                if controller.todos.isEmpty && !addingNew {
                    ContentUnavailableView {
                        Label("Nothing To Do", systemImage: "checklist")
                    } description: {
                        Text("Tap New To-Do below, or ask in Talk: “remind me to call mom at 6”.")
                    }
                    .allowsHitTesting(false)
                }
            }
            .animation(.snappy, value: controller.todos)
            .onChange(of: addingNew) { _, adding in
                if adding { withAnimation { proxy.scrollTo("new", anchor: .bottom) } }
            }
        }
    }

    private func row(_ todo: TodoItem, now: Date, compact: Bool = false) -> some View {
        TodoRow(todo: todo, now: now, compact: compact, focus: $focus) {
            focus = nil
            editing = todo
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: compact ? 4 : 7, leading: 20, bottom: compact ? 4 : 7, trailing: 16))
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
}

// MARK: - Row

/// A to-do you edit right in the list, like Reminders: a checkbox and its text. Tap the text to
/// type; Return or tapping elsewhere finishes. While editing, the calendar button opens the
/// deadline and details.
private struct TodoRow: View {
    @Environment(TodoController.self) private var controller
    let todo: TodoItem
    let now: Date
    let compact: Bool
    var focus: FocusState<TodoField?>.Binding
    let onShowDetails: () -> Void

    @State private var title: String
    @State private var details: String

    init(todo: TodoItem, now: Date, compact: Bool, focus: FocusState<TodoField?>.Binding, onShowDetails: @escaping () -> Void) {
        self.todo = todo
        self.now = now
        self.compact = compact
        self.focus = focus
        self.onShowDetails = onShowDetails
        _title = State(initialValue: todo.title)
        _details = State(initialValue: todo.details)
    }

    private var isEditing: Bool { focus.wrappedValue?.todoID == todo.id }

    var body: some View {
        let overdue = todo.isOverdue(at: now)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                Task { await controller.toggle(todo.id) }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(compact ? .body : .title2)
                    .foregroundStyle(todo.isDone ? Color.orange : (overdue ? Color.red : Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - (compact ? 3 : 5) }
            .sensoryFeedback(.success, trigger: todo.isDone) { _, done in done }
            .accessibilityLabel(todo.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                TextField("To-Do", text: $title, axis: .vertical)
                    .font(compact ? .subheadline : .body)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                    .focused(focus, equals: .title(todo.id))
                    .submitLabel(.done)
                    // A multi-line field types a newline on Return: treat it as "done" instead.
                    .onChange(of: title) { _, text in
                        if text.contains("\n") {
                            title = text.replacingOccurrences(of: "\n", with: "")
                            focus.wrappedValue = nil
                        }
                    }

                if isEditing || !todo.trimmedDetails.isEmpty {
                    TextField("Add details", text: $details, axis: .vertical)
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...4)
                        .focused(focus, equals: .details(todo.id))
                        .submitLabel(.done)
                        .onChange(of: details) { _, text in
                            if text.contains("\n") {
                                details = text.replacingOccurrences(of: "\n", with: "")
                                focus.wrappedValue = nil
                            }
                        }
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
        .animation(.snappy, value: isEditing)
        .onChange(of: focus.wrappedValue) { old, new in
            // Left this row's fields: save.
            if old?.todoID == todo.id, new?.todoID != todo.id { commit() }
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

// MARK: - New to-do

/// The empty row "New To-Do" adds at the end of the list. It's saved once you finish typing
/// (Return or tapping elsewhere); left empty, it simply goes away.
private struct NewTodoRow: View {
    @Environment(TodoController.self) private var controller
    var focus: FocusState<TodoField?>.Binding
    let onFinish: () -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var due: Date?
    @State private var pickingDeadline = false

    private var isEditing: Bool { focus.wrappedValue == .newTitle || focus.wrappedValue == .newDetails }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "circle")
                .font(.title2)
                .foregroundStyle(.tertiary)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }

            VStack(alignment: .leading, spacing: 2) {
                TextField("New To-Do", text: $title, axis: .vertical)
                    .focused(focus, equals: .newTitle)
                    .submitLabel(.done)
                    .onChange(of: title) { _, text in
                        if text.contains("\n") {
                            title = text.replacingOccurrences(of: "\n", with: "")
                            focus.wrappedValue = nil
                        }
                    }
                TextField("Add details", text: $details, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...4)
                    .focused(focus, equals: .newDetails)
                    .onChange(of: details) { _, text in
                        if text.contains("\n") {
                            details = text.replacingOccurrences(of: "\n", with: "")
                            focus.wrappedValue = nil
                        }
                    }
                if let due {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                        Text(TimeFormat.dueDescription(due, relativeTo: .now))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                pickingDeadline = true
            } label: {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Deadline")
        }
        .padding(.vertical, 7)
        .padding(.leading, 4)
        .onChange(of: focus.wrappedValue) { _, new in
            // Finished typing (and not just picking a deadline): save or discard.
            if new != .newTitle, new != .newDetails, !pickingDeadline { finish() }
        }
        .sheet(isPresented: $pickingDeadline, onDismiss: { focus.wrappedValue = .newTitle }) {
            DeadlineSheet(date: due ?? QuickTime.nextDefault()) { picked in due = picked }
                .presentationDetents([.medium, .large])
        }
    }

    private func finish() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            controller.add(title: text, details: details, due: due)
        }
        onFinish()
    }
}

// MARK: - Deadline

/// Deadline for a new to-do: your quick times, a custom time (5-minute steps) and the date.
struct DeadlineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    let onPick: (Date?) -> Void

    init(date: Date, onPick: @escaping (Date?) -> Void) {
        _date = State(initialValue: date.roundedToMinutes(5))
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TimeOfDayChips(date: $date)
                        .padding(.vertical, 4)
                    DeadlineDateTimeRows(date: $date)
                }
                Section {
                    Button("No Deadline", role: .destructive) {
                        onPick(nil)
                        dismiss()
                    }
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

/// "Date" and "Time" rows with the system's compact pickers (time in 5-minute steps).
struct DeadlineDateTimeRows: View {
    @Binding var date: Date

    var body: some View {
        HStack {
            Text("Date")
            Spacer()
            IntervalDatePicker(selection: $date, mode: .date, style: .compact,
                               minimumDate: Calendar.current.startOfDay(for: .now))
        }
        HStack {
            Text("Time")
            Spacer()
            IntervalDatePicker(selection: $date, mode: .time, style: .compact, minuteInterval: 5)
        }
    }
}

/// The quick times from To-Do settings (9 AM · 3 PM · 9 PM by default): one tap sets the deadline's time.
struct TimeOfDayChips: View {
    @Binding var date: Date
    @AppStorage(AppSettings.todoQuickTimesKey, store: AppSettings.store) private var stored = ""

    var body: some View {
        let options = AppSettings.parseQuickTimes(stored).map(QuickTime.init(minutes:))
        let selected = QuickTime.matching(date, in: options)
        HStack(spacing: 6) {
            ForEach(options) { option in
                let isSelected = option == selected
                Button {
                    date = option.apply(to: date)
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.orange : Color(.tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TimeFormat.string(hour: option.hour, minute: option.minute))
            }
        }
        .sensoryFeedback(.selection, trigger: date)
    }
}

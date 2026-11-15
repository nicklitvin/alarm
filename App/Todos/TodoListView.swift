import SwiftUI

/// Which text field is being typed in. One focus for the whole list, so tapping off or pressing
/// Return ends editing everywhere.
enum TodoField: Hashable {
    case title(UUID), details(UUID)

    var todoID: UUID? {
        switch self {
        case .title(let id), .details(let id): id
        }
    }
}

struct TodoListView: View {
    @Environment(TodoController.self) private var controller
    @State private var editing: TodoItem?
    /// The to-do whose time was tapped: a small sheet with just the deadline.
    @State private var editingDue: TodoItem?
    /// The Add To-Do sheet, like Add Alarm and New Timer.
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
                    BottomActionButton(title: "New To-Do", systemImage: "plus") { addingNew = true }
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: focus == nil)
            .sheet(item: $editing) { todo in
                TodoEditorView(todo: todo)
            }
            .sheet(item: $editingDue) { todo in
                DueSheet(todo: todo)
                    .presentationDetents([.height(290)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $addingNew) {
                NewTodoSheet()
            }
            // A widget tap or notification closes these sheets (unless it opens a to-do itself).
            .onChange(of: AppNavigation.shared.linkOpenCount) {
                addingNew = false
                editingDue = nil
                if AppNavigation.shared.pendingTodoID == nil { editing = nil }
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

    private func list(now: Date) -> some View {
        ScrollViewReader { _ in
            List {
                // Open to-dos in your order: press and hold one, then drag it. New ones slot in by
                // deadline. No sections.
                ForEach(controller.openTodos) { todo in
                    row(todo, now: now)
                }
                .onMove { source, destination in
                    controller.moveOpen(from: source, to: destination)
                }

                if !controller.completedTodos.isEmpty {
                    Section {
                        ForEach(controller.completedTodos) { todo in
                            row(todo, now: now)  // same size as open to-dos
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
                if controller.todos.isEmpty {
                    ContentUnavailableView("Nothing To Do", systemImage: "checklist")
                    .allowsHitTesting(false)
                }
            }
            .animation(.snappy, value: controller.todos)
        }
    }

    private func row(_ todo: TodoItem, now: Date) -> some View {
        TodoRow(todo: todo, now: now, focus: $focus, onShowDue: {
            focus = nil
            editingDue = todo
        }) {
            focus = nil
            editing = todo
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 7, leading: 20, bottom: 7, trailing: 16))
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
    var focus: FocusState<TodoField?>.Binding
    let onShowDue: () -> Void
    let onShowDetails: () -> Void

    @State private var title: String
    @State private var details: String

    init(todo: TodoItem, now: Date, focus: FocusState<TodoField?>.Binding,
         onShowDue: @escaping () -> Void, onShowDetails: @escaping () -> Void) {
        self.onShowDue = onShowDue
        self.todo = todo
        self.now = now
        self.focus = focus
        self.onShowDetails = onShowDetails
        _title = State(initialValue: todo.title)
        _details = State(initialValue: todo.details)
    }

    private var isEditing: Bool { focus.wrappedValue?.todoID == todo.id }

    var body: some View {
        let overdue = todo.isOverdue(at: now)
        // The circle is centered on the title's first line: both are top-aligned in boxes of
        // known height (the circle's box is the first line's height plus a little).
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await controller.toggle(todo.id) }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.isDone ? Color.orange : (overdue ? Color.red : Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.success, trigger: todo.isDone) { _, done in done }
            .accessibilityLabel(todo.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                TextField("To-Do", text: $title, axis: .vertical)
                    .font(.body)
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
                        .font(.subheadline)
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
                    // Tapping the time opens just the deadline, in a small sheet.
                    Button(action: onShowDue) {
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
            .padding(.top, 3) // first line (22 pt) centered on the circle (28 pt)

            Spacer(minLength: 0)

            if isEditing {
                Button {
                    commit()
                    onShowDetails()
                } label: {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(height: 28) // level with the circle and the first line
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

/// "New To-Do": a sheet like Add Alarm and New Timer, with the big Add button at the bottom.
/// Swipe down to cancel.
private struct NewTodoSheet: View {
    @Environment(TodoController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var hasDeadline = false
    @State private var deadline = QuickTime.nextDefault().roundedToMinutes(5)
    @FocusState private var titleFocused: Bool

    private var canAdd: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.body.weight(.medium))
                        .focused($titleFocused)
                        .submitLabel(.done)
                    TextField("Details (optional)", text: $details, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...4)
                }

                Section {
                    Toggle("Deadline", isOn: $hasDeadline.animation(.snappy))
                    if hasDeadline {
                        TimeOfDayChips(date: $deadline)
                            .padding(.vertical, 4)
                        DeadlineDateTimeRows(date: $deadline)
                    }
                } footer: {
                    if hasDeadline {
                        Text("You'll get a notification when it's due.")
                    }
                }
            }
            .navigationTitle("New To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                BottomActionButton(title: "Add To-Do", systemImage: "plus", action: add)
                    .disabled(!canAdd)
            }
            .onAppear { titleFocused = true }
        }
        .tint(.orange)
    }

    private func add() {
        guard canAdd else { return }
        controller.add(title: title, details: details, due: hasDeadline ? deadline : nil)
        dismiss()
    }
}

/// The small sheet from tapping a to-do's time: quick times, date and time, nothing else.
/// Saves as you change it; swipe down to close.
struct DueSheet: View {
    @Environment(TodoController.self) private var controller
    let todo: TodoItem
    @State private var date: Date

    init(todo: TodoItem) {
        self.todo = todo
        _date = State(initialValue: (todo.due ?? QuickTime.nextDefault()).roundedToMinutes(5))
    }

    var body: some View {
        Form {
            Section {
                TimeOfDayChips(date: $date)
                    .padding(.vertical, 4)
                DeadlineDateTimeRows(date: $date)
            }
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .tint(.orange)
        .onChange(of: date) { _, newDate in
            guard var current = controller.todos.first(where: { $0.id == todo.id }) else { return }
            current.due = newDate
            controller.update(current)
        }
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

/// The quick times from To-Do settings (8 AM · 2 PM · 9 PM by default): one tap sets the deadline's time.
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

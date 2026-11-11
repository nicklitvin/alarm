import SwiftUI
import UIKit

enum EditorTarget: Identifiable {
    case new
    case edit(AlarmItem)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let alarm): alarm.id.uuidString
        }
    }
}

struct AlarmListView: View {
    @Environment(AlarmController.self) private var controller
    @Environment(\.scenePhase) private var scenePhase
    @State private var editorTarget: EditorTarget?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .navigationTitle("Alarms")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                TabHeader(title: "Alarms", tab: .alarms) { now in
                    controller.nextFire(now: now).map { "Next in \(TimeFormat.countdown(from: now, to: $0.date))" }
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionButton(title: "New Alarm", systemImage: "plus") { editorTarget = .new }
            }
            .task(id: AppNavigation.shared.pendingAlarmID) {
                // Opened from a chat event: show that alarm.
                guard let id = AppNavigation.shared.pendingAlarmID else { return }
                AppNavigation.shared.pendingAlarmID = nil
                if let alarm = controller.alarms.first(where: { $0.id == id }) {
                    editorTarget = .edit(alarm)
                }
            }
            .sheet(item: $editorTarget) { target in
                AlarmEditorView(target: target)
            }
        }
        .tint(.orange)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.refresh() }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if controller.alarms.isEmpty {
            ContentUnavailableView {
                Label("No Alarms", systemImage: "alarm")
            } description: {
                Text("Tap New Alarm below to set your first one.")
            }
        } else {
            List {
                if !controller.isAuthorized {
                    Section { PermissionBanner() }
                }
                if !controller.notificationsAllowed {
                    Section {
                        PermissionBanner(
                            title: "Notifications Are Off",
                            message: "Turn on notifications for Alarm in Settings to get the heads-up an hour before each alarm."
                        )
                    }
                }

                let soon = controller.soonAlarms(now: now)
                if !soon.isEmpty {
                    Section {
                        ForEach(soon) { item in
                            SoonAlarmCard(item: item, now: now)
                        }
                    }
                }

                Section {
                    ForEach(controller.sortedAlarms) { alarm in
                        AlarmRow(alarm: alarm, now: now)
                            .contentShape(Rectangle())
                            .onTapGesture { editorTarget = .edit(alarm) }
                    }
                    .onDelete { offsets in
                        let sorted = controller.sortedAlarms
                        offsets.map { sorted[$0].id }.forEach(controller.delete)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.default, value: controller.alarms)
        }
    }
}

// MARK: - Rows

private struct AlarmRow: View {
    @Environment(AlarmController.self) private var controller
    let alarm: AlarmItem
    let now: Date

    var body: some View {
        let parts = TimeFormat.parts(hour: alarm.hour, minute: alarm.minute)

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.time)
                        .font(.system(size: 52, weight: .light))
                        .monospacedDigit()
                    if let period = parts.period {
                        Text(period)
                            .font(.system(size: 24, weight: .regular))
                    }
                }
                .foregroundStyle(alarm.isEnabled ? .primary : .secondary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let skipped = alarm.skippedOccurrence, skipped > now {
                    Label("Skipping \(TimeFormat.dayDescription(for: skipped, relativeTo: now).lowercasedIfRelative)",
                          systemImage: "bell.slash.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            Toggle("Enabled", isOn: Binding(
                get: { alarm.isEnabled },
                set: { controller.setEnabled($0, for: alarm.id) }
            ))
            .labelsHidden()
            .tint(.green)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !alarm.label.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(alarm.title) }
        if alarm.isRepeating {
            parts.append(alarm.repeatSummary)
        } else if alarm.isEnabled, let date = alarm.oneTimeDate {
            parts.append(TimeFormat.dayDescription(for: date, relativeTo: now))
        } else if parts.isEmpty {
            parts.append("Alarm")
        }
        return parts.joined(separator: ", ")
    }
}

private extension String {
    /// "Skipping today" / "Skipping tomorrow" read better lowercased; weekday names stay capitalized.
    var lowercasedIfRelative: String {
        (self == "Today" || self == "Tomorrow") ? lowercased() : self
    }
}

// MARK: - Dismiss card

/// Shown for alarms that will ring within the hour, with a button to dismiss that ring.
private struct SoonAlarmCard: View {
    @Environment(AlarmController.self) private var controller
    let item: SoonAlarm
    let now: Date
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.isDismissed ? "bell.slash.fill" : "alarm.waves.left.and.right.fill")
                .font(.title3)
                .foregroundStyle(item.isDismissed ? Color.secondary : Color.orange)
                .frame(width: 44, height: 44)
                .background(Circle().fill(item.isDismissed ? Color(.tertiarySystemFill) : Color.orange.opacity(0.15)))
                .symbolEffect(.pulse, isActive: !item.isDismissed)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.isDismissed ? "Dismissed" : item.alarm.title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .strikethrough(item.isDismissed)
            }

            Spacer(minLength: 0)

            if item.isDismissed {
                Button("Undo") { controller.undoDismiss(of: item.alarm.id) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color.secondary)
            } else {
                Button {
                    isWorking = true
                    Task {
                        await controller.dismissNextRing(of: item.alarm.id)
                        isWorking = false
                    }
                } label: {
                    Text("Dismiss").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(isWorking)
            }
        }
        .padding(.vertical, 6)
    }

    private var detail: String {
        let minutes = max(1, Int((item.date.timeIntervalSince(now) / 60).rounded(.up)))
        return "\(TimeFormat.string(for: item.date)) · in \(minutes) min"
    }
}

// MARK: - Permission banner

private struct PermissionBanner: View {
    @Environment(\.openURL) private var openURL
    var title = "Alarms Are Off"
    var message = "Allow alarms in Settings so they can ring, even in Silent mode."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

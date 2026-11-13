import SwiftUI

/// Running timers. New timers are set up in a sheet (like adding an alarm), with your last three
/// times one tap away.
struct TimersView: View {
    @Environment(TimerController.self) private var controller
    @State private var showNew = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !controller.timers.isEmpty {
                    Section("Running") {
                        ForEach(controller.timers) { timer in
                            TimerRow(timer: timer)
                                .swipeActions {
                                    Button("Cancel", role: .destructive) { controller.cancel(timer.id) }
                                }
                        }
                    }
                }

            }
            .listStyle(.insetGrouped)
            // Always the same light gray as the other tabs (an empty list would otherwise be white).
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .overlay {
                if controller.timers.isEmpty {
                    ContentUnavailableView {
                        Label("No Timers", systemImage: "timer")
                    } description: {
                        Text("Tap New Timer below. Your last three times are one tap away there.")
                    }
                }
            }
            .navigationTitle("Timers")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                TabHeader(title: "Timers", tab: .timers) { _ in
                    let running = controller.timers.filter { $0.state != .paused }.count
                    let paused = controller.timers.count - running
                    switch (running, paused) {
                    case (0, 0): return nil
                    case (_, 0): return "\(running) running"
                    case (0, _): return "\(paused) paused"
                    default: return "\(running) running · \(paused) paused"
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionButton(title: "New Timer", systemImage: "plus") { showNew = true }
            }
            .animation(.default, value: controller.timers)
            .sheet(isPresented: $showNew) {
                NewTimerSheet(recentTimes: controller.recentTimes) { duration, label in start(duration, label: label) }
            }
            .alert("Couldn't Start Timer", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(.orange)
    }

    private func start(_ duration: TimeInterval, label: String) {
        Task {
            do {
                try await controller.start(duration: duration, label: label)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - New timer sheet

private struct NewTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hours = 0
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var label = ""
    /// The last three times used (filled in with 5, 10 and 15 minutes at first).
    let recentTimes: [RecentTimer]
    let onStart: (TimeInterval, String) -> Void

    private var pickedDuration: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DurationWheel(hours: $hours, minutes: $minutes, seconds: $seconds)
                }
                .listRowBackground(Color.clear)

                Section {
                    // Recent times, the same chips as the to-do quick times: tap one to set the wheels.
                    HStack(spacing: 8) {
                        ForEach(recentTimes) { recent in
                            let selected = TimeInterval(hours * 3600 + minutes * 60 + seconds) == recent.duration
                            Button {
                                set(recent)
                            } label: {
                                Text(TimeFormat.compactDuration(recent.duration))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .fixedSize()
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selected ? Color.orange : Color(.tertiarySystemFill)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(recent.title)
                        }
                    }
                    .padding(.vertical, 4)
                    .sensoryFeedback(.selection, trigger: hours * 3600 + minutes * 60 + seconds)

                    HStack {
                        Text("Label")
                        TextField("Timer", text: $label)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .submitLabel(.done)
                    }
                } header: {
                    Text("Recent")
                }
            }
            .navigationTitle("New Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start(pickedDuration) }
                        .fontWeight(.semibold)
                        .disabled(pickedDuration == 0)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    start(pickedDuration)
                } label: {
                    Text("Start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(pickedDuration == 0)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .tint(.orange)
    }

    private func set(_ recent: RecentTimer) {
        let total = Int(recent.duration)
        hours = total / 3600
        minutes = total % 3600 / 60
        seconds = total % 60
        if label.isEmpty || recentTimes.contains(where: { $0.label == label }) { label = recent.label }
    }

    private func start(_ duration: TimeInterval) {
        guard duration > 0 else { return }
        onStart(duration, label.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

// MARK: - Running timer row

private struct TimerRow: View {
    @Environment(TimerController.self) private var controller
    let timer: TimerItem

    var body: some View {
        // Ticks aligned to the fire time so the seconds flip exactly on the beat.
        let anchor = timer.fireDate.addingTimeInterval(-(timer.duration.rounded(.up) + 1))
        TimelineView(.periodic(from: anchor, by: 1)) { context in
            let left = timer.timeLeft(at: context.date)
            HStack(spacing: 14) {
                ProgressRing(
                    progress: timer.duration > 0 ? left / timer.duration : 0,
                    systemImage: timer.state == .ringing ? "bell.fill" : nil
                )

                VStack(alignment: .leading, spacing: 0) {
                    Text(timer.state == .ringing ? "Time's up" : TimeFormat.clock(left - 0.05))
                        .font(.system(size: 34, weight: .light))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text(timer.state == .paused ? "\(timer.title) · Paused" : timer.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                switch timer.state {
                case .ringing:
                    Button("Stop") { controller.cancel(timer.id) }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(.red)
                case .running:
                    CircleButton(systemImage: "pause.fill") { controller.pause(timer.id) }
                case .paused:
                    CircleButton(systemImage: "play.fill") { controller.resume(timer.id) }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ProgressRing: View {
    let progress: Double
    let systemImage: String?

    var body: some View {
        ZStack {
            Circle().stroke(Color.orange.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
            }
        }
        .frame(width: 44, height: 44)
    }
}

private struct CircleButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.orange.opacity(0.15)))
                .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hours / minutes / seconds wheels

private struct DurationWheel: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int

    /// Numbers end at the same spot in every column, and each label starts a fixed gap after it.
    private static let numberWidth: CGFloat = 40
    private static let labelWidth: CGFloat = 52
    private static let gap: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
            wheel($hours, range: 0..<24, unit: "hours")
            wheel($minutes, range: 0..<60, unit: "min")
            wheel($seconds, range: 0..<60, unit: "sec")
        }
        .frame(height: 180)
    }

    private func wheel(_ selection: Binding<Int>, range: Range<Int>, unit: String) -> some View {
        Picker(unit, selection: selection) {
            ForEach(range, id: \.self) { value in
                HStack(spacing: 0) {
                    Text("\(value)")
                        .monospacedDigit()
                        .frame(width: Self.numberWidth, alignment: .trailing)
                    Color.clear.frame(width: Self.gap + Self.labelWidth)
                }
                .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .overlay {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.numberWidth + Self.gap)
                Text(unit)
                    .font(.headline)
                    .frame(width: Self.labelWidth, alignment: .leading)
            }
            .allowsHitTesting(false)
        }
    }
}

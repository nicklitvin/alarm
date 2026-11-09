import SwiftUI

struct TimersView: View {
    @Environment(TimerController.self) private var controller
    @State private var hours = 0
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var label = ""
    @State private var errorMessage: String?

    private static let presets: [TimeInterval] = [60, 3 * 60, 5 * 60, 10 * 60, 15 * 60, 30 * 60]

    private var pickedDuration: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

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

                Section {
                    DurationWheel(hours: $hours, minutes: $minutes, seconds: $seconds)
                }
                .listRowBackground(Color.clear)

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.presets, id: \.self) { preset in
                                Button(TimeFormat.compactDuration(preset)) { start(preset) }
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.orange.opacity(0.14)))
                                    .foregroundStyle(.orange)
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    HStack {
                        Text("Label")
                        TextField("Timer", text: $label)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .submitLabel(.done)
                    }
                } footer: {
                    Text("Tap a preset to start it right away.")
                }

                Section {
                    Button {
                        start(pickedDuration)
                    } label: {
                        Text("Start")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(pickedDuration == 0)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Timers")
            .animation(.default, value: controller.timers)
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

    private func start(_ duration: TimeInterval) {
        let label = label
        Task {
            do {
                try await controller.start(duration: duration, label: label)
                self.label = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
                Text("\(value)").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            Text(unit)
                .font(.headline)
                .padding(.trailing, 6)
                .allowsHitTesting(false)
        }
    }
}

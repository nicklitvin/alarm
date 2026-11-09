import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock screen + Dynamic Island UI for running timers (AlarmKit countdowns).
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AlarmPayload>.self) { context in
            TimerLockScreenView(context: context)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.displayTitle, systemImage: context.symbol)
                        .font(.headline)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: context.state)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimerButtons(context: context)
                        .padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: context.symbol)
                    .foregroundStyle(.orange)
            } compactTrailing: {
                CountdownText(state: context.state)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.symbol)
                    .foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
    }
}

private extension ActivityViewContext where Attributes == AlarmAttributes<AlarmPayload> {
    var isTimer: Bool { attributes.metadata?.isTimer ?? true }

    var displayTitle: String {
        let label = attributes.metadata?.label ?? ""
        return label.isEmpty ? (isTimer ? "Timer" : "Alarm") : label
    }

    var symbol: String { isTimer ? "timer" : "alarm.fill" }
}

private struct TimerLockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<AlarmPayload>>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label(context.displayTitle, systemImage: context.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                CountdownText(state: context.state)
                    .font(.system(size: 44, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            TimerButtons(context: context, compact: true)
        }
    }
}

private struct CountdownText: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            let now = Date.now
            Text(timerInterval: now...max(now, countdown.fireDate), countsDown: true)
        case .paused(let paused):
            Text(TimeFormat.clock(paused.totalCountdownDuration - paused.previouslyElapsedDuration))
        default:
            Text("0:00")
        }
    }
}

private struct TimerButtons: View {
    let context: ActivityViewContext<AlarmAttributes<AlarmPayload>>
    var compact = false

    var body: some View {
        if context.isTimer {
            let id = context.state.alarmID
            HStack(spacing: 10) {
                switch context.state.mode {
                case .countdown:
                    button("Pause", systemImage: "pause.fill", intent: PauseTimerIntent(timerID: id))
                case .paused:
                    button("Resume", systemImage: "play.fill", intent: ResumeTimerIntent(timerID: id))
                default:
                    EmptyView()
                }
                button("Cancel", systemImage: "xmark", intent: CancelTimerIntent(timerID: id))
            }
        }
    }

    @ViewBuilder
    private func button(_ title: String, systemImage: String, intent: some AppIntent) -> some View {
        Button(intent: intent) {
            if compact {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.orange.opacity(0.25)))
            } else {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.orange.opacity(0.25)))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
        .accessibilityLabel(title)
    }
}

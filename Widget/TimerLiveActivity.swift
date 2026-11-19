// Live Activities (AlarmKit timers) are iPhone and iPad only; the Mac build leaves them out.
#if !targetEnvironment(macCatalyst)
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
                .widgetURL(context.link) // tapping opens the Timers tab
        } dynamicIsland: { context in
            DynamicIsland {
                // The same fonts as the Timers tab (system font, light time), and the same 8 pt in
                // from the island's edge on both sides.
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.displayTitle, systemImage: context.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: context.state)
                        .font(.system(size: 30, weight: .light))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: context.state.countdownWidth(perDigit: 17), alignment: .trailing)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ExtendButtons(context: context)
                        TimerButtons(context: context)
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: context.symbol)
                    .foregroundStyle(.orange)
                    .padding(.leading, 4)
            } compactTrailing: {
                // Sized to the time, so the space either side of the island matches.
                CountdownText(state: context.state)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.orange)
                    .frame(width: context.state.countdownWidth(perDigit: 9), alignment: .trailing)
                    .padding(.trailing, 4)
            } minimal: {
                Image(systemName: context.symbol)
                    .foregroundStyle(.orange)
            }
            .widgetURL(context.link) // tapping the island opens the Timers tab
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

    /// Where a tap goes: the Timers tab (or Alarms, for an alarm).
    var link: URL { (isTimer ? DeepLink.timers : DeepLink.alarms).url }
}

private extension AlarmPresentationState {
    /// A width that fits the countdown ("9:58", "48:10", "1:02:03"), so a live countdown (which
    /// otherwise takes all the width it can) sits tight against its edge.
    func countdownWidth(perDigit: CGFloat) -> CGFloat {
        let left: TimeInterval = switch mode {
        case .countdown(let countdown): countdown.fireDate.timeIntervalSinceNow
        case .paused(let paused): paused.totalCountdownDuration - paused.previouslyElapsedDuration
        default: 0
        }
        let characters: CGFloat = left >= 3600 ? 7 : left >= 600 ? 5 : 4
        return characters * perDigit
    }
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

/// Touch and hold the Dynamic Island: add 1, 5 or 15 minutes to the timer.
private struct ExtendButtons: View {
    let context: ActivityViewContext<AlarmAttributes<AlarmPayload>>

    var body: some View {
        if context.isTimer {
            HStack(spacing: 8) {
                ForEach([1, 5, 15], id: \.self) { minutes in
                    Button(intent: ExtendTimerIntent(timerID: context.state.alarmID, minutes: minutes)) {
                        Text("+\(minutes) min")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Add \(minutes) minute\(minutes == 1 ? "" : "s")")
                }
            }
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
#endif

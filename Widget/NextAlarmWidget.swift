import SwiftUI
import WidgetKit

// MARK: - Timeline

struct NextAlarmEntry: TimelineEntry {
    let date: Date
    let next: UpcomingAlarm?
}

struct NextAlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(date: .now, next: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        let now = Date()
        let next = AlarmStorage.load().nextFire(after: now)
        completion(NextAlarmEntry(date: now, next: next ?? (context.isPreview ? .sample : nil)))
    }

    /// One entry now, then one each time an alarm rings, which moves the widget on to the next alarm.
    /// The app reloads the timeline whenever alarms change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let now = Date()
        let upcoming = AlarmStorage.load().upcomingFires(after: now, limit: 30)

        guard let last = upcoming.last else {
            completion(Timeline(entries: [NextAlarmEntry(date: now, next: nil)], policy: .never))
            return
        }

        // Refresh when each alarm rings (move on to the next one) and when it comes within 24 hours
        // (the lock screen shows zzz until then).
        let moments = Set(upcoming.flatMap { [$0.date, $0.date.addingTimeInterval(-NextAlarmWidgetView.lockScreenWindow)] }
            .filter { $0 > now })
        let entries = ([now] + moments.sorted().prefix(40)).map { date in
            NextAlarmEntry(date: date, next: upcoming.first { $0.date > date })
        }
        completion(Timeline(entries: entries, policy: .after(last.date)))
    }
}

private extension UpcomingAlarm {
    static var sample: UpcomingAlarm {
        let date = AlarmItem.nextTime(hour: 7, minute: 0, after: .now) ?? .now
        return UpcomingAlarm(alarm: AlarmItem(hour: 7, minute: 0, weekdays: Weekday.workdays), date: date)
    }
}

// MARK: - Views

struct NextAlarmWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextAlarmEntry

    /// Lock screen widgets only show an alarm within this window; otherwise zzz.
    static let lockScreenWindow: TimeInterval = 24 * 3600

    /// The next alarm, if it rings within 24 hours.
    private var soon: UpcomingAlarm? {
        guard let next = entry.next, next.date.timeIntervalSince(entry.date) <= Self.lockScreenWindow else { return nil }
        return next
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .systemSmall: small
            default: rectangular
            }
        }
        // Tapping opens that alarm in the app (or the Alarms tab when there's none).
        .widgetURL((entry.next.map { DeepLink.alarm($0.alarm.id) } ?? .alarms).url)
    }

    // Home screen: big time, day and countdown.
    @ViewBuilder
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: entry.next == nil ? "alarm" : "alarm.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                if let next = entry.next {
                    Text(TimeFormat.dayDescription(for: next.date, relativeTo: entry.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let next = entry.next {
                let parts = TimeFormat.parts(for: next.date)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(parts.time)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let period = parts.period {
                        Text(period).font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(next.alarm.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("in \(next.date, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No Alarms")
                    .font(.title3.weight(.semibold))
                Text("Tap to add one")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // "⏰ Tue 7:00 AM"
    @ViewBuilder
    private var inline: some View {
        if let next = soon {
            let isToday = Calendar.current.isDate(next.date, inSameDayAs: entry.date)
            let day = next.date.formatted(.dateTime.weekday(.abbreviated))
            Label(isToday ? TimeFormat.string(for: next.date) : "\(day) \(TimeFormat.string(for: next.date))",
                  systemImage: "alarm.fill")
        } else {
            Label(entry.next == nil ? "No alarms" : "No alarm today", systemImage: "zzz")
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let next = soon {
                let parts = TimeFormat.parts(for: next.date)
                VStack(spacing: 0) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .widgetAccentable()
                    Text(parts.time)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let period = parts.period {
                        Text(period)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            } else {
                Image(systemName: "zzz")
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next = soon {
                let parts = TimeFormat.parts(for: next.date)
                Label(next.alarm.title, systemImage: "alarm.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .widgetAccentable()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(parts.time)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let period = parts.period {
                        Text(period)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text("\(TimeFormat.dayDescription(for: next.date, relativeTo: entry.date)) · in \(next.date, style: .relative)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                // Nothing in the next 24 hours: just zzz.
                HStack(spacing: 8) {
                    Image(systemName: "zzz")
                        .font(.system(size: 26, weight: .semibold))
                        .widgetAccentable()
                    Text(entry.next == nil ? "No alarms" : "No alarm in the next 24 hours")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct NextAlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AlarmStorage.widgetKind, provider: NextAlarmProvider()) { entry in
            NextAlarmWidgetView(entry: entry)
                .widgetBackground()
        }
        .configurationDisplayName("Next Alarm")
        .description("See when your next alarm will go off.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct AlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
        UpNextWidget()
        TimerLiveActivity()
        AskAssistantControl()
        LiveTalkControl()
    }
}

#Preview(as: .accessoryRectangular) {
    NextAlarmWidget()
} timeline: {
    NextAlarmEntry(date: .now, next: .sample)
    NextAlarmEntry(date: .now, next: nil)
}

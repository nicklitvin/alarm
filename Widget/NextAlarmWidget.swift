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

        var entries = [NextAlarmEntry(date: now, next: upcoming.first)]
        for index in upcoming.indices.dropLast() {
            entries.append(NextAlarmEntry(date: upcoming[index].date, next: upcoming[index + 1]))
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

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        default: rectangular
        }
    }

    // "⏰ Tue 7:00 AM"
    @ViewBuilder
    private var inline: some View {
        if let next = entry.next {
            let isToday = Calendar.current.isDate(next.date, inSameDayAs: entry.date)
            let day = next.date.formatted(.dateTime.weekday(.abbreviated))
            Label(isToday ? TimeFormat.string(for: next.date) : "\(day) \(TimeFormat.string(for: next.date))",
                  systemImage: "alarm.fill")
        } else {
            Label("No Alarm", systemImage: "alarm")
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let next = entry.next {
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
                Image(systemName: "alarm")
                    .font(.system(size: 22, weight: .medium))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next = entry.next {
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
                Label("Alarm", systemImage: "alarm")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text("No alarms set")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
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
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Next Alarm")
        .description("See when your next alarm will go off.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct AlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextAlarmWidget()
    }
}

#Preview(as: .accessoryRectangular) {
    NextAlarmWidget()
} timeline: {
    NextAlarmEntry(date: .now, next: .sample)
    NextAlarmEntry(date: .now, next: nil)
}

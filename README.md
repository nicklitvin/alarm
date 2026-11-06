# Alarm

A simple, clean iPhone alarm app built with SwiftUI and **AlarmKit**, so alarms ring like the built-in Clock app: full screen on the lock screen, even in Silent mode or a Focus.

## Features

- **Alarms for specific days and times.** Pick a time and any set of weekdays, or none for a one-time alarm.
- **Lock screen widget** that shows when your next alarm will go off. It comes in three sizes: rectangular, circular and inline.
- **Heads-up notification 1 hour before** each alarm. Touch and hold it and tap **Dismiss Alarm** to cancel that ring. The next one still rings as normal.
- **Dismiss in the app.** If you open the app within an hour of an alarm, a card at the top has a **Dismiss** button, plus **Undo**.

## Requirements

- Xcode 26 or later
- iOS 26 or later on a real iPhone (AlarmKit alarms don't ring in the Simulator)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project

## Getting started

1. Open `project.yml` and set:
   - `DEVELOPMENT_TEAM`: your Apple Developer Team ID (Xcode → Settings → Accounts)
   - `APP_BUNDLE_ID`: something unique, e.g. `com.yourname.alarm`. The widget ID and App Group are derived from it.
2. Generate the project and open it:
   ```sh
   brew install xcodegen
   xcodegen generate
   open Alarm.xcodeproj
   ```
3. Select the **Alarm** scheme and your iPhone, then run.
4. When asked, allow **Alarms** and **Notifications**.
5. To add the widget: long-press the lock screen → **Customize** → **Lock Screen** → tap the widget area → **Alarm** → **Next Alarm**.

## How it works

| Piece | File |
| --- | --- |
| Alarm model and next-ring math (shared with widget) | `Shared/AlarmItem.swift` |
| Storage in the App Group (shared with widget) | `Shared/AlarmStorage.swift` |
| Which system alarms should exist | `App/Services/AlarmPlan.swift` |
| Syncs that plan to AlarmKit | `App/Services/AlarmKitScheduler.swift` |
| 1-hour heads-up notifications and the Dismiss action | `App/Services/NotificationScheduler.swift` |
| App state; every change syncs AlarmKit, notifications and widget | `App/Services/AlarmController.swift` |
| UI | `App/Views/` |
| Lock screen widget | `Widget/NextAlarmWidget.swift` |

**Dismissing one ring of a repeating alarm.** AlarmKit can't skip a single occurrence of a repeating alarm. Say you have a Mon–Fri 7:00 alarm and dismiss Friday's ring. The app reschedules it as a weekly Mon–Thu alarm, plus one-off alarms for the following 8 Fridays. Once the dismissed Friday has passed, the next time the app opens it merges these back into a single Mon–Fri alarm.

**Dismissing a one-time alarm** simply turns it off.

## Tests

The scheduling and date logic can be tested without Xcode:

```sh
./Tests/run.sh
```

## Notes

- Each repeating alarm uses one pending notification per weekday. iOS allows 64 pending notifications per app, which is plenty for normal use.
- The heads-up notification is Time Sensitive, so it gets through most Focus modes.

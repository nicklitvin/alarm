# Alarmie

A simple, clean iPhone alarm app built with SwiftUI and **AlarmKit**, so alarms ring like the built-in Clock app: full screen on the lock screen, even in Silent mode or a Focus.

## Features

- **Works sideways too.** Turn your iPhone and Alarms shows a grid of cards with big times.
- **Alarms for specific days and times.** Pick a time and any set of weekdays, or none for a one-time alarm, and a sound (Default, Chime, Beacon, Pulse, Rise or Bells).
- **Lock screen widget** that shows when your next alarm will go off. It comes in three sizes: rectangular, circular and inline.
- **Heads-up notification before each alarm** (1 hour by default; change it in Alarm settings). It says when the alarm rings. Touch and hold it and tap **Dismiss Alarm** to cancel that ring, or turn on **Tap Notification to Dismiss** in Alarm settings to cancel it with a single tap. Swiping the notification away never cancels anything. The next ring still happens as normal.
- **Dismiss in the app.** If you open the app within an hour of an alarm, a card at the top has a **Dismiss** button. Once dismissed, the card goes away and the alarm shows "Skipping today".
- **Timers tab.** Your running timers. **New Timer** opens a sheet with hour, minute and second wheels, your last three times as one-tap buttons, and a label. Timers ring through Silent mode and show a countdown on the lock screen and in the Dynamic Island, with Pause and Cancel buttons.
- **To-Do tab.** Add a to-do and tap a suggested time ("In 1 hour", "Tonight", "Tomorrow morning", …) or pick a custom time and date. Under the deadline, three one-tap quick times (8 AM, 2 PM and 9 PM to start) can be changed in To-Do settings. Tap **New To-Do** to add an empty row at the end of the list and start typing, like Reminders; press Return or tap elsewhere to finish. Edit any to-do right in the list, and tap 📅 for the deadline (your quick times, or any date and time). You get a notification at the deadline with **Mark as Done**, **Remind Me in 1 Hour** and **Remind Me Tomorrow** buttons. To-dos are one simple list, soonest deadline first, with completed ones in a compact list at the bottom.
- **Notes tab.** Searchable notes with **Copy All**, **Clear** (removes the text, keeps the title) and **Delete** buttons on every note. Tap the checklist button to make a to-do list inside a note (tap a box to check it off), or the bullet button for a bulleted list (or type "- "). Return starts the next item. Pin notes to the top (swipe right), press and hold a note to drag it somewhere else, or sort by date or title. The assistant can read them ("what's on my packing note?") and write to them ("add charger to my packing note").
- **Widgets.**
  - **Up Next:** home screen (small, medium, large) and lock screen. Shows what's relevant now: an alarm within the hour with a **Dismiss** button, running timers, overdue and soon-due to-dos, the next alarm, then the rest of your to-dos. Tap an alarm or timer to open its tab, a to-do to open that to-do, or tap a to-do's circle to check it off. The title shows how many to-dos you have, the list uses the full height, and the ✦ button in the bottom-right corner (medium and large sizes) opens Talk.
  - **Next Alarm:** home screen (small) and lock screen. Tap it to open the Alarms tab. On the lock screen it shows zzz when nothing rings in the next 24 hours.
- **Settings per tab.** The gear next to each tab's title opens that tab's settings: when to get alarm heads-ups and to-do reminders, your to-do quick times, how to sort notes, and Talk options. Each also has **Delete All** for that tab and **About & Updates**.
- **Updates and patch notes.**
  - The app checks the App Store for a newer version and offers to open it there. A copy installed from Xcode isn't on the App Store, so it just says so.
  - Open any tab's settings → **About & Updates** to see your version and the patch notes for every release.
  - A "What's New" screen appears the first time you open a new version.
- **Control Center button.**
  - **Live Talk:** a pop-up at the top of the screen with your conversation. Tap **Type a Message** to talk to the assistant without opening the app, or 🎙 to open the app for hands-free Live Talk.
  - You can also ask the assistant through Siri ("Ask Alarmie"), Spotlight, Shortcuts and the Action button.
- **Talk tab.** A private assistant that runs entirely on your iPhone using Apple's on-device model:
  - Tap the waveform for hands-free **Live Talk**: it listens, replies out loud and listens again. You can still type at any time.
  - It can manage almost everything in the app:
    - **Alarms:** create, change, turn on or off, delete ("wake me up at 6:45 on weekdays", "move my gym alarm to 7").
    - **To-dos:** add with a deadline and details, reschedule, complete, delete ("remind me to call mom tomorrow at 6").
    - **Notes:** read, create, add to, replace, rename, delete ("add eggs to my grocery note").
    - **Timers:** start and cancel ("set a pasta timer for 9 minutes").
    - **Settings:** wake word and spoken replies ("turn on the wake word and set it to Jarvis").
  - **Custom Instructions** (Talk settings): your own instructions, applied to every conversation and reply.
  - **Optional wake word**, off by default (Talk settings → Require Wake Word). When on, Live Talk ignores sentences that don't start with your wake word, e.g. "Hey Alarm, …". Say only the wake word and your next sentence counts. Typed messages always get a reply.

## Requirements

- Xcode 26 or later
- iOS 26 or later on a real iPhone (AlarmKit alarms don't ring in the Simulator)
- For the Talk tab: an iPhone with Apple Intelligence turned on (iPhone 15 Pro or newer)
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
4. When asked, allow **Alarms** and **Notifications**. The Talk tab asks for **Microphone** and **Speech Recognition** the first time you start Live Talk.
5. To add widgets:
   - **Home screen:** long-press an empty spot → **Edit** → **Add Widget** → **Alarm**.
   - **Lock screen:** long-press the lock screen → **Customize** → **Lock Screen** → tap the widget area → **Alarm**.
   - **Control Center:** swipe down from the top-right corner → tap **+** (top left) → **Add a Control** → search "Alarm" → pick **Live Talk**.

## How it works

| Piece | File |
| --- | --- |
| Alarm model and next-ring math (shared with widget) | `Shared/AlarmItem.swift` |
| Storage in the App Group (shared with widget) | `Shared/AlarmStorage.swift` |
| Which system alarms should exist | `App/Services/AlarmPlan.swift` |
| Syncs that plan to AlarmKit | `App/Services/AlarmKitScheduler.swift` |
| Re-syncs when an alarm's Stop is tapped | `App/Services/StopAlarmIntent.swift` |
| Background refresh after a dismissed ring | `App/Services/BackgroundRefresh.swift` |
| Heads-up notifications and the Dismiss action | `App/Services/NotificationScheduler.swift` |
| App state; every change syncs AlarmKit, notifications and widget | `App/Services/AlarmController.swift` |
| Alarms UI | `App/Views/` |
| Timers (AlarmKit countdowns) and their tab | `App/Timers/` |
| Lock screen / Dynamic Island timer Live Activity | `Widget/TimerLiveActivity.swift` |
| Talk: on-device model and timer tools | `App/Talk/TalkModel.swift`, `App/Talk/AssistantTools.swift` |
| Talk: speech in/out and wake word | `App/Talk/LiveVoice.swift`, `App/Talk/WakeWord.swift` |
| Talk: reading "tomorrow at 5pm" and finding "my gym alarm" | `App/Talk/NaturalTime.swift`, `App/Talk/AssistantMatching.swift` |
| To-dos: model, storage, reminders, widget toggle (shared with widget) | `Shared/TodoItem.swift`, `Shared/TodoReminders.swift`, `Shared/TodoIntents.swift` |
| To-Do tab and suggested times | `App/Todos/` |
| Up Next widget (what's relevant now) | `Shared/UpNext.swift`, `Widget/UpNextWidget.swift` |
| Notes tab | `App/Notes/` |
| Version check, What's New, patch notes | `App/About/`, `CHANGELOG.json` |
| Control Center button, Siri and Shortcuts | `Shared/AssistantIntents.swift`, `Widget/AssistantControls.swift`, `App/Talk/AssistantShortcuts.swift` |
| Lock screen widget | `Widget/NextAlarmWidget.swift` |
| Alarm sounds (made by `Tools/make_sounds.py`) | `Shared/AlarmSound.swift`, `App/Sounds/` |

**Dismissing one ring of a repeating alarm.** Each weekday of an alarm is its own weekly system alarm. AlarmKit can't skip a single occurrence, so when you dismiss Friday's ring, only Friday is touched: it's swapped for a one-time alarm next Friday, and Mon–Thu are left alone. The weekly Friday alarm comes back the first time any app code runs after the dismissed time:

- iOS gives the app background time, which it requests for 1 minute after the dismissed ring.
- You tap **Stop** on any of the app's alarms. This includes next Friday's one-time alarm itself, so restoring never depends on opening the app.
- You open the app or use a notification action.

**Dismissing a one-time alarm** simply turns it off.

## Web preview

`web/` is a browser copy of the app's screens (Vite + React) for reviewing the design without building in Xcode. It never rings, isn't part of the iPhone app, and can be deployed on Vercel. See [web/README.md](web/README.md).

## Versions and updates

- `CHANGELOG.json` lists every version with its patch notes, newest first. It's bundled into the app for the patch notes and What's New screens.
- To release: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, add a matching entry at the top of `CHANGELOG.json`, then push to `main`. `./Tests/run.sh` fails if the two don't match.
- The app checks at launch and when it comes to the foreground, at most every 6 hours, or straight away with **Check for Updates** on the About screen.
- Updates are found with Apple's App Store lookup service, using the app's bundle ID. When a newer version is listed, the app shows its App Store release notes with an **Update in App Store** button. iOS also installs App Store updates by itself if automatic updates are on.

## Tests

The scheduling and date logic can be tested without Xcode:

```sh
./Tests/run.sh
```

## Notes

- Each repeating alarm uses one pending notification per weekday. iOS allows 64 pending notifications per app, which is plenty for normal use.
- The heads-up notification is Time Sensitive, so it gets through most Focus modes.

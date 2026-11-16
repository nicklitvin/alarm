# Alarmie

A simple, clean iPhone alarm app built with SwiftUI and **AlarmKit**, so alarms ring like the built-in Clock app: full screen on the lock screen, even in Silent mode or a Focus.

## Features

- **Works sideways too.** Turn your iPhone and Alarms shows a grid of cards, each with its time and switch side by side.
- **Alarms for specific days and times.** Pick a time and any set of weekdays, or none for a one-time alarm, and a sound (Default, Chime, Beacon, Pulse, Rise or Bells).
- **Lock screen widget** that shows when your next alarm will go off. It comes in three sizes: rectangular, circular and inline.
- **Heads-up notification before each alarm** (1 hour by default; change it in Alarm settings). It says when the alarm rings. Tap it to open the Alarms tab, where a **Dismiss** button is waiting, or touch and hold it and tap **Dismiss Alarm**. Swiping the notification away never cancels anything. The next ring still happens as normal.
- **Dismiss in the app.** From 12 hours before an alarm (Alarm settings → Show Alarm: any number of hours from 1 to 24), a card at the top of the Alarms tab has a **Dismiss** button (the widgets offer it too). Once dismissed, the card goes away.
- **Timers tab.** Your running timers, and a **Stopwatch** (button next to New Timer) with laps that keeps counting while the app is closed. **New Timer** opens a sheet with hour, minute and second wheels, three one-tap quick times (5, 10 and 15 min to start; change them in Timer settings, or turn on **Use Recent Times** to get your last three times instead), and a label. Timers ring through Silent mode and show a countdown on the lock screen and in the Dynamic Island, with Pause and Cancel buttons.
- **To-Do tab.** Add a to-do and tap a suggested time ("In 1 hour", "Tonight", "Tomorrow morning", …) or pick a custom time and date. Under the deadline, three one-tap quick times (8 AM, 2 PM and 9 PM to start) can be changed in To-Do settings. Tap **New To-Do** to open a sheet like Add Alarm: title, details and an optional deadline, then **Add To-Do**. Edit any to-do right in the list, and tap 📅 for the deadline (your quick times, or any date and time). You get a notification at the deadline with **Mark as Done**, **Remind Me in 1 Hour** and **Remind Me Tomorrow** buttons. To-dos are one simple list: press and hold one and drag it to rearrange. New to-dos slot in by deadline. Completed ones sit in a compact list at the bottom.
- **Notes tab.** Searchable notes. Inside a note: **Copy All**, **Clear** (removes the text, keeps the title) and **Delete**. Tap the checklist button to make a to-do list inside a note (tap a box to check it off), or the bullet button for a bulleted list (or type "- "). Return starts the next item. Pin notes to the top (swipe right) and sort by date edited, date created or title. The assistant can read them ("what's on my packing note?") and write to them ("add charger to my packing note").
- **Widgets.**
  - **Up Next:** home screen (medium, large) and lock screen. Your next alarm sits on top with a **Dismiss** button from 12 hours before it rings (change it in Alarm settings → Show Alarm), followed by running timers and to-dos, most urgent first. Tap anything to open its tab, or tap a to-do's circle to check it off. The title shows how many to-dos you have, and the waveform button in the bottom-right corner (medium and large) opens Talk.
  - **Next Alarm:** home screen (small: the next alarm with a full-width **Dismiss** button) and lock screen (circular, rectangular, inline; zzz until the alarm is within the Show Alarm window). Tap it to open the Alarms tab.
- **Settings per tab.** The gear next to each tab's title opens that tab's settings: when to get alarm heads-ups and to-do reminders, your to-do quick times, how to sort notes, and Talk options. Each also has **Delete All** for that tab and **About & Updates**.
- **Updates and patch notes.**
  - The app checks the App Store for a newer version and offers to open it there. A copy installed from Xcode isn't on the App Store, so it just says so.
  - Open any tab's settings → **About & Updates** to see your version and the patch notes for every release.
  - A "What's New" screen appears the first time you open a new version.
- **Siri and Shortcuts.** Ask the assistant through Siri ("Ask Alarmie"), Spotlight, Shortcuts and the Action button.
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
- For the Mac app: macOS 26 or later on an Apple silicon Mac (pick **My Mac (Mac Catalyst)** as the run destination)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project

## Getting started

1. Create `Config/Signing.local.xcconfig` (ignored by git, so updates never touch it) with:
   ```
   DEVELOPMENT_TEAM = ABCDE12345          // your Apple Developer Team ID (Xcode → Settings → Accounts)
   APP_BUNDLE_ID = com.yourname.alarm     // something unique; the widget ID and App Group follow it
   ```
   **Every build must use the same team and bundle ID as the copy on your phone.** Your data lives
   in the App Group `group.<bundle ID>`; a build with a different team or bundle ID (or without
   the App Group) can't see it, opens empty, and its widgets stop updating. The app warns about
   this in the Alarms tab and in Settings → About & Updates. To check a build:
   `codesign -d --entitlements - Alarmie.app` must list `group.<bundle ID>` under
   `com.apple.security.application-groups` (the widget too).
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
| Siri and Shortcuts | `Shared/AssistantIntents.swift`, `App/Talk/AssistantShortcuts.swift` |
| Lock screen widget | `Widget/NextAlarmWidget.swift` |
| Alarm sounds (made by `Tools/make_sounds.py`) | `Shared/AlarmSound.swift`, `App/Sounds/` |

**Starting Live Talk from another app.** Open `alarmapp://livetalk`: Alarmie opens on Talk and
starts listening. From a Mac app (Alarmie running on the same Mac as an iPhone app on Apple
silicon):

```swift
NSWorkspace.shared.open(URL(string: "alarmapp://livetalk")!)
```

The **Start Live Talk** action in Shortcuts does the same; a Mac app can run a shortcut that
uses it with `/usr/bin/shortcuts run "<shortcut name>"`. Other links: `alarmapp://talk` (just
the tab), `alarmapp://alarms`, `alarmapp://todos`, `alarmapp://notes`, `alarmapp://timers`.

**Dismissing one ring of a repeating alarm.** Each weekday of an alarm is its own weekly system alarm. AlarmKit can't skip a single occurrence, so when you dismiss Friday's ring, only Friday is touched: it's swapped for a one-time alarm next Friday, and Mon–Thu are left alone. The weekly Friday alarm comes back the first time any app code runs after the dismissed time:

- iOS gives the app background time, which it requests for 1 minute after the dismissed ring.
- You tap **Stop** on any of the app's alarms. This includes next Friday's one-time alarm itself, so restoring never depends on opening the app.
- You open the app or use a notification action.

**Dismissing a one-time alarm** simply turns it off.

## Your data: backups and Recently Deleted

Everything is saved in the App Group's shared storage (`AlarmStorage.defaults`), which the widgets
read too. To make sure an update can never lose it:

- **Backups** (`App/Services/DataBackup.swift`, `App/Services/Backups.swift`): every change is copied
  into a backup file for the day (the last 14 days are kept), both in the app's own container and in
  the App Group container. If everything suddenly empties, the previous copy is kept aside.
- **Automatic restore**: at launch, if the storage has never been used (no data, not marked) but a
  backup has data, the backup is put back. A reinstall or a copy signed without the App Group would
  otherwise open empty.
- **Restore by hand**: Settings → About & Updates → Backups lists every backup ("3 alarms · 8 to-dos
  · 5 notes") and restores one (what you have is backed up first).
- **Shared storage check**: if this copy can't reach the App Group (signed without it), the Alarms
  tab and About say so. That's also why the widgets would stop matching the app.
- **Notes: Recently Deleted**: deleted notes (and Delete All Notes) wait 30 days before they're
  removed for good, and can be recovered from Notes settings → Recently Deleted (`NotesTrash` in `App/Notes/Note.swift`).

When building for TestFlight or the App Store, keep the same bundle ID, team and App Group
(`group.<bundle ID>`), or the new build can't see the data saved by the old one.

## Mac and iPad

The same target runs on iPad and, through Mac Catalyst, as a Mac app (same bundle ID and App Group,
so it shares data with its own widgets). In a wide window the tab bar becomes a sidebar
(`.sidebarAdaptable`) and each tab switches to a wide layout when the horizontal size class is
regular: Alarms as a grid of cards, Timers with the stopwatch in its own column and timers as cards,
To-Do in two columns (your to-dos and Completed | Deadlines), Notes with the list beside the open
note, and Talk in a centered column. The Mac window has a minimum size of 820 × 560
(`MacWindow` in `App/RootView.swift`). The Mac build uses its own entitlements
(`App/Alarm-Mac.entitlements`, `Widget/AlarmWidget-Mac.entitlements`) for the sandbox, network and
microphone.

**Menu bar item.** On the Mac, Alarmie puts a ⏰ in the menu bar (next to the battery). Its menu
shows the next alarm and how many to-dos are open, and opens any tab or Live Talk. Mac Catalyst
can't use AppKit, so the item is a small AppKit bundle (`MenuBar/AlarmieMenuBar.swift`, target
`AlarmieMenuBar`) embedded in the Mac build's PlugIns folder and loaded at launch by
`App/Services/MenuBarBridge.swift`; its items open Alarmie's own `alarmapp://` links.

**Alarms and timers on the Mac.** AlarmKit and ActivityKit don't build for Mac Catalyst, so that
code is compiled out of the Mac build (`#if !targetEnvironment(macCatalyst)`). On the Mac,
`AlarmKitScheduler` schedules each planned alarm (same `AlarmPlan`, including a dismissed ring) as a
time-sensitive notification with the alarm's sound, and timers end with a notification
(`MacTimers` in `TimerController.swift`); there are no Live Activities. A sleeping Mac won't wake up
for these, so the iPhone remains the alarm clock.

## Web preview

`web/` is a browser copy of the app's screens (Vite + React) for reviewing the design without building in Xcode. Tabs at the top switch between the iPhone app, the Mac app (sidebar and wide layouts) and Widgets & System. It never rings, isn't part of the iPhone app, and can be deployed on Vercel. See [web/README.md](web/README.md).

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

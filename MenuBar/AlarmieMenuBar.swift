import AppKit

/// Alarmie's menu bar item on the Mac (next to the battery and Wi-Fi).
///
/// The Mac app is the iPad app running on the Mac (Mac Catalyst), which can't use AppKit itself.
/// So this small AppKit bundle is embedded in the app's PlugIns folder and loaded at launch
/// (`MenuBarBridge` in the app). It talks to the app only through:
/// - two text properties the app sets (`nextAlarmText`, `todoText`), shown at the top of the menu;
/// - Alarmie's own links (alarmapp://…), which the app already handles for widgets and
///   notifications, so every menu item opens the right tab.
@objc(AlarmieMenuBar)
final class AlarmieMenuBar: NSObject {
    private var statusItem: NSStatusItem?

    /// "Next alarm: Tomorrow 7:00 AM" (set by the app whenever alarms change).
    @objc dynamic var nextAlarmText: String = "No alarms" { didSet { rebuildMenu() } }
    /// "3 to-dos open" (set by the app whenever to-dos change).
    @objc dynamic var todoText: String = "" { didSet { rebuildMenu() } }

    override init() {
        super.init()
        DispatchQueue.main.async { self.install() }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: "Alarmie")
        image?.isTemplate = true // black or white with the menu bar, like the system's icons
        item.button?.image = image
        item.button?.toolTip = "Alarmie"
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        // What's coming up (not clickable, like the battery menu's status lines).
        menu.addItem(info(nextAlarmText))
        if !todoText.isEmpty { menu.addItem(info(todoText)) }
        menu.addItem(.separator())

        menu.addItem(link("Open Alarmie", "alarmapp://alarms", key: "o"))
        menu.addItem(link("Live Talk", "alarmapp://livetalk", key: "l"))
        menu.addItem(.separator())
        menu.addItem(link("Alarms", "alarmapp://alarms", symbol: "alarm"))
        menu.addItem(link("Timers", "alarmapp://timers", symbol: "timer"))
        menu.addItem(link("To-Do", "alarmapp://todos", symbol: "checklist"))
        menu.addItem(link("Notes", "alarmapp://notes", symbol: "note.text"))
        menu.addItem(link("Talk", "alarmapp://talk", symbol: "waveform"))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Alarmie", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func link(_ title: String, _ url: String, key: String = "", symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openLink(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = URL(string: url)
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    /// Brings Alarmie to the front and opens the link (the app shows the tab, or starts Live Talk).
    @objc private func openLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

import Foundation

/// The Mac app's menu bar item (next to the battery). Mac Catalyst can't use AppKit directly, so
/// the item lives in a small AppKit plugin (`MenuBar/AlarmieMenuBar.swift`, embedded in PlugIns)
/// that this loads at launch and keeps up to date. Does nothing on iPhone and iPad.
@MainActor
enum MenuBarBridge {
    private static var plugin: NSObject?

    static func install() {
        #if targetEnvironment(macCatalyst)
        guard plugin == nil,
              let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("AlarmieMenuBar.bundle"),
              let bundle = Bundle(url: url), bundle.load(),
              let type = bundle.principalClass as? NSObject.Type
        else { return }
        plugin = type.init()
        update()
        #endif
    }

    /// Refreshes the menu's status lines. Called whenever alarms or to-dos change.
    static func update() {
        guard let plugin else { return }
        let now = Date()
        let next = AlarmController.shared.nextFire(now: now).map {
            "Next alarm: \(TimeFormat.dayDescription(for: $0.date, relativeTo: now)) \(TimeFormat.string(for: $0.date))"
        } ?? "No alarms"
        let open = TodoController.shared.openTodos.count
        plugin.setValue(next, forKey: "nextAlarmText")
        plugin.setValue(open == 0 ? "No to-dos" : "\(open) to-do\(open == 1 ? "" : "s") open", forKey: "todoText")
    }
}

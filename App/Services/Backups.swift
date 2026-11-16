import Foundation
import WidgetKit

/// The app side of `DataBackup`: where backups live, when they're made, and restoring one.
@MainActor
enum Backups {
    /// The app's own container (survives a build that can't reach the App Group) and the shared
    /// App Group container (survives anything that keeps the group).
    static var directories: [URL] {
        var directories: [URL] = []
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            directories.append(support.appendingPathComponent("Backups"))
        }
        if let group = sharedContainer {
            directories.append(group.appendingPathComponent("Library/Application Support/Backups"))
        }
        return directories
    }

    private static var sharedContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AlarmStorage.appGroupIdentifier)
    }

    /// At launch, before anything loads: puts a backup back if the storage is brand new.
    static func restoreIfNeeded() {
        if DataBackup.restoreIfUntouched(AlarmStorage.defaults, directories: directories) {
            print("Alarmie: restored data from a backup (storage was empty)")
        }
    }

    private static var pending: Task<Void, Never>?

    /// After a change: a backup a moment later (several quick changes make one backup).
    static func scheduleBackup() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            backUpNow()
        }
    }

    static func backUpNow() {
        let values = DataBackup.values(in: AlarmStorage.defaults)
        for directory in directories { DataBackup.save(values, in: directory) }
    }

    static var all: [DataBackup.Backup] { DataBackup.backups(in: directories) }

    /// Replaces your data with `backup` (what you have now is kept aside first) and reloads it.
    static func restore(_ backup: DataBackup.Backup) {
        let current = DataBackup.values(in: AlarmStorage.defaults)
        for directory in directories {
            try? DataBackup.write(current, to: directory.appendingPathComponent("before-empty-\(Int(Date().timeIntervalSince1970)).plist"))
        }
        DataBackup.restore(backup.values, into: AlarmStorage.defaults)
        AlarmController.shared.reloadFromStorage()
        TodoController.shared.reload()
        NotesController.shared.reloadFromStorage()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

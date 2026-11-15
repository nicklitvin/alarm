import Foundation

/// Backups of everything Alarmie saves (alarms, to-dos, notes, timers, settings), so nothing is
/// ever lost to a bad update or a build that can't reach the shared storage.
///
/// - Every change is copied into today's backup file (one per day, holding that day's latest
///   state); the last 14 days are kept. `Backups` (app side) writes them in two places: the app's
///   own container and the shared App Group container.
/// - If everything suddenly empties, the copy from just before is kept aside as well.
/// - At launch, if the storage has never been used (no data, not marked as used) but a backup has
///   data, the backup is put back automatically. That's what a reinstalled widget-less build or a
///   build signed without the App Group would otherwise look like: an empty app.
/// - Any backup can also be restored by hand (Settings → About & Updates → Backups).
///
/// Foundation only, so `Tests/run.sh` can test it.
enum DataBackup {
    /// The saved lists. Settings ("settings.…") and Talk settings ("talk.…") come along too.
    static let dataKeys = ["alarms.v1", "todos.v1", "notes.v1", "timers.v1", "timers.recents.v1", "stopwatch.v1"]
    /// Set once this storage has been used by a version that makes backups.
    static let initializedKey = "storage.initialized"
    static let keepDays = 14

    static func isOwned(_ key: String) -> Bool {
        dataKeys.contains(key) || key.hasPrefix("settings.") || key.hasPrefix("talk.")
    }

    /// Everything Alarmie saved in `defaults`.
    static func values(in defaults: UserDefaults) -> [String: Any] {
        defaults.dictionaryRepresentation().filter { isOwned($0.key) }
    }

    // MARK: - What's in a backup

    struct Summary: Equatable {
        var alarms = 0, todos = 0, notes = 0

        var isEmpty: Bool { alarms + todos + notes == 0 }

        /// "3 alarms · 8 to-dos · 5 notes"
        var text: String {
            func part(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
            return [part(alarms, "alarm", "alarms"), part(todos, "to-do", "to-dos"), part(notes, "note", "notes")]
                .joined(separator: " · ")
        }
    }

    static func summary(of values: [String: Any]) -> Summary {
        func count(_ key: String) -> Int {
            guard let data = values[key] as? Data,
                  let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return 0 }
            return list.count
        }
        let notes = (values["notes.v1"] as? Data).flatMap { try? JSONDecoder().decode([Note].self, from: $0) }
        return Summary(alarms: count("alarms.v1"), todos: count("todos.v1"),
                       notes: notes?.filter { !$0.isDeleted }.count ?? 0)
    }

    struct Backup: Identifiable {
        let url: URL
        let date: Date
        let values: [String: Any]
        var id: URL { url }
        var summary: Summary { DataBackup.summary(of: values) }
    }

    // MARK: - Files

    static func read(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    static func write(_ values: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// "backup-2026-11-15.plist"
    static func dayFileName(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "backup-%04d-%02d-%02d.plist", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Saves `values` as today's backup in `directory`. If that empties a backup that had data,
    /// the previous copy is kept aside ("before-empty-…").
    static func save(_ values: [String: Any], in directory: URL, now: Date = Date()) {
        let today = directory.appendingPathComponent(dayFileName(now))
        if summary(of: values).isEmpty, let previous = read(today), !summary(of: previous).isEmpty {
            try? write(previous, to: directory.appendingPathComponent("before-empty-\(Int(now.timeIntervalSince1970)).plist"))
        }
        try? write(values, to: today)
        prune(directory)
    }

    /// Keeps the newest 14 daily backups and 5 "before-empty" copies.
    static func prune(_ directory: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for (prefix, keep) in [("backup-", keepDays), ("before-empty-", 5)] {
            let files = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".plist") }.sorted(by: >)
            for name in files.dropFirst(keep) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    /// Every backup in `directories`, newest first (the same file in two places counts once).
    static func backups(in directories: [URL]) -> [Backup] {
        var byName: [String: Backup] = [:]
        for directory in directories {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for name in names where name.hasSuffix(".plist") && (name.hasPrefix("backup-") || name.hasPrefix("before-empty-")) {
                let url = directory.appendingPathComponent(name)
                guard let values = read(url) else { continue }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if let existing = byName[name], existing.date >= date { continue }
                byName[name] = Backup(url: url, date: date, values: values)
            }
        }
        return byName.values.sorted { $0.date > $1.date }
    }

    // MARK: - Restoring

    /// Replaces what's saved in `defaults` with a backup.
    static func restore(_ values: [String: Any], into defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where isOwned(key) && values[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in values where isOwned(key) {
            defaults.set(value, forKey: key)
        }
    }

    /// At launch: if this storage has never been used (no saved lists, not marked as used) and a
    /// backup has data, puts the newest such backup back. Then marks the storage as used.
    @discardableResult
    static func restoreIfUntouched(_ defaults: UserDefaults, directories: [URL]) -> Bool {
        defer { defaults.set(true, forKey: initializedKey) }
        guard defaults.object(forKey: initializedKey) == nil,
              !dataKeys.contains(where: { defaults.object(forKey: $0) != nil }),
              let newest = backups(in: directories).first(where: { !$0.summary.isEmpty })
        else { return false }
        restore(newest.values, into: defaults)
        return true
    }
}

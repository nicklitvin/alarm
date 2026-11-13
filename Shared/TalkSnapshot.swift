import Foundation

/// The last few lines of the Talk conversation, saved in the App Group so the Control Center
/// popup can show them wherever iOS runs it.
struct TalkSnapshotMessage: Codable, Hashable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant, event, error }

    var id = UUID()
    let role: Role
    let text: String
}

enum TalkSnapshot {
    private static let key = "talk.snapshot"
    static let limit = 6

    static func save(_ messages: [TalkSnapshotMessage]) {
        let recent = Array(messages.suffix(limit))
        if let data = try? JSONEncoder().encode(recent) {
            AlarmStorage.defaults.set(data, forKey: key)
        }
    }

    static func load() -> [TalkSnapshotMessage] {
        guard let data = AlarmStorage.defaults.data(forKey: key),
              let messages = try? JSONDecoder().decode([TalkSnapshotMessage].self, from: data) else { return [] }
        return messages
    }
}

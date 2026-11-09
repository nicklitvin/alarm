import Foundation

/// Talk preferences, stored in UserDefaults (the settings screen edits them via @AppStorage).
enum TalkSettings {
    static let wakeWordEnabledKey = "talk.wakeWordEnabled"
    static let wakeWordKey = "talk.wakeWord"
    static let speakRepliesKey = "talk.speakReplies"

    static let defaultWakeWord = "Hey Alarm"

    /// Off by default: Live Talk answers everything it hears.
    static var wakeWordEnabled: Bool {
        UserDefaults.standard.bool(forKey: wakeWordEnabledKey)
    }

    static var wakeWord: String {
        let value = UserDefaults.standard.string(forKey: wakeWordKey) ?? defaultWakeWord
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The wake word to enforce right now, or nil when the feature is off.
    static var activeWakeWord: String? {
        guard wakeWordEnabled, !wakeWord.isEmpty else { return nil }
        return wakeWord
    }

    static var speakReplies: Bool {
        UserDefaults.standard.object(forKey: speakRepliesKey) as? Bool ?? true
    }
}

import Foundation

/// A place in the app, as a URL (alarmapp://alarm/<id>, alarmapp://todos, …).
/// Widgets use it to open exactly what was tapped; chat events use it too.
enum DeepLink: Hashable, Sendable {
    case alarms
    case alarm(UUID)
    case timers
    case todos
    case todo(UUID)
    case notes
    case talk
    case note(UUID)

    static let scheme = "alarmapp"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .alarms: components.host = "alarms"
        case .alarm(let id): components.host = "alarm"; components.path = "/" + id.uuidString
        case .timers: components.host = "timers"
        case .todos: components.host = "todos"
        case .todo(let id): components.host = "todo"; components.path = "/" + id.uuidString
        case .notes: components.host = "notes"
        case .talk: components.host = "talk"
        case .note(let id): components.host = "note"; components.path = "/" + id.uuidString
        }
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        let id = UUID(uuidString: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        switch (host, id) {
        case ("alarms", _): self = .alarms
        case ("alarm", let id?): self = .alarm(id)
        case ("alarm", nil): self = .alarms
        case ("timers", _), ("timer", _): self = .timers
        case ("todos", _): self = .todos
        case ("todo", let id?): self = .todo(id)
        case ("todo", nil): self = .todos
        case ("notes", _): self = .notes
        case ("talk", _), ("chat", _): self = .talk
        case ("note", let id?): self = .note(id)
        case ("note", nil): self = .notes
        default: return nil
        }
    }
}

extension UpNextItem {
    /// Where tapping this item in the widget goes.
    var deepLink: DeepLink {
        switch kind {
        case .alarmSoon(let alarm, _), .nextAlarm(let alarm, _): .alarm(alarm.id)
        case .timer: .timers
        case .todo(let todo): .todo(todo.id)
        }
    }
}

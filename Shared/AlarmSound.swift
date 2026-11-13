import Foundation

/// The sound an alarm rings with. "Default" is the system alarm sound; the others are bundled
/// files in App/Sounds (made by Tools/make_sounds.py).
enum AlarmSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case `default`, chime, beacon, pulse, rise, bells

    var id: String { rawValue }

    var name: String {
        switch self {
        case .default: "Default"
        case .chime: "Chime"
        case .beacon: "Beacon"
        case .pulse: "Pulse"
        case .rise: "Rise"
        case .bells: "Bells"
        }
    }

    /// The bundled file, or nil for the system sound.
    var fileName: String? {
        self == .default ? nil : "alarmie-\(rawValue).wav"
    }

    /// Accepts the name ("Chime") or raw value, case-insensitively.
    init?(name: String) {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = Self.allCases.first(where: { $0.rawValue == key || $0.name.lowercased() == key }) else { return nil }
        self = match
    }
}

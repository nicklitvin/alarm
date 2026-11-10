import Foundation

/// A version number like "1.5.0", compared numerically ("1.10.0" is newer than "1.9.2").
struct AppVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    let components: [Int]

    init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        components = numbers
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let a = i < lhs.components.count ? lhs.components[i] : 0
            let b = i < rhs.components.count ? rhs.components[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
    }
}

/// One entry in CHANGELOG.json.
struct Release: Codable, Identifiable, Hashable, Sendable {
    var version: String
    var build: Int?
    var date: String
    var title: String?
    var notes: [String]

    var id: String { version }
    var appVersion: AppVersion? { AppVersion(version) }

    /// "Nov 10, 2026" from "2026-11-10".
    var displayDate: String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return date }
        let month = Calendar.current.shortMonthSymbols[parts[1] - 1]
        return "\(month) \(parts[2]), \(parts[0])"
    }
}

/// The app's version history: newest first.
struct Changelog: Codable, Hashable, Sendable {
    var releases: [Release]

    static func decode(_ data: Data) throws -> Changelog {
        var changelog = try JSONDecoder().decode(Changelog.self, from: data)
        changelog.releases.sort { ($0.appVersion ?? AppVersion("0")!) > ($1.appVersion ?? AppVersion("0")!) }
        return changelog
    }

    var latest: Release? { releases.first }

    /// Releases newer than `version`, newest first.
    func releases(newerThan version: AppVersion) -> [Release] {
        releases.filter { ($0.appVersion ?? version) > version }
    }

    /// Releases after `old` up to and including `new`: what changed between two installed versions.
    func releases(after old: AppVersion, upTo new: AppVersion) -> [Release] {
        releases.filter { guard let v = $0.appVersion else { return false }; return v > old && v <= new }
    }

    /// Combines a fetched changelog with the bundled one, preferring the fetched copy of each version.
    func merged(with other: Changelog?) -> Changelog {
        guard let other else { return self }
        var byVersion: [String: Release] = [:]
        for release in releases { byVersion[release.appVersion?.description ?? release.version] = release }
        for release in other.releases { byVersion[release.appVersion?.description ?? release.version] = release }
        let all = byVersion.values.sorted { ($0.appVersion ?? AppVersion("0")!) > ($1.appVersion ?? AppVersion("0")!) }
        return Changelog(releases: all)
    }
}

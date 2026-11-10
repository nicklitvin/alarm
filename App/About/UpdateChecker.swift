import Foundation
import Observation

/// Checks GitHub for a newer version (the app is installed from Xcode, so the App Store can't
/// update it), and shows "What's New" the first time a new version is opened.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastChecked: Date?
    /// The version history: bundled with the app, plus anything newer found online.
    private(set) var changelog: Changelog
    /// Shown as a sheet: a newer version is available.
    var updatePrompt: Release?
    /// Shown as a sheet: what changed since the version opened last time.
    var whatsNew: [Release] = []

    let installedVersionString: String
    let buildNumber: String
    var installedVersion: AppVersion { AppVersion(installedVersionString) ?? AppVersion("0")! }

    /// Where updates come from. Override with `UpdateFeedURL` / `UpdatePageURL` in Info.plist.
    let feedURL: URL?
    let updatePageURL: URL?

    /// Don't check more often than this automatically.
    private static let checkInterval: TimeInterval = 6 * 3600
    private static let lastCheckKey = "updates.lastCheck"
    private static let skippedKey = "updates.skippedVersion"
    private static let lastSeenKey = "updates.lastSeenVersion"

    @ObservationIgnored private var promptedThisSession = false

    var updateAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        installedVersionString = info["CFBundleShortVersionString"] as? String ?? "0"
        buildNumber = info["CFBundleVersion"] as? String ?? "0"
        feedURL = (info["UpdateFeedURL"] as? String).flatMap(URL.init(string:))
        updatePageURL = (info["UpdatePageURL"] as? String).flatMap(URL.init(string:))
        lastChecked = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date

        if let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let bundled = try? Changelog.decode(data) {
            changelog = bundled
        } else {
            changelog = Changelog(releases: [])
        }
    }

    // MARK: - What's New

    /// After an update, shows the notes for everything since the last version that was opened.
    func showWhatsNewIfUpdated() {
        let defaults = UserDefaults.standard
        defer { defaults.set(installedVersion.description, forKey: Self.lastSeenKey) }

        // A fresh install shows nothing; only real updates do.
        guard let lastSeen = defaults.string(forKey: Self.lastSeenKey).flatMap(AppVersion.init),
              lastSeen < installedVersion else { return }
        let notes = changelog.releases(after: lastSeen, upTo: installedVersion)
        if !notes.isEmpty { whatsNew = notes }
    }

    // MARK: - Checking

    /// Checks unless it already did recently.
    func checkIfNeeded() {
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval {
            // Still show a known pending update once per launch.
            if case .available(let release) = status { prompt(release) }
            return
        }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard let feedURL else {
            status = .failed("No update source is configured.")
            return
        }
        guard status != .checking else { return }
        status = .checking

        do {
            var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let remote = try Changelog.decode(data)

            changelog = changelog.merged(with: remote)
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Self.lastCheckKey)

            if let latest = remote.latest, let version = latest.appVersion, version > installedVersion {
                status = .available(latest)
                if userInitiated || !isSkipped(version) { prompt(latest, force: userInitiated) }
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed(userInitiated ? "Couldn't reach GitHub. Check your connection and try again." : "Couldn't check for updates.")
        }
    }

    /// Releases you don't have yet, newest first.
    var pendingReleases: [Release] {
        changelog.releases(newerThan: installedVersion)
    }

    func skip(_ release: Release) {
        UserDefaults.standard.set(release.version, forKey: Self.skippedKey)
        updatePrompt = nil
    }

    private func isSkipped(_ version: AppVersion) -> Bool {
        guard let skipped = UserDefaults.standard.string(forKey: Self.skippedKey).flatMap(AppVersion.init) else { return false }
        return version <= skipped
    }

    private func prompt(_ release: Release, force: Bool = false) {
        guard force || (!promptedThisSession && whatsNew.isEmpty) else { return }
        if !force, let version = release.appVersion, isSkipped(version) { return }
        promptedThisSession = true
        updatePrompt = release
    }
}

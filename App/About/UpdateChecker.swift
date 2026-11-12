import Foundation
import Observation

/// Checks the App Store for a newer version and offers to open it there, and shows "What's New"
/// the first time a new version is opened. Copies installed from Xcode aren't on the App Store,
/// so for those the check simply says so (no prompts).
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        /// This app isn't listed on the App Store (e.g. installed from Xcode).
        case notOnAppStore
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastChecked: Date?
    /// The version history bundled with the app, plus the App Store's notes for a newer version.
    private(set) var changelog: Changelog
    /// Shown as a sheet: a newer version is available.
    var updatePrompt: Release?
    /// Shown as a sheet: what changed since the version opened last time.
    var whatsNew: [Release] = []

    let installedVersionString: String
    let buildNumber: String
    var installedVersion: AppVersion { AppVersion(installedVersionString) ?? AppVersion("0")! }

    /// The app's App Store page, once found.
    private(set) var appStoreURL: URL?
    private let bundleID: String

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
        bundleID = Bundle.main.bundleIdentifier ?? ""
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
        guard status != .checking else { return }
        guard let url = AppStoreLookup.url(bundleID: bundleID, countryCode: Locale.current.region?.identifier) else {
            status = .failed("Couldn't check for updates.")
            return
        }
        status = .checking

        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Self.lastCheckKey)

            guard let result = try AppStoreLookup.parse(data) else {
                status = .notOnAppStore
                return
            }
            appStoreURL = result.storeURL
            let latest = result.release
            if let version = latest.appVersion, version > installedVersion {
                changelog = changelog.merged(with: Changelog(releases: [latest]))
                status = .available(latest)
                if userInitiated || !isSkipped(version) { prompt(latest, force: userInitiated) }
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed(userInitiated ? "Couldn't reach the App Store. Check your connection and try again." : "Couldn't check for updates.")
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

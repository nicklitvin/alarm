import Foundation

/// Looks the app up on the App Store (Apple's public iTunes lookup service) to find the latest
/// published version, its release notes and its store page.
enum AppStoreLookup {
    struct Result: Equatable {
        let release: Release
        let storeURL: URL?
    }

    /// e.g. https://itunes.apple.com/lookup?bundleId=com.example.alarm&country=us
    static func url(bundleID: String, countryCode: String?) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            // Without a country the US store is used; the app may only be listed in the user's region.
            countryCode.map { URLQueryItem(name: "country", value: $0.lowercased()) },
            // Apple caches lookups for a while; this asks for a fresh answer.
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 / 300))),
        ].compactMap { $0 }
        return components?.url
    }

    /// Nil when the app isn't on the App Store (yet), e.g. when it was installed from Xcode.
    static func parse(_ data: Data) throws -> Result? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let entry = response.results.first else { return nil }
        let notes = (entry.releaseNotes ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "•-* ")) }
            .filter { !$0.isEmpty }
        let release = Release(
            version: entry.version,
            build: nil,
            date: String((entry.currentVersionReleaseDate ?? "").prefix(10)),
            title: "App Store",
            notes: notes.isEmpty ? ["Bug fixes and improvements."] : notes
        )
        return Result(release: release, storeURL: entry.trackViewUrl.flatMap(URL.init(string:)))
    }

    private struct Response: Decodable {
        let resultCount: Int
        let results: [Entry]
    }

    private struct Entry: Decodable {
        let version: String
        let releaseNotes: String?
        let trackViewUrl: String?
        let currentVersionReleaseDate: String?
    }
}

import UIKit

/// The pictures pasted into notes, saved as JPEG files next to the notes (in the App Group
/// container, or the app's own when that isn't available). Notes refer to them by ID
/// (`NoteImageText`). Pictures no note uses any more (including Recently Deleted) are removed
/// at launch.
@MainActor
enum NoteImageStore {
    private static let cache = NSCache<NSString, UIImage>()

    static var directory: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AlarmStorage.appGroupIdentifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NoteImages", isDirectory: true)
    }

    private static func url(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).jpg") }

    /// Saves a pasted picture (scaled down to at most 2048 pt on its long side). Nil if it couldn't be saved.
    static func save(_ image: UIImage) -> UUID? {
        let scaled = scaledDown(image, maxSide: 2048)
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        let id = UUID()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(id), options: .atomic)
        } catch {
            print("Alarmie: couldn't save a note picture: \(error)")
            return nil
        }
        cache.setObject(scaled, forKey: id.uuidString as NSString)
        return id
    }

    static func image(_ id: UUID) -> UIImage? {
        if let cached = cache.object(forKey: id.uuidString as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url(id).path) else { return nil }
        cache.setObject(image, forKey: id.uuidString as NSString)
        return image
    }

    /// Removes picture files that no note refers to.
    static func removeUnused(keeping used: Set<UUID>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".jpg") {
            guard let id = UUID(uuidString: String(name.dropLast(4))), !used.contains(id) else { continue }
            try? FileManager.default.removeItem(at: url(id))
        }
    }

    private static func scaledDown(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

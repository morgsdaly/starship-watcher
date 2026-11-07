import CryptoKit
import ImageIO
import SwiftUI
import UIKit

/// Loads remote images once, downsampled off the main thread, and shares them between views.
/// Launch Library images are often 4096px+ (~40MB decoded); `AsyncImage` has no cache, so every
/// tab's backdrop downloaded and decoded its own full-size copy.
///
/// Downsampled images are also written to the Caches directory, so after a cold launch the
/// backdrop can be shown on the first frame instead of being downloaded again.
actor BackdropImageLoader {
    static let shared = BackdropImageLoader()

    // NSCache is thread-safe, so reads can skip the actor hop.
    private nonisolated(unsafe) let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private static let diskDirectory = URL.cachesDirectory.appending(path: "Backdrops", directoryHint: .isDirectory)
    private static let diskLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// Memory, then disk. Synchronous so views can show the image on their first frame.
    nonisolated func cachedImage(for url: URL) -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let data = try? Data(contentsOf: Self.diskURL(for: url)),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    func image(for url: URL, maxPixelSize: CGFloat = 1400) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = Self.downsample(data, maxPixelSize: maxPixelSize) else { return nil }
            Self.writeToDisk(image, for: url)
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL)
        }
        return image
    }

    private nonisolated static func diskURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return diskDirectory.appending(path: "\(name).jpg")
    }

    private nonisolated static func writeToDisk(_ image: UIImage, for url: URL) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        try? data.write(to: diskURL(for: url), options: [.atomic])

        // Drop backdrops for flights we haven't shown in a while.
        let cutoff = Date.now.addingTimeInterval(-diskLifetime)
        let files = (try? fileManager.contentsOfDirectory(
            at: diskDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private nonisolated static func downsample(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

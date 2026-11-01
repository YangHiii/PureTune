import AVFoundation
import UIKit

@MainActor
final class ArtworkStore {
    static let shared = ArtworkStore()

    private let cache = NSCache<NSString, UIImage>()
    private var loadingTasks: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 120
    }

    func cachedArtwork(for fileName: String) -> UIImage? {
        cache.object(forKey: fileName as NSString)
    }

    func artwork(for song: Song, url: URL) async -> UIImage? {
        let key = song.fileName
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        if let existing = loadingTasks[key] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            await Self.loadArtwork(from: url)
        }
        loadingTasks[key] = task

        let image = await task.value
        loadingTasks[key] = nil

        if let image {
            cache.setObject(image, forKey: key as NSString)
        }
        return image
    }

    nonisolated private static func loadArtwork(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)

        guard let metadata = try? await asset.load(.commonMetadata) else {
            return nil
        }

        for item in metadata where item.commonKey == .commonKeyArtwork {
            guard let data = try? await item.load(.dataValue) else { continue }
            return downsample(data)
        }

        return nil
    }

    nonisolated private static func downsample(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }

        let maximumDimension: CGFloat = 1_200
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maximumDimension else { return image }

        let scale = maximumDimension / longestSide
        let targetSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

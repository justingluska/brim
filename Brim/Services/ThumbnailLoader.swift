import SwiftUI
import UIKit
import CapKit

/// Thumbnails come from an authenticated server URL that redirects to
/// object storage, so `AsyncImage` cannot load them. This loader sends the
/// bearer key, follows the redirect, and caches decoded images in memory
/// keyed by the server's `thumbnailCacheKey` (which changes when the cap does).
@MainActor
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 400
    }

    func image(for cap: CapSummary, client: CapClient) async -> UIImage? {
        guard let urlString = cap.thumbnailUrl, let url = URL(string: urlString) else { return nil }
        let key = cap.thumbnailCacheKey ?? urlString
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if let task = inflight[key] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let data = try? await client.thumbnailData(from: url),
                  let image = UIImage(data: data) else { return nil }
            // Downsample once, off the main thread, so lists scroll smoothly.
            return await image.byPreparingThumbnail(ofSize: CGSize(width: 640, height: 360)) ?? image
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        if let result { cache.setObject(result, forKey: key as NSString) }
        return result
    }
}

struct CapThumbnail: View {
    let cap: CapSummary
    let client: CapClient?
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle().fill(Theme.Colors.filler)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if !cap.isReady {
                        VStack(spacing: 6) {
                            ProgressView()
                            Text(cap.upload?.phase == .error ? "Failed" : "Processing…")
                                .font(.caption2).foregroundStyle(Theme.Colors.inkSoft)
                        }
                    } else {
                        Image(systemName: "play.rectangle").font(.title2).foregroundStyle(Theme.Colors.inkFaint)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.thumbnailRadius, style: .continuous))
        .task(id: cap.thumbnailCacheKey ?? cap.thumbnailUrl ?? cap.id) {
            guard let client else { return }
            image = await ThumbnailLoader.shared.image(for: cap, client: client)
        }
    }
}

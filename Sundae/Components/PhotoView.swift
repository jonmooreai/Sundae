import SwiftUI
import UIKit

/// UIImage is immutable and documented thread-safe, so handing a decoded one back from a
/// background task is fine. The wrapper says so to the compiler.
struct DecodedImage: @unchecked Sendable {
    let uiImage: UIImage
}

@MainActor
enum ImageCache {
    private static let cache: NSCache<NSNumber, UIImage> = {
        let c = NSCache<NSNumber, UIImage>()
        c.countLimit = 200
        return c
    }()

    static func image(for data: Data) async -> UIImage? {
        let key = NSNumber(value: data.hashValue)
        if let hit = cache.object(forKey: key) { return hit }
        let decoded = await Task.detached(priority: .userInitiated) { () -> DecodedImage? in
            guard let image = UIImage(data: data)?.preparingForDisplay() else { return nil }
            return DecodedImage(uiImage: image)
        }.value
        if let decoded { cache.setObject(decoded.uiImage, forKey: key) }
        return decoded?.uiImage
    }
}

/// Draws any `PhotoSource` filling its container, clipped. The container decides the size.
struct PhotoView: View {
    let source: PhotoSource

    var body: some View {
        Rectangle()
            .fill(Theme.surface)
            .overlay { content }
            .clipped()
    }

    @ViewBuilder
    private var content: some View {
        switch source {
        case .remote(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Theme.surface
                }
            }
        case .data(let data):
            DataImage(data: data)
        case .placeholder(let seed):
            PlaceholderPhoto(seed: seed)
        }
    }
}

private struct DataImage: View {
    let data: Data
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.surface
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: data) {
            image = await ImageCache.image(for: data)
        }
    }
}

/// Soft gradient stand-in used by seed data and previews.
struct PlaceholderPhoto: View {
    let seed: Int

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SeedColor.gradient(seed)
                Circle()
                    .fill(.white.opacity(0.28))
                    .frame(width: geo.size.width * 0.38)
                    .position(
                        x: geo.size.width * (0.25 + 0.5 * SeedColor.hue(seed + 3)),
                        y: geo.size.height * (0.25 + 0.5 * SeedColor.hue(seed + 11))
                    )
            }
        }
    }
}

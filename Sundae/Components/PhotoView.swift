import SwiftUI
import UIKit

/// UIImage is immutable and documented thread-safe, so handing a decoded one back from a
/// background task is fine. The wrapper says so to the compiler.
struct DecodedImage: @unchecked Sendable {
    let uiImage: UIImage
}

@MainActor
enum ImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()

    /// A photo or avatar, from the server or the phone, decoded no larger than `size`
    /// (ImageDownsampler). Never a full-size decode.
    static func image(for source: PhotoSource, size: PixelSize) async -> UIImage? {
        let name: String
        switch source {
        case .remote(let url): name = url.absoluteString
        case .data(let data): name = "data:\(data.hashValue)"
        case .placeholder: return nil
        }
        let key = "\(name) \(size.width)x\(size.height)" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let data: Data
        switch source {
        case .remote(let url):
            guard let result = try? await URLSession.shared.data(from: url),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            data = result.0
        case .data(let local):
            data = local
        case .placeholder:
            return nil
        }
        let decoded = await Task.detached(priority: .userInitiated) { () -> DecodedImage? in
            guard let image = ImageDownsampler.decode(data, filling: size) else { return nil }
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
        case .remote, .data:
            DownsampledImage(source: source)
        case .placeholder(let seed):
            PlaceholderPhoto(seed: seed)
        }
    }
}

/// Loads at the size it is drawn, and again only if that size grows past the next step.
private struct DownsampledImage: View {
    let source: PhotoSource
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var shown: PhotoSource?

    private struct Request: Equatable {
        let source: PhotoSource
        let size: PixelSize
    }

    var body: some View {
        GeometryReader { geo in
            let request = Request(source: source, size: PixelSize(geo.size, scale: displayScale))
            ZStack {
                Theme.surface
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: request) {
                // A different photo never shows the last one while it loads.
                if shown != request.source { image = nil }
                guard !request.size.isEmpty else { return }
                let loaded = await ImageCache.image(for: request.source, size: request.size)
                guard !Task.isCancelled, let loaded else { return }
                image = loaded
                shown = request.source
            }
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

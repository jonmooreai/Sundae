import Foundation
import ImageIO
import UIKit

/// The size a photo is drawn at, in device pixels, rounded up to a step so small layout
/// changes reuse one decode. Never more than the decode cap on either side.
struct PixelSize: Hashable, Sendable {
    var width: Int
    var height: Int

    static let step = 64

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize, scale: CGFloat) {
        width = Self.pixels(size.width * scale)
        height = Self.pixels(size.height * scale)
    }

    var isEmpty: Bool { width <= 0 || height <= 0 }

    private static func pixels(_ points: CGFloat) -> Int {
        guard points.isFinite, points > 0 else { return 0 }
        let capped = Int(min(points.rounded(.up), CGFloat(ImageDownsampler.maxPixelSize)))
        return min((capped + step - 1) / step * step, ImageDownsampler.maxPixelSize)
    }
}

/// Decodes photos and avatars from the server no larger than they are drawn.
///
/// A full-size decode allocates width x height x 4 bytes whatever the view, so one huge
/// image could take the app down. ImageIO's thumbnail path decodes straight to the smaller
/// size, and anything far larger than a photo the app makes is refused before decoding.
enum ImageDownsampler {
    /// The longest edge ever decoded, whatever the view.
    static let maxPixelSize = 2048
    /// Far beyond any photo the app makes (2048 px) or any avatar (600 px).
    static let maxSourceSide = 8192
    static let maxSourcePixels = 40_000_000

    nonisolated static func isTooLarge(width: Int, height: Int) -> Bool {
        width <= 0 || height <= 0 || width > maxSourceSide || height > maxSourceSide || width * height > maxSourcePixels
    }

    /// The long edge to decode at: enough to fill `view` edge to edge, never more than the
    /// source has, never more than the cap.
    nonisolated static func longEdge(sourceWidth: Int, sourceHeight: Int, filling view: PixelSize) -> Int {
        let sourceLong = max(sourceWidth, sourceHeight, 1)
        guard sourceWidth > 0, sourceHeight > 0, !view.isEmpty else { return min(sourceLong, maxPixelSize) }
        let fill = max(Double(view.width) / Double(sourceWidth), Double(view.height) / Double(sourceHeight))
        let needed = min((Double(sourceLong) * fill).rounded(.up), Double(sourceLong))
        return max(1, min(Int(needed), maxPixelSize))
    }

    /// Nil when the bytes are not an image, or are too large to open safely.
    nonisolated static func decode(_ data: Data, filling view: PixelSize) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions as CFDictionary) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              !isTooLarge(width: width, height: height) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge(sourceWidth: width, sourceHeight: height, filling: view),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

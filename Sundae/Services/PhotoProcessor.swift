import Foundation
import ImageIO
import UIKit

struct ProcessedPhoto: Sendable {
    var data: Data
    var width: Int
    var height: Int
}

/// Re-encodes a picked photo for upload: 2048 px long edge, JPEG, no metadata.
///
/// Drawing through ImageIO's thumbnail path produces a fresh bitmap, so EXIF, GPS and every
/// other tag from the original is dropped on device before anything leaves the phone. The
/// server strips again as a second line. HEIC, Live Photo stills and portrait depth images
/// all come through this path as plain pixels.
enum PhotoProcessor {
    static let maxLongEdge = 2048
    static let jpegQuality: CGFloat = 0.85

    nonisolated static func process(_ data: Data) -> ProcessedPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLongEdge,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        guard let jpeg = image.jpegData(compressionQuality: jpegQuality) else { return nil }
        return ProcessedPhoto(data: jpeg, width: cgImage.width, height: cgImage.height)
    }

    /// Runs the re-encode off the main actor.
    static func processInBackground(_ data: Data) async -> ProcessedPhoto? {
        await Task.detached(priority: .userInitiated) { process(data) }.value
    }
}

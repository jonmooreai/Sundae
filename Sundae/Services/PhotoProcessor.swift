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

    nonisolated static func process(_ data: Data, maxPixelSize: Int = maxLongEdge) -> ProcessedPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        guard let jpeg = image.jpegData(compressionQuality: jpegQuality) else { return nil }
        return ProcessedPhoto(data: jpeg, width: cgImage.width, height: cgImage.height)
    }

    /// Runs the re-encode off the main actor.
    static func processInBackground(_ data: Data, maxPixelSize: Int = maxLongEdge) async -> ProcessedPhoto? {
        await Task.detached(priority: .userInitiated) { process(data, maxPixelSize: maxPixelSize) }.value
    }

    /// Profile photos: the center square, 600 px.
    nonisolated static func processAvatar(_ data: Data) -> ProcessedPhoto? {
        guard let photo = process(data, maxPixelSize: 1200), let image = UIImage(data: photo.data) else { return nil }
        let side = min(image.size.width, image.size.height)
        let origin = CGPoint(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2)
        guard let cg = image.cgImage?.cropping(to: CGRect(origin: origin, size: CGSize(width: side, height: side))) else { return nil }
        let target = CGFloat(600)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: {
            let f = UIGraphicsImageRendererFormat.default()
            f.scale = 1
            return f
        }())
        let square = renderer.image { _ in
            UIImage(cgImage: cg).draw(in: CGRect(x: 0, y: 0, width: target, height: target))
        }
        guard let jpeg = square.jpegData(compressionQuality: jpegQuality) else { return nil }
        return ProcessedPhoto(data: jpeg, width: Int(target), height: Int(target))
    }

    static func processAvatarInBackground(_ data: Data) async -> ProcessedPhoto? {
        await Task.detached(priority: .userInitiated) { processAvatar(data) }.value
    }
}

import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit

/// Turns, recolors and crops a photo with Core Image, on the phone. The editor shows the photo
/// turned and recolored under a crop frame; posting renders the same steps at full size and
/// sends the result through `PhotoProcessor`, so it leaves sized and with nothing but pixels.
enum PhotoEditing {
    /// One context for every render. Core Image contexts are safe to share between threads.
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The photo turned and recolored, its corner at zero: what sits under the editor's frame.
    nonisolated static func adjusted(_ image: CIImage, _ edits: PhotoEdits) -> CIImage {
        var out = image
        switch ((edits.quarterTurns % 4) + 4) % 4 {
        case 1: out = out.oriented(.right)
        case 2: out = out.oriented(.down)
        case 3: out = out.oriented(.left)
        default: break
        }
        out = out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
        let extent = out.extent
        if edits.brightness != 0 || edits.contrast != 0 || edits.saturation != 0 {
            let colors = CIFilter.colorControls()
            colors.inputImage = out
            // Gentle at the ends of the sliders: a photo, not a poster.
            colors.brightness = Float(edits.brightness * 0.22)
            colors.contrast = Float(1 + edits.contrast * 0.35)
            colors.saturation = Float(1 + edits.saturation * 0.9)
            out = colors.outputImage ?? out
        }
        if edits.warmth != 0 {
            // Treating the light as bluer than it was warms the photo, and the other way cools it.
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = out
            temperature.neutral = CIVector(x: CGFloat(6500 + edits.warmth * 2500), y: 0)
            temperature.targetNeutral = CIVector(x: 6500, y: 0)
            out = temperature.outputImage ?? out
        }
        return out.cropped(to: extent)
    }

    /// Width over height once turned.
    nonisolated static func turnedSize(width: Int, height: Int, quarterTurns: Int) -> CGSize {
        quarterTurns % 2 == 0 ? CGSize(width: width, height: height) : CGSize(width: height, height: width)
    }

    /// The part of a turned photo of this size that the crop keeps, in Core Image's space
    /// (origin at the bottom left). The largest rectangle of the chosen shape, made smaller by
    /// the zoom, and moved within the room left over.
    nonisolated static func cropRect(in size: CGSize, _ edits: PhotoEdits) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let shape = edits.aspect.ratio ?? size.width / size.height
        var width = size.width
        var height = size.height
        if size.width / size.height > shape { width = size.height * shape } else { height = size.width / shape }
        let zoom = CGFloat(max(1, edits.zoom))
        width /= zoom
        height /= zoom
        let roomX = size.width - width
        let roomY = size.height - height
        let x = roomX / 2 + CGFloat(clamp(edits.offsetX)) * roomX / 2
        let fromTop = roomY / 2 + CGFloat(clamp(edits.offsetY)) * roomY / 2
        return CGRect(x: x, y: size.height - height - fromTop, width: width, height: height)
    }

    nonisolated static func clamp(_ value: Double) -> Double { min(1, max(-1, value)) }

    /// The editor's picture: the photo at a size that redraws quickly as the sliders move.
    nonisolated static func previewBase(_ data: Data, maxPixelSize: Int = 1400) -> CIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return CIImage(cgImage: image)
    }

    /// The preview turned and recolored, ready to draw.
    nonisolated static func preview(_ base: CIImage, _ edits: PhotoEdits) -> UIImage? {
        let image = adjusted(base, edits)
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// The finished photo: turned, recolored and cropped from the full-size original, then sized
    /// and stripped like every other photo.
    nonisolated static func render(_ data: Data, _ edits: PhotoEdits) -> ProcessedPhoto? {
        guard let input = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let image = adjusted(input, edits)
        let crop = cropRect(in: image.extent.size, edits).integral.intersection(image.extent)
        guard !crop.isEmpty, let cg = context.createCGImage(image, from: crop),
              let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.95) else { return nil }
        return PhotoProcessor.process(jpeg)
    }

    static func renderInBackground(_ data: Data, _ edits: PhotoEdits) async -> ProcessedPhoto? {
        await Task.detached(priority: .userInitiated) { render(data, edits) }.value
    }
}

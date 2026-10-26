import Foundation
import Testing
import UIKit
@testable import Sundae

/// Photos and avatars from the server are decoded at the size they are drawn, never in full.
struct ImageDownsamplerTests {
    private func jpeg(width: Int, height: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }

    @Test func viewSizesRoundUpToAStepAndStopAtTheCap() {
        #expect(PixelSize(CGSize(width: 36, height: 36), scale: 3) == PixelSize(width: 128, height: 128))
        #expect(PixelSize(CGSize(width: 64, height: 10), scale: 1) == PixelSize(width: 64, height: 64))
        #expect(PixelSize(CGSize(width: 5000, height: 1e12), scale: 3) == PixelSize(width: 2048, height: 2048))
        #expect(PixelSize(CGSize(width: 0, height: 40), scale: 3).isEmpty)
        #expect(PixelSize(CGSize(width: CGFloat.infinity, height: 40), scale: 3).isEmpty)
    }

    @Test func theDecodeFillsTheViewWithoutGoingOverTheSourceOrTheCap() {
        // A square view over a wide photo needs the photo's height to cover it.
        #expect(ImageDownsampler.longEdge(sourceWidth: 2048, sourceHeight: 1024, filling: PixelSize(width: 512, height: 512)) == 1024)
        #expect(ImageDownsampler.longEdge(sourceWidth: 600, sourceHeight: 600, filling: PixelSize(width: 128, height: 128)) == 128)
        #expect(ImageDownsampler.longEdge(sourceWidth: 600, sourceHeight: 600, filling: PixelSize(width: 2048, height: 2048)) == 600)
        #expect(ImageDownsampler.longEdge(sourceWidth: 8000, sourceHeight: 100, filling: PixelSize(width: 2048, height: 2048)) == 2048)
    }

    @Test func hugeOrEmptySourcesAreRefused() {
        #expect(!ImageDownsampler.isTooLarge(width: 2048, height: 1536))
        #expect(!ImageDownsampler.isTooLarge(width: 600, height: 600))
        #expect(ImageDownsampler.isTooLarge(width: 60_000, height: 60_000))
        #expect(ImageDownsampler.isTooLarge(width: 9000, height: 10))
        #expect(ImageDownsampler.isTooLarge(width: 8000, height: 8000))
        #expect(ImageDownsampler.isTooLarge(width: 0, height: 100))
    }

    @Test func aPhotoIsDecodedAtTheSizeItIsDrawn() throws {
        let data = try jpeg(width: 1600, height: 1200)
        let image = try #require(ImageDownsampler.decode(data, filling: PixelSize(width: 128, height: 128)))
        let cgImage = try #require(image.cgImage)
        #expect(max(cgImage.width, cgImage.height) <= 171)
        #expect(min(cgImage.width, cgImage.height) >= 120)
    }

    @Test func anImageTooLargeToOpenSafelyIsNotDecoded() throws {
        let data = try jpeg(width: 9000, height: 8)
        #expect(ImageDownsampler.decode(data, filling: PixelSize(width: 128, height: 128)) == nil)
        #expect(ImageDownsampler.decode(Data("not an image".utf8), filling: PixelSize(width: 128, height: 128)) == nil)
    }
}

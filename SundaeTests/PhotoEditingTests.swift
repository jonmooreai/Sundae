import Foundation
import Testing
import UIKit
@testable import Sundae

/// Photos keep the order they were picked in, can be moved, edited, and put back as they were.
@MainActor
struct PhotoEditingTests {
    /// A plain JPEG of this size, made on the spot.
    private func jpeg(_ width: Int, _ height: Int, color: UIColor = .systemTeal) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    @Test func theCropIsTheLargestOfItsShapeMovedWithinItsRoom() {
        let size = CGSize(width: 4000, height: 3000)
        var edits = PhotoEdits()
        #expect(PhotoEditing.cropRect(in: size, edits) == CGRect(x: 0, y: 0, width: 4000, height: 3000))
        edits.aspect = .square
        #expect(PhotoEditing.cropRect(in: size, edits) == CGRect(x: 500, y: 0, width: 3000, height: 3000))
        edits.zoom = 2
        #expect(PhotoEditing.cropRect(in: size, edits) == CGRect(x: 1250, y: 750, width: 1500, height: 1500))
        // All the way right and down: down is the bottom, which is where Core Image starts counting.
        edits.offsetX = 1
        edits.offsetY = 1
        #expect(PhotoEditing.cropRect(in: size, edits) == CGRect(x: 2500, y: 0, width: 1500, height: 1500))
        edits.offsetX = -3
        #expect(PhotoEditing.cropRect(in: size, edits).minX == 0, "never past the edge")
    }

    @Test func renderingTurnsAndCrops() throws {
        let data = jpeg(400, 300)
        var edits = PhotoEdits()
        edits.quarterTurns = 1
        let turned = try #require(PhotoEditing.render(data, edits))
        #expect(turned.width == 300 && turned.height == 400)
        edits.aspect = .square
        edits.warmth = 0.5
        edits.brightness = -0.3
        let square = try #require(PhotoEditing.render(data, edits))
        #expect(square.width == 300 && square.height == 300)
    }

    @Test func straighteningKeepsTheSizeAndFillsTheCorners() throws {
        let data = jpeg(400, 300, color: .systemRed)
        var edits = PhotoEdits()
        edits.straighten = 7.5
        let turned = try #require(PhotoEditing.render(data, edits))
        #expect(turned.width == 400 && turned.height == 300, "same size")
        // A corner pixel is the photo's red, never an empty edge.
        let image = try #require(UIImage(data: turned.data)?.cgImage)
        let corner = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        #expect(drawn)
        #expect(pixel[0] > 180 && pixel[3] > 250, "the corner is filled with the photo")
    }

    @Test func editsSavedBeforeStraighteningStillOpen() throws {
        let old = #"{"quarterTurns":1,"aspect":"square","zoom":1.5,"offsetX":0,"offsetY":0,"brightness":0.2,"contrast":0,"saturation":0,"warmth":0}"#
        let edits = try JSONDecoder().decode(PhotoEdits.self, from: Data(old.utf8))
        #expect(edits.quarterTurns == 1 && edits.aspect == .square && edits.straighten == 0 && edits.brightness == 0.2)
    }

    /// A JPEG with a little XMP carrying these words, as an image maker would write them.
    private func labelled(_ words: String) -> Data {
        let xmp = Data("<x:xmpmeta><rdf:Description \(words)/></x:xmpmeta>".utf8)
        var marker = Data([0xFF, 0xE1])
        let length = xmp.count + 2 + 29
        marker.append(contentsOf: [UInt8(length >> 8), UInt8(length & 0xFF)])
        marker.append(Data("http://ns.adobe.com/xap/1.0/\0".utf8))
        marker.append(xmp)
        var data = jpeg(40, 30)
        data.insert(contentsOf: marker, at: 2)
        return data
    }

    @Test func aLabelInTheFileSaysMadeWithAI() {
        #expect(!MadeWithAI.detect(in: jpeg(40, 30)), "an ordinary photo")
        #expect(MadeWithAI.detect(in: labelled(#"Iptc4xmpExt:DigitalSourceType="http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia""#)))
        #expect(MadeWithAI.detect(in: labelled(#"DigitalSourceType="compositeWithTrainedAlgorithmicMedia""#)), "partly made")
        #expect(MadeWithAI.detect(in: labelled(#"c2pa claim_generator="OpenAI-API c2pa-rs""#)), "Content Credentials from OpenAI")
        #expect(!MadeWithAI.detect(in: labelled(#"dc:description="a photo of the OpenAI office""#)), "a maker named outside Content Credentials")
        #expect(!MadeWithAI.detect(in: labelled(#"DigitalSourceType="digitalCapture""#)), "a camera's own label")
    }

    @Test func thePhotoKeepsTheNoteButNotTheLabel() async throws {
        let compose = ComposeStore(api: MockSundaeAPI(clock: SundayClock()))
        let original = labelled(#"DigitalSourceType="trainedAlgorithmicMedia""#)
        await compose.importLibraryData(original, assetID: "ai", takenAt: nil)
        await compose.importLibraryData(jpeg(40, 30), assetID: "camera", takenAt: nil)
        #expect(compose.draft.photos.map(\.madeWithAI) == [true, false])
        // What goes up is pixels only: the label itself is stripped with everything else.
        guard case .data(let sent) = compose.draft.photos[0].source else { Issue.record("not data"); return }
        #expect(!MadeWithAI.detect(in: sent))
        // And it survives an edit.
        var edits = PhotoEdits()
        edits.warmth = 0.3
        let rendered = try #require(PhotoEditing.render(sent, edits))
        compose.applyEdits(to: compose.draft.photos[0].id, edits: edits, rendered: rendered)
        #expect(compose.draft.photos[0].madeWithAI)
    }

    @Test func photosKeepTheOrderTheyWerePicked() async throws {
        let compose = ComposeStore(api: MockSundaeAPI(clock: SundayClock()))
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 9_000)
        // Picked late first: it stays first, whatever the dates say.
        await compose.importLibraryData(jpeg(40, 30), assetID: "late", takenAt: late)
        await compose.importLibraryData(jpeg(40, 30), assetID: "early", takenAt: early)
        compose.append(ProcessedPhoto(data: jpeg(40, 30), width: 40, height: 30), takenAt: early)
        let ids = compose.draft.photos.map(\.id)
        #expect(ids[0] == compose.libraryPhotoIDs["late"] && ids[1] == compose.libraryPhotoIDs["early"])

        // Tapped again in another order: the camera roll photos follow it, the third stays put.
        compose.orderLibraryPhotos(["early", "late"])
        #expect(compose.draft.photos.map(\.id) == [ids[1], ids[0], ids[2]])

        // Dropped onto the first photo in the strip, the last one takes its place.
        compose.movePhoto(ids[2], to: ids[1])
        #expect(compose.draft.photos.map(\.id) == [ids[2], ids[1], ids[0]])
    }

    @Test func anEditCanBePutBack() async throws {
        let compose = ComposeStore(api: MockSundaeAPI(clock: SundayClock()))
        await compose.importLibraryData(jpeg(400, 300), assetID: "a", takenAt: nil)
        let first = try #require(compose.draft.photos.first)
        var edits = PhotoEdits()
        edits.aspect = .square
        let loaded = await compose.editableData(for: first)
        let original = try #require(loaded)
        let rendered = try #require(PhotoEditing.render(original, edits))
        compose.applyEdits(to: first.id, edits: edits, rendered: rendered)

        let edited = try #require(compose.draft.photos.first)
        #expect(edited.id != first.id, "a new id, so nothing half sent is posted in its place")
        #expect(compose.libraryPhotoIDs["a"] == edited.id)
        #expect(edited.width == 300 && edited.height == 300)
        #expect(edited.original?.source == first.source)
        #expect(edited.replaces == nil, "nothing posted to replace")

        compose.applyEdits(to: edited.id, edits: PhotoEdits(), rendered: nil)
        let back = try #require(compose.draft.photos.first)
        #expect(back.source == first.source && back.width == 400 && back.edits == nil && back.original == nil)
    }

    @Test func anEditedPostedPhotoSaysWhatItReplaces() async throws {
        let compose = ComposeStore(api: MockSundaeAPI(clock: SundayClock()))
        let posted = DraftPhoto(id: "p_posted", source: .remote(URL(string: "https://example.com/p.jpg")!), width: 400, height: 300)
        compose.draft.photos = [posted]
        compose.applyEdits(to: posted.id, edits: { var e = PhotoEdits(); e.contrast = 0.4; return e }(),
                           rendered: ProcessedPhoto(data: jpeg(400, 300), width: 400, height: 300))
        let edited = try #require(compose.draft.photos.first)
        #expect(edited.replaces == "p_posted")
        compose.applyEdits(to: edited.id, edits: PhotoEdits(), rendered: nil)
        #expect(compose.draft.photos.first?.id == "p_posted", "put back, it is the posted photo again")
        #expect(compose.draft.photos.first?.replaces == nil)
    }

    @Test func aDraftFromBeforeEditsStillOpens() throws {
        let old = #"{"id":"x","source":{"placeholder":{"seed":1}},"width":10,"height":10}"#
        let photo = try JSONDecoder().decode(DraftPhoto.self, from: Data(old.utf8))
        #expect(photo.edits == nil && photo.original == nil && photo.replaces == nil)
    }
}

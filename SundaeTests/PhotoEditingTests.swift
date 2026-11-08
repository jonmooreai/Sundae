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

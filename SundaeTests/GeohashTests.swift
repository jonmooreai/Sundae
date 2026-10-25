import Foundation
import Testing
@testable import Sundae

/// The cell is the only thing about location that leaves the phone, so its size and stability matter.
struct GeohashTests {
    @Test func matchesTheReferenceVector() {
        #expect(Geohash.encode(latitude: 57.64911, longitude: 10.40744, precision: 11) == "u4pruydqqvj")
    }

    @Test func sixCharactersIsANeighborhood() {
        #expect(Geohash.encode(latitude: 37.7749, longitude: -122.4194, precision: 6) == "9q8yyk")
        #expect(Geohash.encode(latitude: 37.7749, longitude: -122.4194, precision: 5) == "9q8yy")
    }

    @Test func neighborsShareACell() {
        // Two spots a block apart land in the same cell; the server sees one question from both.
        let a = Geohash.encode(latitude: 37.7749, longitude: -122.4194, precision: 6)
        let b = Geohash.encode(latitude: 37.7755, longitude: -122.4188, precision: 6)
        #expect(a == b)
    }

    @Test func clampsInputAndNeverReturnsEmpty() {
        #expect(Geohash.encode(latitude: 0, longitude: 0, precision: 6) == "s00000")
        #expect(Geohash.encode(latitude: 95, longitude: 200, precision: 3) == Geohash.encode(latitude: 90, longitude: 180, precision: 3))
        #expect(Geohash.encode(latitude: 1, longitude: 1, precision: 0).count == 1)
    }
}

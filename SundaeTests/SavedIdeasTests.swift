import Foundation
import Testing
@testable import Sundae

/// Saved ideas: kept for the week on this phone, matched to photos by place, and Sunday's head start.
@MainActor
struct SavedIdeasTests {
    let zone = TimeZone(identifier: "America/Indiana/Indianapolis")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// Monday, October 19, 2026.
    private var weekStart: Date { date(19, hour: 0) }

    // Juniper Bakery and Riverside Park, made up, a kilometer or so apart.
    private let bakery = (latitude: 39.7700, longitude: -86.1580)
    private let park = (latitude: 39.7790, longitude: -86.1580)

    private func idea(_ id: String, place: String? = nil, at spot: (latitude: Double, longitude: Double)? = nil,
                      categories: [Suggestion.Category] = [.food]) -> Suggestion {
        Suggestion(id: id, text: "Try something new at \(place ?? "home").", reason: "Take a photo of it.",
                   categories: categories, timeOfDay: .any,
                   place: place.map { Suggestion.Place(name: $0, latitude: spot?.latitude, longitude: spot?.longitude) })
    }

    private func photo(_ id: String, day: Int, hour: Int = 14, minute: Int = 0,
                       at spot: (latitude: Double, longitude: Double), northMeters: Double = 0, accuracy: Double = 10) -> LocatedPhoto {
        // About 111,000 meters to a degree of latitude.
        LocatedPhoto(assetID: id, takenAt: date(day, hour: hour, minute: minute),
                     latitude: spot.latitude + northMeters / 111_000, longitude: spot.longitude, accuracy: accuracy)
    }

    private func freshStore() -> SavedIdeasStore {
        let name = "saved-ideas-tests-\(UUID().uuidString)"
        let store = SavedIdeasStore(defaults: UserDefaults(suiteName: name)!)
        store.signedIn(userID: "pat")
        return store
    }

    // MARK: - Matching

    @Test func aPhotoTakenAtTheBakeryAfterSavingItIsFound() {
        let store = freshStore()
        store.save(idea("local:2026-10-21:1", place: "Juniper Bakery", at: bakery), at: date(21, hour: 9), weekStart: weekStart)
        let photos = [
            photo("there", day: 22, at: bakery, northMeters: 60),
            photo("across-town", day: 22, at: bakery, northMeters: 2_000),
            photo("monday-before", day: 19, at: bakery),
        ]
        let found = PhotoMatcher.matches(for: store.ideas, in: photos, calendar: calendar)
        #expect(found[store.ideas[0].id]?.map(\.assetID) == ["there"])
        #expect(found[store.ideas[0].id]?.first?.found == true)
    }

    @Test func earlierTheSameDayCounts() {
        let store = freshStore()
        store.save(idea("local:2026-10-21:1", place: "Juniper Bakery", at: bakery), at: date(21, hour: 17), weekStart: weekStart)
        let found = PhotoMatcher.matches(for: store.ideas, in: [photo("morning", day: 21, hour: 8, at: bakery)], calendar: calendar)
        #expect(found[store.ideas[0].id]?.count == 1)
    }

    @Test func parksReachFurtherThanShops() {
        let store = freshStore()
        store.save(idea("a", place: "Juniper Bakery", at: bakery), at: date(20), weekStart: weekStart)
        store.save(idea("b", place: "Riverside Park", at: park, categories: [.outdoors]), at: date(20), weekStart: weekStart)
        let photos = [
            photo("bakery-far", day: 21, at: bakery, northMeters: -300),
            photo("park-far", day: 21, at: park, northMeters: 300),
        ]
        let found = PhotoMatcher.matches(for: store.ideas, in: photos, calendar: calendar)
        #expect(found[store.ideas[0].id] == nil)
        #expect(found[store.ideas[1].id]?.map(\.assetID) == ["park-far"])
    }

    @Test func aPhotoGoesToTheNearestPlaceOnly() {
        let store = freshStore()
        let near = (latitude: bakery.latitude + 0.002, longitude: bakery.longitude)
        store.save(idea("a", place: "Juniper Bakery", at: bakery), at: date(20), weekStart: weekStart)
        store.save(idea("b", place: "Maple Street Library", at: near), at: date(20), weekStart: weekStart)
        // 100 m north of the bakery, about 120 m south of the library.
        let found = PhotoMatcher.matches(for: store.ideas, in: [photo("between", day: 21, at: bakery, northMeters: 100)], calendar: calendar)
        #expect(found[store.ideas[0].id]?.count == 1)
        #expect(found[store.ideas[1].id] == nil)
    }

    @Test func aVagueLocationOnlyStretchesSoFar() {
        let store = freshStore()
        store.save(idea("a", place: "Juniper Bakery", at: bakery), at: date(20), weekStart: weekStart)
        let photos = [photo("vague", day: 21, at: bakery, northMeters: 260, accuracy: 2_000)]
        #expect(PhotoMatcher.matches(for: store.ideas, in: photos, calendar: calendar).isEmpty)
    }

    @Test func ideasWithoutAPlaceAreNeverMatched() {
        let store = freshStore()
        store.save(idea("walk"), at: date(20), weekStart: weekStart)
        #expect(PhotoMatcher.matches(for: store.ideas, in: [photo("x", day: 21, at: bakery)], calendar: calendar).isEmpty)
    }

    @Test func aBigVisitIsSpreadAcrossSixPhotos() {
        let store = freshStore()
        store.save(idea("a", place: "Riverside Park", at: park, categories: [.outdoors]), at: date(20), weekStart: weekStart)
        let photos = (0..<20).map { photo("p\($0)", day: 21, hour: 15, minute: $0 * 2, at: park) }
        let found = PhotoMatcher.matches(for: store.ideas, in: photos, calendar: calendar)[store.ideas[0].id] ?? []
        #expect(found.count == SavedIdea.maxPhotos)
        #expect(found.first?.assetID == "p0")
        #expect(found.last?.assetID == "p19")
    }

    @Test func evenlyKeepsTheEnds() {
        #expect(PhotoMatcher.evenly(Array(0..<10), count: 3) == [0, 5, 9])
        #expect(PhotoMatcher.evenly([1, 2], count: 6) == [1, 2])
        #expect(PhotoMatcher.evenly([1, 2, 3], count: 1) == [1])
    }

    // MARK: - The store

    @Test func savingTwiceKeepsOne() {
        let store = freshStore()
        let bakeryIdea = idea("local:2026-10-21:1", place: "Juniper Bakery", at: bakery)
        store.save(bakeryIdea, at: date(21), weekStart: weekStart)
        store.save(bakeryIdea, at: date(21, hour: 13), weekStart: weekStart)
        #expect(store.ideas.count == 1)
        #expect(store.isSaved(bakeryIdea))
        // A nearby id names a day and a slot, so the same id somewhere else is another idea.
        #expect(!store.isSaved(idea("local:2026-10-21:1", place: "Riverside Park", at: park)))
    }

    @Test func aNewWeekStartsEmpty() {
        let store = freshStore()
        store.save(idea("a"), at: date(21), weekStart: weekStart)
        store.startWeek(weekStart)
        #expect(store.ideas.count == 1)
        store.startWeek(date(26, hour: 0))
        #expect(store.ideas.isEmpty)
    }

    @Test func foundPhotosArriveOnceAndStayOffWhenTakenOff() {
        let store = freshStore()
        var firsts: [String] = []
        store.onFirstPhoto = { suggestion, _ in firsts.append(suggestion.id) }
        store.save(idea("a", place: "Juniper Bakery", at: bakery), at: date(20), weekStart: weekStart)
        let id = store.ideas[0].id
        let photos = [photo("one", day: 21, at: bakery), photo("two", day: 21, hour: 15, at: bakery)]

        store.addFound(PhotoMatcher.matches(for: store.ideas, in: photos, calendar: calendar), at: date(21))
        #expect(store.ideas[0].photos.map(\.assetID) == ["one", "two"])
        #expect(firsts == ["a"])

        store.removePhoto("one", from: id)
        store.addFound(PhotoMatcher.matches(for: store.ideas, in: photos, calendar: calendar), at: date(22))
        #expect(store.ideas[0].photos.map(\.assetID) == ["two"])
        #expect(firsts == ["a"])
    }

    @Test func pickingByHandMovesAPhotoAndRemembersWhatWasDropped() {
        let store = freshStore()
        store.save(idea("a"), at: date(20), weekStart: weekStart)
        store.save(idea("b"), at: date(20), weekStart: weekStart)
        let (a, b) = (store.ideas[0].id, store.ideas[1].id)
        store.setPhotos([SavedPhoto(assetID: "x", takenAt: date(21), found: false),
                         SavedPhoto(assetID: "y", takenAt: date(20), found: false)], for: a, at: date(21))
        #expect(store.ideas[0].photos.map(\.assetID) == ["y", "x"])

        store.setPhotos([SavedPhoto(assetID: "x", takenAt: date(21), found: false)], for: b, at: date(21))
        #expect(store.ideas[0].photos.map(\.assetID) == ["y"])
        #expect(store.ideas[1].photos.map(\.assetID) == ["x"])

        store.setPhotos([], for: a, at: date(22))
        #expect(store.ideas[0].removed.contains("y"))
    }

    @Test func handPickedPhotosStopAtSix() {
        let store = freshStore()
        store.save(idea("a"), at: date(20), weekStart: weekStart)
        let many = (0..<9).map { SavedPhoto(assetID: "p\($0)", takenAt: date(21, minute: $0), found: false) }
        store.setPhotos(many, for: store.ideas[0].id, at: date(21))
        #expect(store.ideas[0].photos.count == SavedIdea.maxPhotos)
    }

    @Test func photosDeletedFromTheLibraryGo() {
        let store = freshStore()
        store.save(idea("a"), at: date(20), weekStart: weekStart)
        store.setPhotos([SavedPhoto(assetID: "kept", takenAt: date(21), found: false),
                         SavedPhoto(assetID: "deleted", takenAt: date(21), found: false)], for: store.ideas[0].id, at: date(21))
        store.forgetMissing(["deleted"])
        #expect(store.ideas[0].photos.map(\.assetID) == ["kept"])
    }

    @Test func sundayStartsWithEveryIdeaInTheOrderTaken() {
        let store = freshStore()
        store.save(idea("a"), at: date(20), weekStart: weekStart)
        store.save(idea("b"), at: date(20), weekStart: weekStart)
        let (a, b) = (store.ideas[0].id, store.ideas[1].id)
        store.setPhotos((0..<6).map { SavedPhoto(assetID: "a\($0)", takenAt: date(21, minute: $0), found: false) }, for: a, at: date(21))
        store.setPhotos((0..<3).map { SavedPhoto(assetID: "b\($0)", takenAt: date(20, minute: $0), found: false) }, for: b, at: date(21))
        store.setCaption("Juniper's best", for: a)

        let all = store.photosForPost()
        #expect(all.map(\.assetID) == ["b0", "b1", "b2", "a0", "a1", "a2", "a3", "a4", "a5"])
        #expect(all.filter { $0.assetID.hasPrefix("a") }.allSatisfy { $0.caption == "Juniper's best" })
        #expect(all.filter { $0.assetID.hasPrefix("b") }.allSatisfy { $0.caption.isEmpty })

        // Too many for one post: each idea gets its turn, so both make it in.
        let four = store.photosForPost(limit: 4)
        #expect(four.map(\.assetID) == ["b0", "b1", "a0", "a1"])
    }

    @Test func theWeekComesBackForTheSamePersonOnly() {
        let name = "saved-ideas-tests-\(UUID().uuidString)"
        let store = SavedIdeasStore(defaults: UserDefaults(suiteName: name)!)
        store.signedIn(userID: "pat")
        store.save(idea("a"), at: date(20), weekStart: weekStart)
        store.setCaption("Pat's", for: store.ideas[0].id)

        store.signedOut()
        #expect(store.ideas.isEmpty)
        store.signedIn(userID: "pat")
        #expect(store.ideas.first?.caption == "Pat's")

        // A fresh launch reads the same week back.
        #expect(SavedIdeasStore(defaults: UserDefaults(suiteName: name)!).ideas.count == 1)

        store.signedOut()
        store.signedIn(userID: "sam")
        #expect(store.ideas.isEmpty)
    }

    @Test func forgettingLeavesNothing() {
        let name = "saved-ideas-tests-\(UUID().uuidString)"
        let store = SavedIdeasStore(defaults: UserDefaults(suiteName: name)!)
        store.signedIn(userID: "pat")
        store.save(idea("a"), at: date(20), weekStart: weekStart)
        store.forgetAll()
        store.signedIn(userID: "pat")
        #expect(store.ideas.isEmpty)
    }
}

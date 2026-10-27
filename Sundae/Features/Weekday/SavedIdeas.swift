import CoreLocation
import Foundation
import Observation
import Photos

/// An idea someone kept for the week, and the photos set aside for it. Only ever on this phone:
/// nothing here reaches Sundae until its photos are posted on Sunday.
struct SavedIdea: Codable, Identifiable, Hashable, Sendable {
    static let maxPhotos = 6
    static let maxCaptionLength = DumpDraft.maxPhotoCaptionLength

    /// Made when it is saved. Nearby ideas' own ids name a day and a slot, so they can repeat.
    let id: String
    let suggestion: Suggestion
    let savedAt: Date
    /// Oldest first.
    var photos: [SavedPhoto] = []
    /// Photos taken off this idea. Sundae never puts them back on its own.
    var removed: Set<String> = []
    /// One caption for all of this idea's photos. On Sunday each photo starts with it.
    var caption: String = ""

    init(suggestion: Suggestion, savedAt: Date) {
        id = UUID().uuidString
        self.suggestion = suggestion
        self.savedAt = savedAt
    }

    var canAddMore: Bool { photos.count < Self.maxPhotos }

    /// Where it is, when it is a real place.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = suggestion.place?.latitude, let longitude = suggestion.place?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The same idea: the same words at the same place.
    func isSame(as suggestion: Suggestion) -> Bool {
        self.suggestion.id == suggestion.id && self.suggestion.place?.name == suggestion.place?.name
    }
}

/// One photo in the library, by its Photos id. The picture itself stays in Photos.
struct SavedPhoto: Codable, Identifiable, Hashable, Sendable {
    let assetID: String
    let takenAt: Date?
    /// True when Sundae found it by where it was taken, false when it was added by hand.
    let found: Bool

    var id: String { assetID }
}

/// A photo for Sunday's post, with the caption it starts with.
struct SavedPhotoForPost: Hashable, Sendable {
    let assetID: String
    let takenAt: Date?
    let caption: String
}

@MainActor
@Observable
final class SavedIdeasStore {
    /// In the order they were saved.
    private(set) var ideas: [SavedIdea] = []
    /// Called when an idea gets its first photo, which means it was done.
    var onFirstPhoto: ((Suggestion, Date) -> Void)?

    private var weekStart: Date?
    private var ownerID: String?
    private let defaults: UserDefaults

    private enum Key {
        static let week = "savedIdeas.week"
        static let askedForPhotos = "savedIdeas.askedForPhotos"
    }

    /// What is kept on the phone: whose week it is, which week, and its ideas.
    private struct Stored: Codable {
        var ownerID: String?
        var weekStart: Date
        var ideas: [SavedIdea]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    /// True once Sundae has explained finding photos and asked for Photos access, so it asks once.
    var askedForPhotos: Bool {
        get { defaults.bool(forKey: Key.askedForPhotos) }
        set { defaults.set(newValue, forKey: Key.askedForPhotos) }
    }

    func isSaved(_ suggestion: Suggestion) -> Bool {
        ideas.contains { $0.isSame(as: suggestion) }
    }

    /// Names of saved places, so Shuffle skips them whatever today's idea there says.
    var savedPlaceNames: Set<String> { Set(ideas.compactMap { $0.suggestion.place?.name }) }

    // MARK: - The week

    /// Last week's ideas go once a new week starts. Sunday still belongs to the week it ends.
    func startWeek(_ start: Date) {
        guard weekStart != start else { return }
        weekStart = start
        ideas = []
        persist()
    }

    func save(_ suggestion: Suggestion, at date: Date, weekStart start: Date) {
        startWeek(start)
        guard !isSaved(suggestion) else { return }
        ideas.append(SavedIdea(suggestion: suggestion, savedAt: date))
        persist()
    }

    func remove(_ id: String) {
        ideas.removeAll { $0.id == id }
        persist()
    }

    func setCaption(_ text: String, for id: String) {
        guard let index = ideas.firstIndex(where: { $0.id == id }) else { return }
        ideas[index].caption = String(text.prefix(SavedIdea.maxCaptionLength))
        persist()
    }

    // MARK: - Photos

    /// The photos picked by hand for an idea, replacing the ones it had. A photo moves here from
    /// any other idea, and one taken off is remembered so Sundae does not find it again.
    func setPhotos(_ photos: [SavedPhoto], for id: String, at date: Date) {
        guard let index = ideas.firstIndex(where: { $0.id == id }) else { return }
        let wasEmpty = ideas[index].photos.isEmpty
        let kept = Array(photos.prefix(SavedIdea.maxPhotos))
        let keptIDs = Set(kept.map(\.assetID))
        for other in ideas.indices where other != index {
            ideas[other].photos.removeAll { keptIDs.contains($0.assetID) }
        }
        let dropped = ideas[index].photos.map(\.assetID).filter { !keptIDs.contains($0) }
        ideas[index].removed.formUnion(dropped)
        ideas[index].removed.subtract(keptIDs)
        ideas[index].photos = Self.inOrder(kept)
        persist()
        if wasEmpty, !kept.isEmpty { onFirstPhoto?(ideas[index].suggestion, date) }
    }

    func removePhoto(_ assetID: String, from id: String) {
        guard let index = ideas.firstIndex(where: { $0.id == id }) else { return }
        ideas[index].photos.removeAll { $0.assetID == assetID }
        ideas[index].removed.insert(assetID)
        persist()
    }

    /// Photos Sundae found by place, by idea id. Each idea keeps what it has and takes the rest
    /// up to its limit.
    func addFound(_ found: [String: [SavedPhoto]], at date: Date) {
        var firsts: [Suggestion] = []
        for (id, photos) in found {
            guard let index = ideas.firstIndex(where: { $0.id == id }) else { continue }
            let have = Set(ideas.flatMap { $0.photos.map(\.assetID) })
            let fresh = photos.filter { !have.contains($0.assetID) && !ideas[index].removed.contains($0.assetID) }
            let room = SavedIdea.maxPhotos - ideas[index].photos.count
            guard !fresh.isEmpty, room > 0 else { continue }
            if ideas[index].photos.isEmpty { firsts.append(ideas[index].suggestion) }
            ideas[index].photos = Self.inOrder(ideas[index].photos + fresh.prefix(room))
        }
        guard !firsts.isEmpty || found.values.contains(where: { !$0.isEmpty }) else { return }
        persist()
        for suggestion in firsts { onFirstPhoto?(suggestion, date) }
    }

    /// Photos deleted from the library since they were set aside go from their ideas too.
    func forgetMissing(_ missing: Set<String>) {
        guard !missing.isEmpty else { return }
        for index in ideas.indices {
            ideas[index].photos.removeAll { missing.contains($0.assetID) }
        }
        persist()
    }

    /// Looks through this week's photos for ones taken at the places saved, on the phone. Asks
    /// for nothing: without Photos access it does nothing.
    func findPhotos(clock: SundayClock) async {
        guard PhotoFinder.isAuthorized, !ideas.isEmpty else { return }
        let start = weekStart ?? clock.weekStart()
        let end = clock.now()
        let listed = Set(ideas.flatMap { $0.photos.map(\.assetID) })
        let (photos, existing) = await Task.detached(priority: .utility) {
            (PhotoFinder.locatedPhotos(from: start, to: end), PhotoFinder.existing(listed))
        }.value
        // Only what was listed before looking: a photo added meanwhile is not missing.
        forgetMissing(listed.subtracting(existing))
        addFound(PhotoMatcher.matches(for: ideas, in: photos, calendar: clock.calendar), at: end)
    }

    /// Up to `limit` photos for Sunday's post, in the order taken. When there are more, each idea
    /// gets a turn in the order it was saved, so every idea makes it in.
    func photosForPost(limit: Int = DumpDraft.maxPhotos) -> [SavedPhotoForPost] {
        var queues = ideas.map { idea in
            idea.photos.map { SavedPhotoForPost(assetID: $0.assetID, takenAt: $0.takenAt, caption: idea.caption) }
        }
        var picked: [SavedPhotoForPost] = []
        var seen = Set<String>()
        while picked.count < limit, queues.contains(where: { !$0.isEmpty }) {
            for index in queues.indices where picked.count < limit && !queues[index].isEmpty {
                let photo = queues[index].removeFirst()
                if seen.insert(photo.assetID).inserted { picked.append(photo) }
            }
        }
        return picked.sorted { ($0.takenAt ?? .distantFuture) < ($1.takenAt ?? .distantFuture) }
    }

    // MARK: - Accounts

    /// The same person signing back in gets their week back; anyone else starts empty.
    func signedIn(userID: String) {
        restore()
        if ownerID != userID {
            ideas = []
        }
        ownerID = userID
        persist()
    }

    /// Off the screen at once. The week stays on the phone for the same person to sign back in to.
    func signedOut() {
        ideas = []
        weekStart = nil
        ownerID = nil
    }

    /// Nothing of it left on the phone.
    func forgetAll() {
        signedOut()
        defaults.removeObject(forKey: Key.week)
        defaults.removeObject(forKey: Key.askedForPhotos)
    }

    // MARK: - Storage

    private func restore() {
        guard let data = defaults.data(forKey: Key.week),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        ownerID = stored.ownerID
        weekStart = stored.weekStart
        ideas = stored.ideas
    }

    private func persist() {
        // Signed out, the stored week belongs to whoever was signed in. Leave it be.
        guard ownerID != nil, let weekStart,
              let data = try? JSONEncoder().encode(Stored(ownerID: ownerID, weekStart: weekStart, ideas: ideas)) else { return }
        defaults.set(data, forKey: Key.week)
    }

    private static func inOrder(_ photos: [SavedPhoto]) -> [SavedPhoto] {
        photos.sorted { ($0.takenAt ?? .distantFuture) < ($1.takenAt ?? .distantFuture) }
    }
}

// MARK: - Matching

/// Where and when a photo in the library was taken, as far as matching needs to know.
struct LocatedPhoto: Hashable, Sendable {
    let assetID: String
    let takenAt: Date
    let latitude: Double
    let longitude: Double
    /// How far off the camera's position may have been, in meters.
    let accuracy: Double
}

/// Which of this week's photos were taken at a saved place. All on the phone, from the location
/// the camera stored with each photo; nothing is looked up and nothing is sent.
enum PhotoMatcher {
    /// How close counts as there. Parks and trails are big, shops are not.
    static func radius(for suggestion: Suggestion) -> Double {
        suggestion.categories.contains(.outdoors) ? 400 : 150
    }

    /// The most a photo's own uncertainty may stretch that.
    static let accuracyAllowance: Double = 50

    /// For each saved place, by idea id, the new photos taken there from the day it was saved on.
    /// A photo goes to the nearest place only, never one it was taken off, never one already set
    /// aside. When there are more than fit, they are picked evenly across the visit.
    static func matches(for ideas: [SavedIdea], in photos: [LocatedPhoto], calendar: Calendar) -> [String: [SavedPhoto]] {
        let places = ideas.compactMap { idea in idea.coordinate.map { (idea, CLLocation(latitude: $0.latitude, longitude: $0.longitude)) } }
        guard !places.isEmpty else { return [:] }
        let taken = Set(ideas.flatMap { $0.photos.map(\.assetID) })
        var byIdea: [String: [LocatedPhoto]] = [:]
        for photo in photos where !taken.contains(photo.assetID) && photo.accuracy >= 0 {
            let spot = CLLocation(latitude: photo.latitude, longitude: photo.longitude)
            let slack = min(photo.accuracy, accuracyAllowance)
            let nearest = places
                .filter { idea, _ in
                    photo.takenAt >= calendar.startOfDay(for: idea.savedAt) && !idea.removed.contains(photo.assetID)
                }
                .map { idea, place in (idea: idea, distance: spot.distance(from: place)) }
                .filter { $0.distance <= radius(for: $0.idea.suggestion) + slack }
                .min { $0.distance < $1.distance }
            if let nearest { byIdea[nearest.idea.id, default: []].append(photo) }
        }
        var result: [String: [SavedPhoto]] = [:]
        for idea in ideas {
            guard let found = byIdea[idea.id] else { continue }
            let room = SavedIdea.maxPhotos - idea.photos.count
            guard room > 0 else { continue }
            let spread = evenly(found.sorted { $0.takenAt < $1.takenAt }, count: room)
            result[idea.id] = spread.map { SavedPhoto(assetID: $0.assetID, takenAt: $0.takenAt, found: true) }
        }
        return result
    }

    /// `count` items spread from first to last, or all of them when they fit.
    static func evenly<T>(_ items: [T], count: Int) -> [T] {
        guard items.count > count else { return items }
        guard count > 1 else { return Array(items.prefix(count)) }
        let step = Double(items.count - 1) / Double(count - 1)
        return (0..<count).map { items[Int((Double($0) * step).rounded())] }
    }
}

/// Reads the library for matching. Never asks for access; only looks when it has been given.
enum PhotoFinder {
    static var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Photos taken in [start, end) that carry a location, leaving out screenshots.
    nonisolated static func locatedPhotos(from start: Date, to end: Date) -> [LocatedPhoto] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@ AND mediaType == %d",
                                        start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var photos: [LocatedPhoto] = []
        result.enumerateObjects { asset, _, _ in
            guard !asset.mediaSubtypes.contains(.photoScreenshot), let location = asset.location,
                  let taken = asset.creationDate else { return }
            photos.append(LocatedPhoto(assetID: asset.localIdentifier, takenAt: taken,
                                       latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                       accuracy: location.horizontalAccuracy))
        }
        return photos
    }

    /// Which of these ids are still in the library.
    nonisolated static func existing(_ ids: Set<String>) -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        var found = Set<String>()
        result.enumerateObjects { asset, _, _ in found.insert(asset.localIdentifier) }
        return found
    }

    /// Assets by id, for thumbnails and Sunday's post.
    static func assets(_ ids: [String]) -> [String: PHAsset] {
        guard !ids.isEmpty else { return [:] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var found: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in found[asset.localIdentifier] = asset }
        return found
    }
}

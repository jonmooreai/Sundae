import CoreLocation
import Foundation
import MapKit

/// Real places from Apple Maps, picked on the phone. A plain-words search per kind of place
/// around the middle of the cell, once walkable and once within twenty miles: Apple sees a
/// neighborhood, never the fix, and Sundae's servers see nothing at all. The pick is seeded by
/// cell and day, so the day's ideas hold still.
enum NearbyIdeas {
    /// A walk: the cell plus about fifteen minutes on foot.
    static let walkMeters: CLLocationDistance = 1200
    /// Worth the trip: twenty miles.
    static let radiusMeters: CLLocationDistance = 32187

    /// Meters per minute on foot, for the "12 min walk" line.
    private static let walkPace = 80.0

    enum Theme: String, Sendable, CaseIterable {
        case cafe, bakery, park, viewpoint, library, museum, market, trail, waterfront
        case bookstore, recordStore, iceCream, gallery, diner

        /// What to ask Maps for. Plain words find more than category filters do.
        var query: String {
            switch self {
            case .cafe: "coffee shop"
            case .bakery: "bakery"
            case .park: "park"
            case .viewpoint: "scenic viewpoint"
            case .library: "library"
            case .museum: "museum"
            case .market: "farmers market"
            case .trail: "hiking trail"
            case .waterfront: "beach"
            case .bookstore: "bookstore"
            case .recordStore: "record store"
            case .iceCream: "ice cream"
            case .gallery: "art gallery"
            case .diner: "diner"
            }
        }
    }

    /// What came back from Maps, reduced to plain values inside the callback.
    private struct Place: Sendable {
        let id: String
        let name: String
        let theme: Theme
        let latitude: Double
        let longitude: Double
    }

    struct Line: Sendable {
        let text: String
        let reason: String
    }

    enum Failure: Error {
        case badCell
    }

    static func ideas(cell: String, day: Date, calendar: Calendar) async throws -> [Suggestion] {
        guard let origin = Geohash.center(cell) else { throw Failure.badCell }
        // Maps answers each search with a couple of dozen places, and a single broad search comes
        // back mostly parks and landmarks. One plain-words search per kind of place, close by and
        // within twenty miles, gives every kind a fair chance. Merged by place, duplicates dropped.
        async let sky = Weather.sky(latitude: origin.latitude, longitude: origin.longitude)
        let places = await withTaskGroup(of: [Place].self, returning: [Place].self) { group in
            for theme in Theme.allCases {
                group.addTask { await search(theme: theme, around: origin, radius: walkMeters) }
                group.addTask { await search(theme: theme, around: origin, radius: radiusMeters) }
            }
            var seen = Set<String>()
            var all: [Place] = []
            for await batch in group {
                for place in batch where seen.insert(place.id).inserted { all.append(place) }
            }
            return all
        }
        let wet = await sky == .wet
        return pick(from: places, origin: origin, cell: cell, day: day, calendar: calendar, wet: wet)
    }

    // MARK: - Maps

    /// Kinds of place an idea never sends anyone to, whatever the search matched.
    private static let excludedCategories: Set<MKPointOfInterestCategory> = [
        .hospital, .police, .fireStation, .school, .pharmacy, .university, .airport, .publicTransport, .parking,
    ]

    /// One search. Failures count as no places, so one bad request never empties the day.
    private static func search(theme: Theme, around origin: (latitude: Double, longitude: Double),
                               radius: CLLocationDistance) async -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = theme.query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude),
                                            latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        let search = MKLocalSearch(request: request)
        return await withCheckedContinuation { continuation in
            search.start { response, _ in
                let places = (response?.mapItems ?? []).compactMap { item -> Place? in
                    guard let name = item.name, !name.isEmpty, IdeaGuard.isSafePlace(named: name) else { return nil }
                    if let category = item.pointOfInterestCategory, excludedCategories.contains(category) { return nil }
                    let coordinate = item.placemark.coordinate
                    let key = "\(name.lowercased())@\((coordinate.latitude * 1000).rounded()),\((coordinate.longitude * 1000).rounded())"
                    return Place(id: key, name: name, theme: theme, latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
                continuation.resume(returning: places)
            }
        }
    }

    // MARK: - Picking

    /// Places that are still a good idea in the rain.
    private static let indoor: Set<Theme> = [.cafe, .bakery, .library, .museum, .market, .bookstore, .recordStore, .iceCream, .gallery, .diner]

    private static func pick(from places: [Place], origin: (latitude: Double, longitude: Double),
                             cell: String, day: Date, calendar: Calendar, wet: Bool = false) -> [Suggestion] {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let dayString = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        var random = SeededRandom(seed: "\(cell):\(dayString)")
        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let nearby = places
            .map { (place: $0, meters: CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) }
            .filter { $0.meters <= radiusMeters }
            .sorted { $0.meters < $1.meters }

        var usedPlaces = Set<String>()
        var usedThemes = Set<Theme>()
        var ideas: [Suggestion] = []
        let slots: [Suggestion.TimeOfDay] = [.morning, .afternoon, .evening]
        // Eight ideas: three for the parts of the day, five more so Shuffle has somewhere to go.
        for index in 0..<8 {
            let slot = slots[index % slots.count]
            if usedThemes.count == Theme.allCases.count { usedThemes.removeAll() }
            var candidates = nearby.filter { !usedPlaces.contains($0.place.id) && !(lines[$0.place.theme]?[slot] ?? []).isEmpty }
            // A wet day keeps to places with a roof, as long as there are any.
            if wet {
                let dry = candidates.filter { indoor.contains($0.place.theme) }
                if !dry.isEmpty { candidates = dry }
            }
            guard !candidates.isEmpty else { continue }
            // A theme not used yet today, then chance. The morning idea stays close to home;
            // the afternoon and evening may be worth the drive.
            let fresh = candidates.filter { !usedThemes.contains($0.place.theme) }
            let ranked = fresh.isEmpty ? candidates : fresh
            let pool = index == 0 ? Array(ranked.prefix(8)) : ranked
            let choice = pool[Int(random.next() % UInt64(pool.count))]
            guard let variants = lines[choice.place.theme]?[slot], !variants.isEmpty else { continue }
            var line = variants[Int(random.next() % UInt64(variants.count))]
            if wet, let rainy = rainLines[choice.place.theme], random.next() % 2 == 0 { line = rainy }
            usedPlaces.insert(choice.place.id)
            usedThemes.insert(choice.place.theme)
            ideas.append(Suggestion(
                // The day and a slot. Never the cell: this id travels with the account when marked done.
                id: "\(Suggestion.nearbyPrefix)\(dayString):\(index)",
                text: line.text.replacingOccurrences(of: "{name}", with: choice.place.name),
                reason: line.reason.replacingOccurrences(of: "{name}", with: choice.place.name),
                categories: [.local], timeOfDay: slot,
                place: Suggestion.Place(name: choice.place.name,
                                        walkMinutes: choice.meters <= walkMeters ? max(1, Int((choice.meters / walkPace).rounded())) : nil,
                                        distanceMeters: choice.meters,
                                        latitude: choice.place.latitude, longitude: choice.place.longitude)))
        }
        return IdeaGuard.filter(ideas)
    }

    /// One line per roofed place for a rainy day, used about half the time it rains.
    static let rainLines: [Theme: Line] = [
        .cafe: Line(text: "Wait out the rain at {name}.", reason: "Window seat. Photograph the drops on the glass."),
        .bakery: Line(text: "Rain means {name}.", reason: "Something warm, eaten by the window. Photograph the fogged glass."),
        .library: Line(text: "Spend the wet afternoon at {name}.", reason: "A reading room on a rainy day is the best room in town. Photograph the windows."),
        .museum: Line(text: "A rainy day is a museum day. Go to {name}.", reason: "One room, slowly. Photograph the piece you looked at longest."),
        .market: Line(text: "Duck into {name} and shop for dinner.", reason: "Three things, no list. Photograph the haul on your counter."),
        .bookstore: Line(text: "Wait out the rain at {name}.", reason: "Find a corner and a chapter. Photograph the stack you almost bought."),
        .recordStore: Line(text: "Spend the rain at {name}.", reason: "Dig through one crate front to back. Photograph your favorite cover."),
        .gallery: Line(text: "Step into {name} out of the rain.", reason: "Pick one piece and stay with it. Photograph it from across the room."),
        .diner: Line(text: "Have something warm at {name}.", reason: "A booth by the window. Photograph the rain on the glass."),
        .iceCream: Line(text: "Rain or not, go to {name}.", reason: "Ice cream in the rain is a better story. Photograph the cone under your umbrella."),
    ]

    /// What to do at each kind of place, by time of day. {name} is the place. Every line is
    /// something you could photograph without pointing a camera at anyone you don't know.
    static let lines: [Theme: [Suggestion.TimeOfDay: [Line]]] = [
        .cafe: [
            .morning: [
                Line(text: "Have the first coffee of the day at {name}.", reason: "Sit by the window. Photograph the cup, then the view outside."),
                Line(text: "Finally go into {name}.", reason: "You walk past it all the time. Order something you never get."),
            ],
            .afternoon: [
                Line(text: "Take your afternoon break at {name}.", reason: "One table, one hour, no laptop. Photograph the light on the table."),
            ],
            .evening: [
                Line(text: "Get a decaf and a slice at {name} before it closes.", reason: "Closing time is the quietest hour. Photograph the empty chairs."),
            ],
        ],
        .bakery: [
            .morning: [
                Line(text: "Be first in line at {name}.", reason: "The bread comes out around now. Photograph the steam and the paper bags."),
                Line(text: "Buy something still warm at {name}.", reason: "Eat it on a bench outside. Photograph the crumbs."),
            ],
            .afternoon: [
                Line(text: "Pick up tomorrow's breakfast at {name}.", reason: "Get the thing you never get. Photograph it before the first bite."),
            ],
        ],
        .park: [
            .morning: [
                Line(text: "Walk {name} early.", reason: "Low sun, long shadows, a bench for your coffee. Photograph the wide view and one detail."),
            ],
            .afternoon: [
                Line(text: "Lie on the grass at {name} for twenty minutes.", reason: "Phone face down, then one photo straight up at the sky."),
                Line(text: "Read a chapter at {name}.", reason: "Bring the book you keep not finishing. Photograph the page and the view past it."),
            ],
            .evening: [
                Line(text: "Catch the last light at {name}.", reason: "Ten minutes of color. Bring a friend and photograph the sky."),
            ],
        ],
        .viewpoint: [
            .morning: [
                Line(text: "See the city wake up from {name}.", reason: "Get there in time to watch the lights go off. One photo, then just look."),
            ],
            .afternoon: [
                Line(text: "Go to {name} and look at where you live.", reason: "Find your street from there. Photograph the direction of home."),
            ],
            .evening: [
                Line(text: "Catch the sunset from {name}.", reason: "Ten minutes of color. Bring a friend."),
            ],
        ],
        .library: [
            .afternoon: [
                Line(text: "Spend an hour at {name}.", reason: "Find the oldest book on the shelf nearest the window. Photograph the spine."),
                Line(text: "Get a library card at {name}, or use the one you have.", reason: "Borrow something on a whim. Photograph the due date slip."),
            ],
        ],
        .museum: [
            .afternoon: [
                Line(text: "Go see one room at {name}.", reason: "One room, not the whole place. Photograph the piece you looked at longest."),
            ],
            .evening: [
                Line(text: "See whether {name} has a late opening this week.", reason: "Quiet galleries feel like a different museum. Photograph your favorite room."),
            ],
        ],
        .market: [
            .morning: [
                Line(text: "Buy one thing you can't name at {name}.", reason: "Ask what it is. Photograph it at home before you cook it."),
            ],
            .afternoon: [
                Line(text: "Make dinner only from what you find at {name}.", reason: "Three ingredients, no list. Photograph the haul on the counter."),
            ],
        ],
        .trail: [
            .morning: [
                Line(text: "Do the first mile of {name} before work.", reason: "Out and back, no summit. Photograph the turnaround point."),
            ],
            .afternoon: [
                Line(text: "Walk {name} for an hour, then turn around.", reason: "Stay on the marked trail. Photograph the best view on the way back."),
            ],
        ],
        .waterfront: [
            .morning: [
                Line(text: "Walk along the water at {name}.", reason: "Flat light and gulls. Keep the horizon low in the photo."),
            ],
            .evening: [
                Line(text: "Walk to the end of {name} and back.", reason: "The lights come on behind you on the way back. That is the photo."),
            ],
        ],
        .bookstore: [
            .morning: [
                Line(text: "Be the first one into {name}.", reason: "Quiet aisles, coffee in hand. Buy the book with the best first sentence."),
            ],
            .afternoon: [
                Line(text: "Buy a book you've never heard of at {name}.", reason: "Pick it by the first sentence. Photograph it in your hands outside."),
            ],
            .evening: [
                Line(text: "Browse {name} before it closes.", reason: "Start with the staff picks shelf. Photograph the handwritten cards."),
            ],
        ],
        .recordStore: [
            .afternoon: [
                Line(text: "Flip through the dollar bin at {name}.", reason: "Pick the cover that makes you laugh. Photograph it in your hands."),
            ],
            .evening: [
                Line(text: "Ask what's playing at {name}.", reason: "Buy it if you can. Photograph the sleeve under the shop lights."),
            ],
        ],
        .iceCream: [
            .afternoon: [
                Line(text: "Get a flavor you'd never pick at {name}.", reason: "Eat it walking. Photograph the cone against the sky."),
            ],
            .evening: [
                Line(text: "Walk to {name} after dinner.", reason: "The walk is the point and the cone is the excuse. Photograph the sign."),
            ],
        ],
        .gallery: [
            .afternoon: [
                Line(text: "Walk into {name} like you meant to.", reason: "It's free and quiet. Photograph the floor and one wall."),
            ],
            .evening: [
                Line(text: "See whether {name} has an opening this week.", reason: "New work, a good room. Photograph the piece you'd take home."),
            ],
        ],
        .diner: [
            .morning: [
                Line(text: "Have breakfast at the counter at {name}.", reason: "Order whatever they're known for. Photograph the mug, not the plate."),
            ],
            .evening: [
                Line(text: "Have dinner at the counter at {name}.", reason: "Order the special. Photograph the menu board and your plate."),
            ],
        ],
    ]
}

/// SplitMix64, seeded from a string, so a (cell, day) pair always picks the same way.
private struct SeededRandom {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

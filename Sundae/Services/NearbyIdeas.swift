import CoreLocation
import Foundation
import MapKit

/// Real places from Apple Maps, picked on the phone. Two points-of-interest searches around the
/// middle of the cell, one walkable and one within twenty miles: Apple sees a neighborhood,
/// never the fix, and Sundae's servers see nothing at all. The pick is seeded by cell and day,
/// so the three ideas hold still all day.
enum NearbyIdeas {
    /// A walk: the cell plus about fifteen minutes on foot.
    static let walkMeters: CLLocationDistance = 1200
    /// Worth the trip: twenty miles.
    static let radiusMeters: CLLocationDistance = 32187

    /// Meters per minute on foot, for the "12 min walk" line.
    private static let walkPace = 80.0

    enum Theme: String, Sendable {
        case cafe, bakery, park, viewpoint, library, museum, market, trail, waterfront
    }

    /// What came back from Maps, reduced to plain values inside the callback.
    private struct Place: Sendable {
        let id: String
        let name: String
        let theme: Theme
        let latitude: Double
        let longitude: Double
    }

    private struct Line: Sendable {
        let text: String
        let reason: String
    }

    enum Failure: Error {
        case badCell
    }

    static func ideas(cell: String, day: Date, calendar: Calendar) async throws -> [Suggestion] {
        guard let origin = Geohash.center(cell) else { throw Failure.badCell }
        // Maps returns a couple of dozen results per search, so the wide one alone would skip
        // the corner café. Ask twice and merge.
        async let near = search(around: origin, radius: walkMeters)
        async let far = search(around: origin, radius: radiusMeters)
        async let sky = Weather.sky(latitude: origin.latitude, longitude: origin.longitude)
        var seen = Set<String>()
        let places = try await (near + far).filter { seen.insert($0.id).inserted }
        let wet = await sky == .wet
        return pick(from: places, origin: origin, cell: cell, day: day, calendar: calendar, wet: wet)
    }

    // MARK: - Maps

    private static func theme(for category: MKPointOfInterestCategory) -> Theme? {
        switch category {
        case .cafe: .cafe
        case .bakery: .bakery
        case .park, .nationalPark: .park
        case .landmark: .viewpoint
        case .library: .library
        case .museum: .museum
        case .foodMarket: .market
        case .hiking: .trail
        case .beach, .marina: .waterfront
        default: nil
        }
    }

    private static func search(around origin: (latitude: Double, longitude: Double), radius: CLLocationDistance) async throws -> [Place] {
        let center = CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .cafe, .bakery, .park, .nationalPark, .landmark, .library, .museum, .foodMarket, .hiking, .beach, .marina,
        ])
        let search = MKLocalSearch(request: request)
        return try await withCheckedThrowingContinuation { continuation in
            search.start { response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let places = (response?.mapItems ?? []).compactMap { item -> Place? in
                    guard let name = item.name, !name.isEmpty,
                          let category = item.pointOfInterestCategory,
                          let theme = theme(for: category) else { return nil }
                    let coordinate = item.placemark.coordinate
                    return Place(id: "\(name)@\(coordinate.latitude),\(coordinate.longitude)", name: name, theme: theme,
                                 latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
                continuation.resume(returning: places)
            }
        }
    }

    // MARK: - Picking

    /// Places that are still a good idea in the rain.
    private static let indoor: Set<Theme> = [.cafe, .bakery, .library, .museum, .market]

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
        for (index, slot) in slots.enumerated() {
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
        return ideas
    }

    /// One line per roofed place for a rainy day, used about half the time it rains.
    private static let rainLines: [Theme: Line] = [
        .cafe: Line(text: "Wait out the rain at {name}.", reason: "Window seat. Photograph the drops on the glass and whoever is running past."),
        .bakery: Line(text: "Rain means {name}.", reason: "Something warm, eaten by the window. Shoot the fogged glass."),
        .library: Line(text: "Spend the wet afternoon at {name}.", reason: "The reading room on a rainy day is the best room in the city. Shoot the windows."),
        .museum: Line(text: "A rainy day is a museum day. Go to {name}.", reason: "One room, slowly. Photograph the umbrellas by the door on your way out."),
        .market: Line(text: "Duck into {name} and shop for dinner.", reason: "Three things, no list. Photograph the wet pavement outside with the bag in frame."),
    ]

    /// What to do at each kind of place, by time of day. {name} is the place.
    private static let lines: [Theme: [Suggestion.TimeOfDay: [Line]]] = [
        .cafe: [
            .morning: [
                Line(text: "Have the first coffee of the day at {name}.", reason: "Sit by the window. Photograph the cup, then whatever is outside the glass."),
                Line(text: "Finally go into {name}.", reason: "You walk past it all the time. Order what the person ahead of you ordered."),
            ],
            .afternoon: [
                Line(text: "Take your afternoon slump to {name}.", reason: "One table, one hour, no laptop. Shoot the light on the table at the end."),
            ],
            .evening: [
                Line(text: "Get a decaf and a slice at {name} before it closes.", reason: "Closing-time cafés are the quietest rooms in town. Photograph the chairs going up."),
            ],
        ],
        .bakery: [
            .morning: [
                Line(text: "Be first in line at {name}.", reason: "The bread comes out around now. Shoot the steam, the paper bags, the person ahead of you."),
                Line(text: "Buy something still warm at {name}.", reason: "Eat it on the step outside. The photo is the crumbs."),
            ],
            .afternoon: [
                Line(text: "Pick up tomorrow's breakfast at {name}.", reason: "Get the thing you never get. Photograph it before anyone else sees it."),
            ],
        ],
        .park: [
            .morning: [
                Line(text: "Walk {name} before the dog people leave.", reason: "Low sun, long shadows, a bench to drink coffee on. Take the wide shot and one detail."),
            ],
            .afternoon: [
                Line(text: "Lie on the grass at {name} for twenty minutes.", reason: "Phone face down, then one photo straight up. That is the whole assignment."),
                Line(text: "Read a chapter at {name}.", reason: "Bring the book you keep not finishing. Shoot the page and the view past it."),
            ],
            .evening: [
                Line(text: "Catch the last light at {name}.", reason: "Ten minutes of color. Bring someone, or shoot the people who did."),
            ],
        ],
        .viewpoint: [
            .morning: [
                Line(text: "See the city wake up from {name}.", reason: "Get there early enough to watch the lights go off. One frame, then put the phone away."),
            ],
            .afternoon: [
                Line(text: "Walk over to {name} and look at where you live.", reason: "Find your street from there. Photograph the direction of home."),
            ],
            .evening: [
                Line(text: "Catch the sunset from {name}.", reason: "Fifteen minutes there, ten minutes of color. Bring someone."),
            ],
        ],
        .library: [
            .afternoon: [
                Line(text: "Spend an hour at {name}.", reason: "Find the oldest book on the shelf nearest the window. Photograph the spine, not the cover."),
                Line(text: "Get a library card at {name}, or use the one you have.", reason: "Borrow something on a whim. Shoot the stamp or the due date."),
            ],
        ],
        .museum: [
            .afternoon: [
                Line(text: "Go see one room at {name}.", reason: "One room, not the whole place. Photograph the thing you looked at longest."),
            ],
            .evening: [
                Line(text: "See if {name} is open late tonight.", reason: "Empty galleries after dark are a different museum. Shoot a guard, politely."),
            ],
        ],
        .market: [
            .morning: [
                Line(text: "Buy one thing you cannot name at {name}.", reason: "Ask what it is. Shoot it at home before you cook it."),
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
                Line(text: "Walk {name} until the phone has no signal.", reason: "Then one photo and turn around. The photo is the proof."),
            ],
        ],
        .waterfront: [
            .morning: [
                Line(text: "Walk the water at {name} before anyone is out.", reason: "Flat light, gulls, somebody fishing. Shoot the horizon low in the frame."),
            ],
            .evening: [
                Line(text: "Walk to the end of {name} and back.", reason: "The lights come on behind you on the way back. That is the photo."),
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

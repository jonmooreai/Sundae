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
        case cafe, bakery, restaurant, market, library, museum, gallery, bookstore, recordStore, iceCream
        case park, trail, waterfront, viewpoint

        /// What to ask Maps for. Only a starting point: a result's kind is confirmed by Apple's own
        /// category before any line is written about it.
        var query: String {
            switch self {
            case .cafe: "coffee shop"
            case .bakery: "bakery"
            case .restaurant: "restaurant"
            case .market: "farmers market"
            case .library: "library"
            case .museum: "museum"
            case .gallery: "art gallery"
            case .bookstore: "bookstore"
            case .recordStore: "record store"
            case .iceCream: "ice cream"
            case .park: "park"
            case .trail: "hiking trail"
            case .waterfront: "beach"
            case .viewpoint: "scenic overlook"
            }
        }

        /// Businesses and venues: their lines may only say what any place of that category does.
        var isBusiness: Bool {
            switch self {
            case .park, .trail, .waterfront, .viewpoint: false
            default: true
            }
        }

        /// What a result really is, from Apple's category and, where the category is broad, its
        /// name. Nil when we cannot vouch for it; the place is then not used at all.
        static func confirm(searchedFor theme: Theme, category: MKPointOfInterestCategory?, name: String) -> Theme? {
            let words = IdeaGuard.words(in: name.lowercased())
            func named(_ list: Set<String>) -> Bool { !words.isDisjoint(with: list) }
            switch category {
            case .cafe?: return theme == .iceCream && named(iceCreamWords) ? .iceCream : .cafe
            case .bakery?: return theme == .iceCream && named(iceCreamWords) ? .iceCream : .bakery
            case .restaurant?: return theme == .iceCream && named(iceCreamWords) ? .iceCream : .restaurant
            case .foodMarket?: return .market
            case .library?: return .library
            case .museum?: return theme == .gallery ? .gallery : .museum
            case .park?, .nationalPark?: return named(viewpointWords) ? .viewpoint : .park
            case .beach?, .marina?: return .waterfront
            case .hiking?: return .trail
            case .store?:
                switch theme {
                case .bookstore: return .bookstore
                case .recordStore: return named(recordWords) ? .recordStore : nil
                case .gallery: return .gallery
                case .iceCream: return named(iceCreamWords) ? .iceCream : nil
                default: return nil
                }
            case nil: return theme == .viewpoint && named(viewpointWords) ? .viewpoint : nil
            default: return nil
            }
        }

        private static let iceCreamWords: Set<String> = ["ice", "cream", "creamery", "gelato", "gelateria", "custard", "froyo", "scoop", "scoops", "sundae", "sundaes"]
        private static let recordWords: Set<String> = ["record", "records", "vinyl"]
        private static let viewpointWords: Set<String> = ["overlook", "lookout", "viewpoint", "vista", "outlook", "observation"]
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

    /// An idea and the kind of place it is about.
    private struct Pick {
        let suggestion: Suggestion
        let theme: Theme
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
        let picks = pick(from: places, origin: origin, cell: cell, day: day, calendar: calendar, wet: wet)
        return await reword(picks, wet: wet, first: Suggestion.TimeOfDay.current(for: day, calendar: calendar))
    }

    /// How long the on-device model may take over the day's wording before the rest keep their
    /// hand-written lines. The ideas wait for it, so it stays short.
    static let rewordBudget: Duration = .seconds(6)

    /// The day's ideas in fresh words, where the phone has Apple's on-device model (IdeaWriter):
    /// this part of the day first, then the rest, within the budget. The rest keep their lines.
    private static func reword(_ picks: [Pick], wet: Bool, first slot: Suggestion.TimeOfDay) async -> [Suggestion] {
        var ideas = picks.map(\.suggestion)
        guard IdeaWriter.isAvailable else { return ideas }
        let deadline = ContinuousClock.now + rewordBudget
        let order = ideas.indices.sorted {
            (ideas[$0].timeOfDay == slot ? 0 : 1, $0) < (ideas[$1].timeOfDay == slot ? 0 : 1, $1)
        }
        for index in order {
            guard ContinuousClock.now < deadline else { break }
            let idea = ideas[index]
            let theme = picks[index].theme
            guard let place = idea.place else { continue }
            let brief = IdeaWriter.Brief(place: place.name, kind: theme.query, isBusiness: theme.isBusiness,
                                         timeOfDay: idea.timeOfDay, walkMinutes: place.walkMinutes, isRaining: wet,
                                         text: idea.text, reason: idea.reason)
            guard let wording = await IdeaWriter.reword(brief) else { continue }
            ideas[index] = Suggestion(id: idea.id, text: wording.text, reason: wording.reason,
                                      categories: idea.categories, timeOfDay: idea.timeOfDay, place: idea.place)
        }
        return ideas
    }

    // MARK: - Maps

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
                    guard let name = item.name, !name.isEmpty, IdeaGuard.isSafePlace(named: name),
                          let kind = Theme.confirm(searchedFor: theme, category: item.pointOfInterestCategory, name: name)
                    else { return nil }
                    let coordinate = item.placemark.coordinate
                    let key = "\(name.lowercased())@\((coordinate.latitude * 1000).rounded()),\((coordinate.longitude * 1000).rounded())"
                    return Place(id: key, name: name, theme: kind, latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
                continuation.resume(returning: places)
            }
        }
    }

    // MARK: - Picking

    /// Places that are still a good idea in the rain.
    private static let indoor: Set<Theme> = [.cafe, .bakery, .restaurant, .market, .library, .museum, .gallery, .bookstore, .recordStore, .iceCream]

    private static func pick(from places: [Place], origin: (latitude: Double, longitude: Double),
                             cell: String, day: Date, calendar: Calendar, wet: Bool = false) -> [Pick] {
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
        var ideas: [Pick] = []
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
            if choice.place.theme.isBusiness,
               !IdeaGuard.makesNoBusinessClaims(line.text) || !IdeaGuard.makesNoBusinessClaims(line.reason) { continue }
            usedPlaces.insert(choice.place.id)
            usedThemes.insert(choice.place.theme)
            ideas.append(Pick(suggestion: Suggestion(
                // The day and a slot. Never the cell: this id travels with the account when marked done.
                id: "\(Suggestion.nearbyPrefix)\(dayString):\(index)",
                text: line.text.replacingOccurrences(of: "{name}", with: choice.place.name),
                reason: line.reason.replacingOccurrences(of: "{name}", with: choice.place.name),
                categories: [.local], timeOfDay: slot,
                place: Suggestion.Place(name: choice.place.name,
                                        walkMinutes: choice.meters <= walkMeters ? max(1, Int((choice.meters / walkPace).rounded())) : nil,
                                        distanceMeters: choice.meters,
                                        latitude: choice.place.latitude, longitude: choice.place.longitude)),
                theme: choice.place.theme))
        }
        return ideas.filter { IdeaGuard.isSafe($0.suggestion) }
    }

    /// One line per roofed place for a rainy day, used about half the time it rains.
    static let rainLines: [Theme: Line] = [
        .cafe: Line(text: "Wait out the rain at {name}.", reason: "Get a drink and take a photo of the rain from inside."),
        .bakery: Line(text: "Duck into {name} out of the rain.", reason: "Pick something you've never tried. Take a photo of it."),
        .restaurant: Line(text: "Wait out the rain at {name}.", reason: "Order something you've never had. Snap a pic of the table."),
        .market: Line(text: "Shop for one meal at {name} while it rains.", reason: "Three things, no list. Take a photo of the haul at home."),
        .library: Line(text: "Spend a rainy hour at {name}.", reason: "Pick a book you'd never choose. Take a photo of the cover."),
        .museum: Line(text: "A rainy day is a good day for {name}.", reason: "Pick one thing and give it five minutes. Take a photo if photos are allowed."),
        .gallery: Line(text: "Step into {name} out of the rain.", reason: "Find the piece you'd take home. Take a photo if photos are allowed."),
        .bookstore: Line(text: "Wait out the rain at {name}.", reason: "Pick a book by its first sentence. Take a photo of it in your hands."),
        .recordStore: Line(text: "Spend the rain at {name}.", reason: "Pick the cover you like most. Snap a pic of it."),
    ]

    /// What to do at each kind of place, by time of day. {name} is the place. Business lines say
    /// only what any place of that kind does: no meals, hours, counters, menus or seating.
    /// Photos are always "take a photo", "take photos" or "snap a pic".
    static let lines: [Theme: [Suggestion.TimeOfDay: [Line]]] = {
        let cafe = [
            Line(text: "Get a drink you've never ordered at {name}.", reason: "Take a photo of the cup before the first sip."),
            Line(text: "Take a coffee break at {name}.", reason: "Ten minutes with no phone, then snap a pic of the view from where you are."),
        ]
        let bakery = [
            Line(text: "Pick something you've never tried at {name}.", reason: "Take a photo of it before the first bite."),
            Line(text: "Bring a treat from {name} to a friend.", reason: "Snap a pic of it before you hand it over."),
        ]
        let restaurant = [
            Line(text: "Try {name}.", reason: "Order something you've never had. Snap a pic before the first bite."),
            Line(text: "Take a friend to {name}.", reason: "Order two things and share. Take a photo of the table."),
        ]
        let market = [
            Line(text: "Buy one thing you've never cooked at {name}.", reason: "Take a photo of it at home before you cook it."),
            Line(text: "Shop for one meal at {name}.", reason: "Three things, no list. Snap a pic of the haul."),
        ]
        let library = [
            Line(text: "Spend an hour at {name}.", reason: "Pick a book you'd never choose. Take a photo of the cover."),
            Line(text: "Read for a while at {name}.", reason: "Snap a pic of the page you stopped on."),
        ]
        let museum = [
            Line(text: "Spend an hour at {name}.", reason: "Pick one thing and give it five minutes. Take a photo if photos are allowed."),
        ]
        let gallery = [
            Line(text: "Walk through {name}.", reason: "Find the piece you'd take home. Take a photo if photos are allowed."),
        ]
        let bookstore = [
            Line(text: "Browse {name} for twenty minutes.", reason: "Pick a book by its first sentence. Take a photo of it in your hands."),
        ]
        let records = [
            Line(text: "Browse the records at {name}.", reason: "Pick the cover you like most. Snap a pic of it."),
        ]
        let iceCream = [
            Line(text: "Get something sweet at {name}.", reason: "Take a photo of it before it melts."),
        ]
        return [
            .cafe: [.morning: cafe, .afternoon: cafe],
            .bakery: [.morning: bakery, .afternoon: bakery],
            .restaurant: [.afternoon: restaurant, .evening: restaurant],
            .market: [.morning: market, .afternoon: market],
            .library: [.morning: library, .afternoon: library],
            .museum: [.afternoon: museum],
            .gallery: [.afternoon: gallery],
            .bookstore: [.morning: bookstore, .afternoon: bookstore],
            .recordStore: [.afternoon: records],
            .iceCream: [.afternoon: iceCream, .evening: iceCream],
            .park: [
                .morning: [Line(text: "Take an early walk at {name}.", reason: "Low sun and long shadows. Take a photo of the wide view and one small detail.")],
                .afternoon: [
                    Line(text: "Sit somewhere at {name} for twenty minutes.", reason: "Phone down first. Then snap a pic of what's in front of you."),
                    Line(text: "Read a chapter at {name}.", reason: "Bring the book you keep not finishing. Take a photo of the page and the view."),
                ],
                .evening: [Line(text: "Catch the last light at {name}.", reason: "Bring a friend and take photos of the sky as it changes.")],
            ],
            .trail: [
                .morning: [Line(text: "Walk part of {name} and turn back when you're ready.", reason: "Stay on the marked trail. Take a photo at your turnaround point.")],
                .afternoon: [Line(text: "Walk part of {name} and turn back when you're ready.", reason: "Stay on the marked trail. Take a photo at your turnaround point.")],
            ],
            .waterfront: [
                .morning: [Line(text: "Walk along the water at {name}.", reason: "Take a photo with the horizon low in the frame.")],
                .afternoon: [Line(text: "Walk along the water at {name}.", reason: "Take a photo with the horizon low in the frame.")],
                .evening: [Line(text: "Watch the sky change at {name}.", reason: "Stay for the color after sunset. Take photos every few minutes.")],
            ],
            .viewpoint: [
                .morning: [Line(text: "See the morning from {name}.", reason: "Take one photo, then put the phone away and look.")],
                .afternoon: [Line(text: "Go to {name} and find your street.", reason: "Take a photo looking toward home.")],
                .evening: [Line(text: "Watch the sunset from {name}.", reason: "Bring a friend. Take photos as the color changes.")],
            ],
        ]
    }()
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

import Foundation
import MapKit
import Testing
@testable import Sundae

/// Nothing violent, nothing aimed at strangers, no alcohol, nothing risky, never a solemn
/// place. These tests read every line the app can show; adding one that fails breaks the build.
struct IdeaGuardTests {
    private let names = ["Tartine", "The Corner Spot", "Riverside", "Central Library"]

    @Test func theLinesThatMustNeverAppearAreRefused() {
        for line in [
            "Shoot a guard, politely.",
            "Free wine, strangers, art. Shoot the crowd, not the work.",
            "Shoot the counter, the specials board, the faces.",
            "Walk the trail until the phone has no signal.",
            "Order what the person ahead of you ordered.",
            "Catch the last light. Bring someone, or shoot the people who did.",
            "A parking garage roof counts.",
            "Photograph the steam and the paper bags.",
            "Capture the light on the table.",
            "Snap the menu board.",
        ] {
            #expect(!IdeaGuard.isSafeText(line), "\(line)")
        }
    }

    @Test func businessLinesMayNotAssumeMealsHoursCountersOrMenus() {
        for line in ["Have breakfast at the counter at Chicken Salad Chick.", "Photograph the mug, not the plate.",
                     "Order the special.", "See whether it is open late tonight.", "The bread comes out around now. Be first in line."] {
            #expect(!IdeaGuard.makesNoBusinessClaims(line), "\(line)")
        }
        #expect(IdeaGuard.makesNoBusinessClaims("Try Chicken Salad Chick."))
    }

    @Test func aPlacesKindComesFromAppleNotFromOurSearchWords() {
        // A restaurant found by a search for ice cream is a restaurant, and gets restaurant lines.
        #expect(NearbyIdeas.Theme.confirm(searchedFor: .iceCream, category: .restaurant, name: "Chicken Salad Chick") == .restaurant)
        #expect(NearbyIdeas.Theme.confirm(searchedFor: .iceCream, category: .restaurant, name: "Jeni's Splendid Ice Creams") == .iceCream)
        // A shop that is not plainly a record shop is not used for record lines.
        #expect(NearbyIdeas.Theme.confirm(searchedFor: .recordStore, category: .store, name: "Guitar Center") == nil)
        // No category, no idea; landmarks are never used.
        #expect(NearbyIdeas.Theme.confirm(searchedFor: .park, category: nil, name: "Somewhere") == nil)
        #expect(NearbyIdeas.Theme.confirm(searchedFor: .museum, category: .landmark, name: "Monument Circle") == nil)
        #expect(NearbyIdeas.Theme.confirm(searchedFor: .viewpoint, category: .park, name: "Riverside Overlook") == .viewpoint)
    }

    @Test func ordinaryLinesPass() {
        for line in [
            "Take a photo of the steam.",
            "Take photos as the color changes.",
            "Take a photograph of the view.",
            "Snap a pic of it before you hand it over.",
            "Watch the sunset from somewhere high.",
        ] {
            #expect(IdeaGuard.isSafeText(line), "\(line)")
        }
    }

    @Test func solemnAndSensitivePlacesAreNeverUsed() {
        for name in ["Indiana War Memorials", "Crown Hill Cemetery", "St. Mary's Church", "Riley Children\u{2019}s Hospital",
                     "Lincoln Memorial", "Holocaust Museum", "Marion County Jail", "Veterans Park", "Oak Elementary School"] {
            #expect(!IdeaGuard.isSafePlace(named: name), "\(name)")
        }
        for name in ["Warwick Park", "Tartine Bakery", "Newfields", "Mission Dolores Park", "Central Library"] {
            #expect(IdeaGuard.isSafePlace(named: name), "\(name)")
        }
    }

    @Test func aSuggestionAtAMemorialIsRefusedHoweverItIsWorded() {
        let idea = Suggestion(id: "local:2026-10-26:0", text: "Go see one room at Indiana War Memorials.",
                              reason: "Photograph the piece you looked at longest.", categories: [.local],
                              timeOfDay: .afternoon, place: Suggestion.Place(name: "Indiana War Memorials"))
        #expect(!IdeaGuard.isSafe(idea))
    }

    @Test func everyBundledIdeaPasses() throws {
        let url = try #require(Bundle.main.url(forResource: "suggestions", withExtension: "json"))
        let all = try JSONDecoder().decode([Suggestion].self, from: Data(contentsOf: url))
        #expect(!all.isEmpty)
        for idea in all {
            #expect(IdeaGuard.isSafe(idea), "\(idea.id): \(idea.text) / \(idea.reason)")
        }
    }

    @Test func everyNearbyLinePassesWhateverThePlaceIsCalled() {
        var count = 0
        for (theme, slots) in NearbyIdeas.lines {
            for (slot, lines) in slots {
                for line in lines {
                    for name in names {
                        count += 1
                        #expect(IdeaGuard.isSafeText(line.text.replacingOccurrences(of: "{name}", with: name)), "\(theme)/\(slot): \(line.text)")
                        #expect(IdeaGuard.isSafeText(line.reason.replacingOccurrences(of: "{name}", with: name)), "\(theme)/\(slot): \(line.reason)")
                    }
                    if theme.isBusiness {
                        #expect(IdeaGuard.makesNoBusinessClaims(line.text), "\(theme)/\(slot) claims: \(line.text)")
                        #expect(IdeaGuard.makesNoBusinessClaims(line.reason), "\(theme)/\(slot) claims: \(line.reason)")
                    }
                }
            }
        }
        for (theme, line) in NearbyIdeas.rainLines {
            #expect(IdeaGuard.makesNoBusinessClaims(line.text) || !theme.isBusiness, "\(theme) rain claims: \(line.text)")
            #expect(IdeaGuard.makesNoBusinessClaims(line.reason) || !theme.isBusiness, "\(theme) rain claims: \(line.reason)")
            for name in names {
                #expect(IdeaGuard.isSafeText(line.text.replacingOccurrences(of: "{name}", with: name)), "\(theme) rain: \(line.text)")
                #expect(IdeaGuard.isSafeText(line.reason.replacingOccurrences(of: "{name}", with: name)), "\(theme) rain: \(line.reason)")
            }
        }
        #expect(count > 0)
    }

    @Test func theDemoBackendOnlyWritesSafeIdeas() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!
        for day in 19...24 {
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
            let api = MockSundaeAPI(clock: SundayClock(now: { date }, timeZone: calendar.timeZone))
            for cell in ["9q8yyk", "dp4j2a", "u4pruy", "gcpvj0", "dr5reg"] {
                let ideas = try await api.localIdeas(cell: cell, day: date)
                #expect(ideas.count == 3)
                for idea in ideas { #expect(IdeaGuard.isSafe(idea), "\(idea.text) / \(idea.reason)") }
            }
        }
    }

    @Test func wordsSplitOnLettersSoNamesAreNotMisread() {
        #expect(IdeaGuard.words(in: "warwick park") == ["warwick", "park"])
        #expect(IdeaGuard.words(in: "st. mary's church") == ["st", "mary", "church"])
    }
}

import Foundation
import Testing
@testable import Sundae

/// The on-device model only ever rewords, and a rewrite is kept only if it passes everything a
/// hand-written line does and a little more. These tests run without the model.
struct IdeaWriterTests {
    private let bakery = IdeaWriter.Brief(place: "Pat's Bakery", kind: "bakery", isBusiness: true, timeOfDay: .morning,
                                          walkMinutes: 6, isRaining: false,
                                          text: "Pick something you've never tried at Pat's Bakery.",
                                          reason: "Take a photo of it before the first bite.")
    private let park = IdeaWriter.Brief(place: "Riverside Park", kind: "park", isBusiness: false, timeOfDay: .evening,
                                        walkMinutes: nil, isRaining: false,
                                        text: "Catch the last light at Riverside Park.",
                                        reason: "Bring a friend and take photos of the sky as it changes.")

    @Test func aGoodRewriteIsKept() {
        #expect(IdeaWriter.accepts(text: "Try something new at Pat's Bakery.",
                                   reason: "It's a 6 minute walk. Take a photo of it before the first bite.", for: bakery))
        #expect(IdeaWriter.accepts(text: "Watch the day end at Riverside Park.",
                                   reason: "Bring someone along and take photos as the sky turns.", for: park))
    }

    @Test func itMustNameThePlaceAndAskForAPhoto() {
        #expect(!IdeaWriter.accepts(text: "Try something new at the bakery.",
                                    reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery.",
                                    reason: "Enjoy it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery.",
                                    reason: "Capture it before the first bite.", for: bakery))
    }

    @Test func itMayNotSayWhatABusinessHasOrMakeThingsUp() {
        #expect(!IdeaWriter.accepts(text: "Get the famous scones at Pat's Bakery.",
                                    reason: "Take a photo of one.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Try something fresh at Pat's Bakery.",
                                    reason: "Take a photo of it.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Go to Pat's Bakery before 9.",
                                    reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Watch the sky at Riverside Park.",
                                    reason: "Bring wine and take photos as it changes.", for: park))
    }

    @Test func itKeepsTheHouseStyle() {
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery!",
                                    reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery \u{2014} anything.",
                                    reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery \u{1F370}.",
                                    reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery, and take your time getting there.",
                                    reason: String(repeating: "Take a photo of it. ", count: 10), for: bakery))
    }

    @Test func tidyingMakesOnePlainLine() {
        #expect(IdeaWriter.tidy("  Try something new at Pat\u{2019}s Bakery\n") == "Try something new at Pat's Bakery.")
        #expect(IdeaWriter.tidy("Take a photo of it.") == "Take a photo of it.")
    }

    @Test func thePromptCarriesOnlyWhatIsTrue() {
        let prompt = IdeaWriter.prompt(for: bakery, why: "")
        #expect(prompt.contains("Pat's Bakery"))
        #expect(prompt.contains("a 6 minute walk"))
        #expect(!prompt.contains("Weather"))
        #expect(!prompt.contains("Take a photo"), "the photo ask is never the model's to write")
        #expect(!IdeaWriter.prompt(for: park, why: "").contains("walk"))
    }

    @Test func thePhotoAskIsKeptWordForWord() {
        let parts = IdeaWriter.split("Pick a book you'd never choose. Take a photo of the cover.")
        #expect(parts.why == "Pick a book you'd never choose.")
        #expect(parts.ask == "Take a photo of the cover.")
        let only = IdeaWriter.split("Take a photo of it before the first bite.")
        #expect(only.why.isEmpty)
        #expect(only.ask == "Take a photo of it before the first bite.")
        let one = IdeaWriter.split("Take one photo, then put the phone away and look.")
        #expect(one.why.isEmpty)
    }

    @Test func itNeverAsksForAPhotoTwice() {
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery.",
                                    reason: "Take a photo of it, then snap a pic before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery.",
                                    reason: "Take a photo or snap a pic of it.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Take a photo at Pat's Bakery.",
                                    reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery.",
                                    reason: "Great for pictures. Take a photo of it before the first bite.", for: bakery))
    }
}

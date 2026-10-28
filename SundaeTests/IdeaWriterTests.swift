import Foundation
import Testing
@testable import Sundae

/// The on-device model only ever rewords, and a rewrite is kept only if it passes everything a
/// hand-written line does and a little more. These tests run without the model.
struct IdeaWriterTests {
    private let bakery = IdeaWriter.Brief(place: "Pat's Bakery", kind: "bakery", isBusiness: true,
                                          text: "Pick something you've never tried at Pat's Bakery.",
                                          reason: "Take a photo of it before the first bite.",
                                          keep: ["something|treat", "never|new"])
    private let park = IdeaWriter.Brief(place: "Riverside Park", kind: "park", isBusiness: false,
                                        text: "Catch the last light at Riverside Park.",
                                        reason: "Bring a friend and take photos of the sky as it changes.",
                                        keep: ["light|sky|sunset"])
    private let gift = IdeaWriter.Brief(place: "Uptown Bakery", kind: "bakery", isBusiness: true,
                                        text: "Bring a treat from Uptown Bakery to a friend.",
                                        reason: "Snap a pic of it before you hand it over.",
                                        keep: ["treat", "friend|someone"])
    private let library = IdeaWriter.Brief(place: "Maple Street Library", kind: "library", isBusiness: true,
                                           text: "Spend an hour at Maple Street Library.",
                                           reason: "Pick a book you'd never choose. Take a photo of the cover.",
                                           keep: ["book"])

    @Test func aGoodRewriteIsKept() {
        #expect(IdeaWriter.accepts(text: "Try something new at Pat's Bakery.",
                                   reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(IdeaWriter.accepts(text: "Stay for the last light at Riverside Park.",
                                   reason: "Bring someone along and take photos as the sky turns.", for: park))
        #expect(IdeaWriter.accepts(text: "Surprise a friend with a treat from Uptown Bakery.",
                                   reason: "Snap a pic of it before you hand it over.", for: gift))
    }

    /// What reached a phone: the treat and the friend were dropped, so "hand it over" pointed at
    /// nothing. A rewrite has to keep what the photo line leans on, or the hand-written line stays.
    @Test func theActivitySurvivesTheRewording() {
        #expect(!IdeaWriter.accepts(text: "Visit Uptown Bakery in the morning.",
                                    reason: "Snap a pic of it before you hand it over.", for: gift))
        #expect(!IdeaWriter.accepts(text: "Pick up a treat at Uptown Bakery.",
                                    reason: "Snap a pic of it before you hand it over.", for: gift))
        #expect(IdeaWriter.accepts(text: "Bring someone a treat from Uptown Bakery.",
                                   reason: "Snap a pic of it before you hand it over.", for: gift))
        // In the why counts too, but never in the photo line, which is kept whatever is written.
        #expect(IdeaWriter.accepts(text: "Give Maple Street Library an hour of your week.",
                                   reason: "Choose a book you would usually walk past. Take a photo of the cover.", for: library))
        #expect(!IdeaWriter.accepts(text: "Give Maple Street Library an hour of your week.",
                                    reason: "Choose something you would usually walk past. Take a photo of the cover.", for: library))
    }

    /// The screen already says "An idea for Wednesday morning" and how far it is.
    @Test func itDoesNotRepeatWhatTheScreenShows() {
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery this morning.",
                                    reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery, a short walk away.",
                                    reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Try something new at Pat's Bakery nearby.",
                                    reason: "Take a photo of it before the first bite.", for: bakery))
        // Unless the hand-written line said it first.
        let view = IdeaWriter.Brief(place: "Lookout Point", kind: "scenic viewpoint", isBusiness: false,
                                    text: "See the morning from Lookout Point.",
                                    reason: "Take one photo, then put the phone away and look.",
                                    keep: ["morning|view"])
        #expect(IdeaWriter.accepts(text: "Greet the morning from Lookout Point.",
                                   reason: "Take one photo, then put the phone away and look.", for: view))
    }

    @Test func keptWordsAreWholeWords() {
        #expect(IdeaWriter.keeps(["rain|rainy"], in: "Wait out the rainy hour."))
        #expect(IdeaWriter.keeps(["cook"], in: "Something you have never cooked."))
        #expect(IdeaWriter.keeps(["friend|someone"], in: "Bring someone a treat."))
        #expect(IdeaWriter.keeps(["first sentence|first line"], in: "Choose by the first line."))
        #expect(!IdeaWriter.keeps(["read"], in: "Turn back when you're ready."))
        #expect(!IdeaWriter.keeps(["treat", "friend"], in: "Bring a treat."))
        #expect(IdeaWriter.keeps([], in: "Anything."))
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
        #expect(!IdeaWriter.accepts(text: "Find something new at Pat's Bakery before 9.",
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
        let prompt = IdeaWriter.prompt(for: gift, why: "")
        #expect(prompt.contains("Place: Uptown Bakery"))
        #expect(prompt.contains("Idea to reword: Bring a treat from Uptown Bakery to a friend."))
        // Shown so the words lead into it, but never the model's to write (accepts checks).
        #expect(prompt.contains("Photo line, shown after your words: Snap a pic of it before you hand it over."))
        #expect(prompt.contains("Words to keep: treat, friend"))
        // Never the time, the walk or the weather: the screen shows them.
        for word in ["morning", "walk", "minute", "Weather", "rain"] {
            #expect(!prompt.contains(word), "\(word)")
        }
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

    @Test func theExamplesShownToTheModelPassEveryCheck() {
        for example in IdeaWriter.examples {
            let ask = IdeaWriter.split(example.brief.reason).ask
            let reason = example.why.isEmpty ? ask : "\(example.why) \(ask)"
            #expect(IdeaWriter.accepts(text: example.idea, reason: reason, for: example.brief), "\(example.idea)")
        }
        #expect(IdeaWriter.instructions.contains("idea: Surprise a friend with a treat from Sugar Hill Bakery."))
        #expect(IdeaWriter.instructions.contains("Words to keep: treat, friend"))
        #expect(!IdeaWriter.instructions.contains("\u{2014}"))
    }

    @Test func thePlaceNameAloneIsNotAnIdea() {
        #expect(!IdeaWriter.accepts(text: "Pat's Bakery.", reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Pat's Bakery is worth a visit.", reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(IdeaWriter.accepts(text: "Find something new at Pat's Bakery.", reason: "Take a photo of it before the first bite.", for: bakery))
        #expect(!IdeaWriter.accepts(text: "Visit Pat's Bakery.", reason: "Take a photo of it before the first bite.", for: bakery))
    }

    @Test func aPlaceholderWhyIsNeverShown() {
        #expect(!IdeaWriter.isSentence("none."))
        #expect(!IdeaWriter.isSentence("None, so leave it empty."))
        #expect(!IdeaWriter.isSentence("Pick one."))
        #expect(IdeaWriter.isSentence("Choose a book you would usually walk past."))
        #expect(!IdeaWriter.prompt(for: bakery, why: "").contains("Why to reword"))
    }

    /// Every hand-written line names what its rewording must keep, and its own words keep it, so
    /// no line can be reworded into one its photo line no longer fits.
    @Test func everyHandWrittenLineSaysWhatToKeep() {
        var lines: [NearbyIdeas.Line] = Array(NearbyIdeas.rainLines.values)
        for slots in NearbyIdeas.lines.values {
            for slotLines in slots.values { lines.append(contentsOf: slotLines) }
        }
        #expect(lines.count > 30)
        for line in lines {
            #expect(!line.keep.isEmpty, "\(line.text)")
            let text = line.text.replacingOccurrences(of: "{name}", with: "Pat's Place")
            let why = IdeaWriter.split(line.reason).why
            #expect(IdeaWriter.keeps(line.keep, in: "\(text) \(why)"), "\(line.text) keeps \(line.keep)")
        }
    }
}

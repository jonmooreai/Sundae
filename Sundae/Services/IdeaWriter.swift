import Foundation
import FoundationModels

/// Fresh words for ideas near you, from Apple's on-device model, on iPhones with Apple
/// Intelligence. It costs nothing, works offline, and nothing it reads or writes leaves the phone.
///
/// The model only rewords the idea and the why. The photo ask is never its to write: the
/// hand-written one is kept word for word, so an idea never asks for a picture twice. The model
/// is shown that ask, so its words still lead into it, and the words the activity hangs on
/// ("treat", "friend"), which a rewrite must keep: "Visit Uptown Bakery" followed by "Snap a pic
/// of it before you hand it over" is what happens otherwise. It is told only the place's name and
/// kind and the hand-written words, never the time or the distance, which the screen already
/// shows. Every rewrite must pass the same checks as the hand-written lines, and a few more, or the
/// hand-written line stays. Phones without the model keep the hand-written lines.
enum IdeaWriter {
    /// Everything the model is told about one idea.
    struct Brief: Sendable {
        let place: String
        /// What kind of place, in plain words: "bakery", "hiking trail".
        let kind: String
        /// Businesses may only be described by what any place of their kind does.
        let isBusiness: Bool
        let text: String
        let reason: String
        /// Words the activity hangs on, which a rewrite must keep (NearbyIdeas.Line.keep).
        /// "friend|someone" is kept by either.
        var keep: [String] = []
    }

    @Generable
    struct Wording {
        @Guide(description: "The idea: one short sentence that starts with a verb, names the place exactly as given and keeps every word to keep. No mention of photos.")
        var idea: String
        @Guide(description: "Why it is worth doing: one short sentence with no mention of photos. Empty when no why is given.")
        var why: String
    }

    /// True on an iPhone with Apple Intelligence turned on and the model ready.
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// The rules, most important first, then worked examples: a small model copies examples far
    /// more faithfully than it follows rules. Every example passes `accepts` (a test checks).
    static let instructions: String = {
        let rules = """
            You reword one daily idea for Sundae, a photo app for a small group of friends. Each \
            idea sends someone to one real place near them with one small, specific thing to do there.

            Change the words, never the meaning. Keep the same place and the same thing to do, \
            with everything in it: what to get, who it is for, what to look for. Every word listed \
            under Words to keep must appear in your idea or your why. Never shorten an idea to just \
            visiting or going to the place. If you cannot make it better, keep the original words.

            The app shows the photo line right after your words, word for word. Whatever it points \
            to (the treat, the book, the cup, the friend) must still be in your words, so the two \
            read as one. Never mention photos, pictures or cameras yourself.

            The app also shows the day, the time of day and the distance, so never add the time of \
            day, the weather, how far it is or how long it takes to get there.

            Write like a friend suggesting it: warm, plain, specific and short. Start the idea with \
            a verb. Write the place name exactly as given.

            You know nothing about the place beyond its name and its kind. Never say what it has: \
            no food, drink or dish by name, no menus, prices, hours, staff, seating, views or events. \
            Never mention alcohol, strangers, children, danger, or being out alone at night.

            The idea is one sentence of at most 70 characters. The why is one sentence of at most \
            90 characters, or left empty when there is no why to reword. No emoji, exclamation \
            marks, quotation marks or dashes.
            """
        let shown = Self.examples.map { example in
            let why = Self.split(example.brief.reason).why
            return "Example:\n\(Self.prompt(for: example.brief, why: why))\nidea: \(example.idea)\nwhy: \(example.why)"
        }
        return ([rules] + shown).joined(separator: "\n\n")
    }()

    /// A good rewrite, shown to the model.
    struct Example: Sendable {
        let brief: Brief
        let idea: String
        let why: String
    }

    static let examples: [Example] = [
        Example(brief: Brief(place: "Sugar Hill Bakery", kind: "bakery", isBusiness: true,
                             text: "Bring a treat from Sugar Hill Bakery to a friend.",
                             reason: "Snap a pic of it before you hand it over.",
                             keep: ["treat", "friend|someone"]),
                idea: "Surprise a friend with a treat from Sugar Hill Bakery.", why: ""),
        Example(brief: Brief(place: "Juniper Bakery", kind: "bakery", isBusiness: true,
                             text: "Pick something you've never tried at Juniper Bakery.",
                             reason: "Take a photo of it before the first bite.",
                             keep: ["something|treat", "never|new"]),
                idea: "Find something at Juniper Bakery you have never tried.", why: ""),
        Example(brief: Brief(place: "Riverside Park", kind: "park", isBusiness: false,
                             text: "Catch the last light at Riverside Park.",
                             reason: "Bring a friend and take photos of the sky as it changes.",
                             keep: ["light|sky|sunset"]),
                idea: "Stay for the last light at Riverside Park.", why: ""),
        Example(brief: Brief(place: "Maple Street Library", kind: "library", isBusiness: true,
                             text: "Spend an hour at Maple Street Library.",
                             reason: "Pick a book you'd never choose. Take a photo of the cover.",
                             keep: ["book"]),
                idea: "Give Maple Street Library an hour of your week.",
                why: "Choose a book you would usually walk past."),
    ]

    /// The idea in fresh words, or nil to keep the hand-written line. Never throws.
    static func reword(_ brief: Brief) async -> (text: String, reason: String)? {
        let parts = split(brief.reason)
        // Every line asks for one photo. One that does not is left as written.
        guard !parts.ask.isEmpty else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        do {
            // Greedy, so the same idea is worded the same way each time the day's ideas are looked up.
            let response = try await session.respond(to: prompt(for: brief, why: parts.why), generating: Wording.self,
                                                     options: GenerationOptions(sampling: .greedy))
            let text = tidy(response.content.idea)
            let reason: String
            if parts.why.isEmpty {
                reason = parts.ask
            } else {
                // A why that is not a real sentence keeps the hand-written one.
                let why = tidy(response.content.why)
                reason = "\(isSentence(why) ? why : parts.why) \(parts.ask)"
            }
            return accepts(text: text, reason: reason, for: brief) ? (text, reason) : nil
        } catch {
            // Unavailable, busy, or refused by Apple's own guardrails: the hand-written line it is.
            return nil
        }
    }

    /// The ways a line asks for a picture. Each hand-written line uses one, once.
    static let photoAsks = ["take a photo", "take photos", "take one photo", "snap a pic", "take a photograph"]

    /// A reason in two parts: the sentences that ask for a photo, kept word for word, and the
    /// rest, the why, which the model may reword.
    static func split(_ reason: String) -> (why: String, ask: String) {
        let parts = sentences(in: reason)
        let asks = parts.filter { sentence in photoAsks.contains { sentence.lowercased().contains($0) } }
        let why = parts.filter { !asks.contains($0) }
        return (why.joined(separator: " "), asks.joined(separator: " "))
    }

    /// "Low sun and long shadows. Take a photo." is two sentences.
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "?" {
                let sentence = current.trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { result.append(sentence) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    /// The place, the hand-written words, the photo line they lead into, and the words to keep.
    /// Never the time or the distance: the screen shows those, and a model told them repeats them.
    static func prompt(for brief: Brief, why: String) -> String {
        var lines = [
            "Place: \(brief.place)",
            "Kind of place: \(brief.kind)",
            "Idea to reword: \(brief.text)",
        ]
        // With no why there is no line for it, so there is nothing to copy back.
        if !why.isEmpty { lines.append("Why to reword: \(why)") }
        let ask = split(brief.reason).ask
        if !ask.isEmpty { lines.append("Photo line, shown after your words: \(ask)") }
        // The first spelling of each, the one the hand-written line uses.
        let keep = brief.keep.compactMap { $0.split(separator: "|").first.map(String.init) }
        if !keep.isEmpty { lines.append("Words to keep: \(keep.joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }

    /// True when every entry of `keep` is in `text`: "friend|someone" by either, "rain" also as
    /// "rains", "rained" or "raining". Whole words, so "read" is never kept by "ready".
    static func keeps(_ keep: [String], in text: String) -> Bool {
        let lowered = text.lowercased()
        let found = IdeaGuard.words(in: lowered)
        let endings = ["", "s", "es", "d", "ed", "ing"]
        return keep.allSatisfy { entry in
            entry.split(separator: "|").contains { spelling in
                let spelling = spelling.lowercased()
                if spelling.contains(" ") { return lowered.contains(spelling) }
                return endings.contains { found.contains(spelling + $0) }
            }
        }
    }

    /// What the screen already shows beside the idea: the day, the time of day, the distance.
    /// A rewrite that adds one repeats the screen ("in the morning" under "an idea for Wednesday
    /// morning"); one the hand-written line already had may stay.
    static let screenWords: Set<String> = [
        "morning", "afternoon", "evening", "tonight", "today", "tomorrow", "nearby", "weekend",
    ]
    static let screenPhrases = ["walk away", "minutes away", "minute walk", "short walk", "around the corner", "down the street"]

    /// A real short sentence, not a placeholder such as "none": three words or more, starting
    /// with a capital, at most 100 characters.
    static func isSentence(_ text: String) -> Bool {
        let words = text.split(whereSeparator: { $0 == " " })
        guard words.count >= 3, text.count <= 100, text.first?.isUppercase == true else { return false }
        let start = text.lowercased()
        return !["none", "n/a", "empty", "no why"].contains { start.hasPrefix($0) }
    }

    /// One line of plain text, ending in a full stop.
    static func tidy(_ raw: String) -> String {
        var text = raw.split(whereSeparator: \.isNewline).joined(separator: " ")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespaces)
        if let last = text.last, last.isLetter || last.isNumber { text += "." }
        return text
    }

    /// The checks a rewrite has to pass. When in doubt, no.
    static func accepts(text: String, reason: String, for brief: Brief) -> Bool {
        guard (8...80).contains(text.count), (12...160).contains(reason.count) else { return false }
        // The place, by its own name.
        let place = brief.place.replacingOccurrences(of: "\u{2019}", with: "'")
        guard text.contains(place) else { return false }
        // An idea, not just the place's name: it starts with what to do and says something more.
        let around = text.replacingOccurrences(of: place, with: " ")
        guard !text.hasPrefix(place), IdeaGuard.words(in: around.lowercased()).count >= 2 else { return false }
        // Asks for a picture once, in the app's own words, and nowhere else mentions one.
        let lowered = reason.lowercased()
        let askCount = photoAsks.reduce(0) { $0 + lowered.components(separatedBy: $1).count - 1 }
        guard askCount == 1 else { return false }
        let pictureWords: Set<String> = ["photo", "photos", "pic", "pics", "picture", "pictures", "camera", "selfie"]
        guard IdeaGuard.words(in: text.lowercased()).isDisjoint(with: pictureWords) else { return false }
        let why = split(reason).why
        guard IdeaGuard.words(in: why.lowercased()).isDisjoint(with: pictureWords) else { return false }
        let both = "\(text) \(reason)"
        // No dashes, exclamation marks, quotation marks or emoji.
        let banned: Set<Character> = ["\u{2014}", "\u{2013}", "!", "\"", "\u{201C}", "\u{201D}"]
        guard !both.contains(where: { banned.contains($0) }),
              !both.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) else { return false }
        // No numbers at all, so no made-up hours, prices or distances.
        guard !both.contains(where: \.isNumber) else { return false }
        // The activity survives: every word it hangs on, in the idea or the why. The photo line
        // does not count, since it is kept whatever the model writes.
        guard keeps(brief.keep, in: "\(text) \(why)") else { return false }
        // Nothing the screen already says, unless the hand-written words said it.
        let original = "\(brief.text) \(brief.reason)".lowercased()
        let said = IdeaGuard.words(in: original)
        let added = IdeaGuard.words(in: "\(text) \(why)".lowercased()).subtracting(said)
        guard added.isDisjoint(with: screenWords) else { return false }
        let rewritten = "\(text) \(why)".lowercased()
        guard !screenPhrases.contains(where: { rewritten.contains($0) && !original.contains($0) }) else { return false }
        // The same checks as every hand-written line.
        guard IdeaGuard.isSafeText(text), IdeaGuard.isSafeText(reason) else { return false }
        if brief.isBusiness, !IdeaGuard.makesNoBusinessClaims(text) || !IdeaGuard.makesNoBusinessClaims(reason) {
            return false
        }
        return true
    }
}

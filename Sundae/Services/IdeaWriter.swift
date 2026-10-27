import Foundation
import FoundationModels

/// Fresh words for ideas near you, from Apple's on-device model, on iPhones with Apple
/// Intelligence. It costs nothing, works offline, and nothing it reads or writes leaves the phone.
///
/// The model only rewords the idea and the why. The photo ask is never its to write: the
/// hand-written one is kept word for word, so an idea never asks for a picture twice. Each idea
/// keeps its place and its activity, and the model is told nothing that is not already true: the
/// place's name and kind, the part of the day, the walk, the rain. Every rewrite must pass the
/// same checks as the hand-written lines, and a few more, or the hand-written line stays. Phones
/// without the model keep the hand-written lines.
enum IdeaWriter {
    /// Everything the model is told about one idea.
    struct Brief: Sendable {
        let place: String
        /// What kind of place, in plain words: "bakery", "hiking trail".
        let kind: String
        /// Businesses may only be described by what any place of their kind does.
        let isBusiness: Bool
        let timeOfDay: Suggestion.TimeOfDay
        let walkMinutes: Int?
        let isRaining: Bool
        let text: String
        let reason: String
    }

    @Generable
    struct Wording {
        @Guide(description: "The idea: one short sentence that names the place exactly as given. No mention of photos.")
        var idea: String
        @Guide(description: "Why it is worth doing: one short sentence with no mention of photos. Empty when no why is given.")
        var why: String
    }

    /// True on an iPhone with Apple Intelligence turned on and the model ready.
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    static let instructions = """
        You reword the daily idea in Sundae, a photo app for a small group of friends. Each idea \
        sends someone to one real place near them.

        Rewrite the idea, and the why when one is given, in fresh, warm, plain words, like a \
        friend suggesting it. Keep the same place and the same activity, and keep it something a \
        person can really do at that kind of place. Write the place name exactly as given.

        The app adds the photo to take on its own, so never mention photos, pictures or cameras.

        You know nothing about the place beyond its name and its kind. Never describe it or say \
        what it has: name no particular food, drink or dish, and no menus, prices, hours, staff, \
        seating, views or events.

        Mention the walk or the rain only when given. Never mention alcohol, strangers, children, \
        danger, or being out alone at night.

        The idea is one sentence of at most 70 characters. The why is one sentence of at most 90 \
        characters, or empty when none is given. No emoji, exclamation marks, quotation marks or \
        dashes.
        """

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
                let why = tidy(response.content.why)
                guard !why.isEmpty, why.count <= 100 else { return nil }
                reason = "\(why) \(parts.ask)"
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

    static func prompt(for brief: Brief, why: String) -> String {
        var lines = [
            "Place: \(brief.place)",
            "Kind of place: \(brief.kind)",
            "Part of the day: \(brief.timeOfDay.rawValue)",
        ]
        if let minutes = brief.walkMinutes { lines.append("Getting there: a \(minutes) minute walk") }
        if brief.isRaining { lines.append("Weather: rain") }
        lines.append("Idea to reword: \(brief.text)")
        lines.append(why.isEmpty ? "Why to reword: none, so leave the why empty" : "Why to reword: \(why)")
        return lines.joined(separator: "\n")
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
        // No number it was not given, so no made-up hours, prices or distances.
        let numbers = both.split(whereSeparator: { !$0.isNumber }).map(String.init)
        if numbers.contains(where: { $0 != brief.walkMinutes.map(String.init) }) { return false }
        // The same checks as every hand-written line.
        guard IdeaGuard.isSafeText(text), IdeaGuard.isSafeText(reason) else { return false }
        if brief.isBusiness, !IdeaGuard.makesNoBusinessClaims(text) || !IdeaGuard.makesNoBusinessClaims(reason) {
            return false
        }
        return true
    }
}

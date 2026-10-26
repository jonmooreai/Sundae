import Foundation
import FoundationModels

/// Fresh words for ideas near you, from Apple's on-device model, on iPhones with Apple
/// Intelligence. It costs nothing, works offline, and nothing it reads or writes leaves the phone.
///
/// The model only rewords. Each idea keeps its place and its activity, and is told nothing that
/// is not already true: the place's name and kind, the part of the day, the walk, the rain. Every
/// rewrite must pass the same checks as the hand-written lines, and a few more, or the
/// hand-written line stays. Phones without the model keep the hand-written lines.
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
        @Guide(description: "The idea: one short sentence that names the place exactly as given.")
        var idea: String
        @Guide(description: "Why, and the photo to take: one or two short sentences that ask for a picture with Take a photo or Snap a pic.")
        var reason: String
    }

    /// True on an iPhone with Apple Intelligence turned on and the model ready.
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    static let instructions = """
        You reword the daily idea in Sundae, a photo app for a small group of friends. Each idea \
        sends someone to one real place near them and asks for one photo there.

        Rewrite the idea and the reason you are given in fresh, warm, plain words, like a friend \
        suggesting it. Keep the same place and the same activity. Write the place name exactly as \
        given.

        You know nothing about the place beyond its name and its kind. Never describe it or say \
        what it has: name no particular food, drink or dish, and no menus, prices, hours, staff, \
        seating, views or events.

        Mention the walk or the rain only when given. Never mention alcohol, strangers, children, \
        danger, or being out alone at night.

        The idea is one sentence of at most 70 characters. The reason is one or two sentences of \
        at most 120 characters, and asks for a picture using exactly the words Take a photo or \
        Snap a pic. No emoji, exclamation marks, quotation marks or dashes.
        """

    /// The idea in fresh words, or nil to keep the hand-written line. Never throws.
    static func reword(_ brief: Brief) async -> (text: String, reason: String)? {
        let session = LanguageModelSession(instructions: instructions)
        do {
            // Greedy, so the same idea is worded the same way each time the day's ideas are looked up.
            let response = try await session.respond(to: prompt(for: brief), generating: Wording.self,
                                                     options: GenerationOptions(sampling: .greedy))
            let text = tidy(response.content.idea)
            let reason = tidy(response.content.reason)
            return accepts(text: text, reason: reason, for: brief) ? (text, reason) : nil
        } catch {
            // Unavailable, busy, or refused by Apple's own guardrails: the hand-written line it is.
            return nil
        }
    }

    static func prompt(for brief: Brief) -> String {
        var lines = [
            "Place: \(brief.place)",
            "Kind of place: \(brief.kind)",
            "Part of the day: \(brief.timeOfDay.rawValue)",
        ]
        if let minutes = brief.walkMinutes { lines.append("Getting there: a \(minutes) minute walk") }
        if brief.isRaining { lines.append("Weather: rain") }
        lines.append("Idea to reword: \(brief.text)")
        lines.append("Reason to reword: \(brief.reason)")
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
        // Still asks for a picture, in the app's own words.
        let asks = reason.lowercased()
        guard ["take a photo", "take photos", "snap a pic"].contains(where: { asks.contains($0) }) else { return false }
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

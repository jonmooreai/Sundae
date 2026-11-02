import Foundation
import FoundationModels

/// Fresh ideas for the week from Apple's on-device model, on iPhones with Apple Intelligence,
/// alongside the hand-written ones in suggestions.json. It costs nothing, works offline, and
/// nothing it reads or writes leaves the phone.
///
/// The model is told only the season and a different angle for each day ("a small kindness for
/// someone you love"), never anything about the person: no place, no name, no history. It is
/// shown a few hand-written ideas for their tone, writes one idea at a time, and every idea must
/// pass the checks the hand-written ones do, and stricter ones, or it is dropped and the day keeps
/// a hand-written idea. Phones without the model only ever see hand-written ideas.
enum WeekIdeaWriter {
    @Generable
    struct Draft {
        @Guide(description: "The idea: one short sentence that starts with a verb. One small, specific thing to go and do. No names, no numbers, no mention of photos.")
        var idea: String
        @Guide(description: "Why it is worth doing: one short, warm sentence. No mention of photos.")
        var why: String
    }

    /// True on an iPhone with Apple Intelligence turned on and the model ready.
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// What a day's idea is about. Consecutive days get consecutive angles, and with twenty of
    /// them each week starts somewhere new.
    struct Angle: Sendable {
        let words: String
        let category: Suggestion.Category
    }

    static let angles: [Angle] = [
        Angle(words: "a small kindness for someone you love", category: .people),
        Angle(words: "food you make, share or try for the first time", category: .food),
        Angle(words: "a little adventure outdoors", category: .outdoors),
        Angle(words: "noticing what the season is doing around you", category: .outdoors),
        Angle(words: "making something with your hands", category: .creative),
        Angle(words: "a slow, cozy moment at home", category: .creative),
        Angle(words: "time with a friend", category: .people),
        Angle(words: "seeing your own neighborhood with fresh eyes", category: .local),
        Angle(words: "trying something you have never done", category: .creative),
        Angle(words: "a small ritual that makes the day feel special", category: .creative),
        Angle(words: "color, light or texture you would usually walk past", category: .creative),
        Angle(words: "something you loved when you were little", category: .creative),
        Angle(words: "a book, a song or a film", category: .creative),
        Angle(words: "moving your body somewhere green", category: .outdoors),
        Angle(words: "an old thing you love and the story behind it", category: .creative),
        Angle(words: "plants, trees or animals near you", category: .outdoors),
        Angle(words: "a local spot you have never been into", category: .local),
        Angle(words: "a treat or a meal somewhere new", category: .food),
        Angle(words: "a note or a visit for someone you miss", category: .people),
        Angle(words: "a corner of your town you only ever pass through", category: .local),
    ]

    static func angle(for day: Date, calendar: Calendar, attempt: Int = 0) -> Angle {
        let ordinal = calendar.ordinality(of: .day, in: .era, for: day) ?? 0
        // A second try takes the angle half a cycle away, never one another day this week has.
        return angles[(ordinal + attempt * angles.count / 2) % angles.count]
    }

    // MARK: - The season

    private static let months = ["January", "February", "March", "April", "May", "June", "July",
                                 "August", "September", "October", "November", "December"]

    /// "late autumn, November": the season where the phone is, from the month and which half of
    /// the world its time zone is in. Only the season is told to the model, never the place.
    static func season(for date: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: date)
        let seasons = ["winter", "spring", "summer", "autumn"]
        // December, January and February are winter in the north and summer in the south.
        let index = (month % 12) / 3
        let name = seasons[(index + (isSouthern(calendar.timeZone) ? 2 : 0)) % 4]
        let part = ["early", "the middle of", "late"][(month % 12) % 3]
        return "\(part) \(name), \(months[max(0, min(11, month - 1))])"
    }

    /// Time zones south of the equator, where the seasons are the other way round.
    static func isSouthern(_ zone: TimeZone) -> Bool {
        let id = zone.identifier
        let prefixes = ["Australia/", "Antarctica/", "America/Argentina/"]
        let zones: Set<String> = [
            "Pacific/Auckland", "Pacific/Chatham", "Pacific/Fiji", "Pacific/Tongatapu", "Pacific/Apia", "Pacific/Noumea",
            "America/Santiago", "America/Punta_Arenas", "America/Sao_Paulo", "America/Montevideo", "America/Asuncion",
            "America/La_Paz", "America/Lima", "Atlantic/Stanley",
            "Africa/Johannesburg", "Africa/Maputo", "Africa/Windhoek", "Africa/Harare", "Africa/Lusaka",
            "Africa/Gaborone", "Africa/Maseru", "Africa/Mbabane", "Africa/Blantyre", "Africa/Lubumbashi",
            "Indian/Mauritius", "Indian/Reunion", "Indian/Antananarivo",
        ]
        return zones.contains(id) || prefixes.contains { id.hasPrefix($0) }
    }

    // MARK: - Writing

    /// The rules, most important first, then hand-written ideas to match: a small model copies
    /// examples far more faithfully than it follows rules.
    static func instructions(examples: [Suggestion]) -> String {
        let rules = """
            You write ideas for Sundae, a photo app for a small group of friends. Each day the app \
            suggests one small, specific thing to go and do, with a moment in it worth keeping. On \
            Sunday, friends share their week with each other.

            Write one new idea for the angle and the season you are given. It should be easy, free \
            or cheap, safe, and something almost anyone could do this week, wherever they live and \
            at any time of day.

            Write like a friend suggesting it: warm, plain, specific and gentle. The idea is one \
            short sentence that starts with a verb, at most 60 characters. The why is one short \
            sentence that makes it feel worth doing, at most 90 characters.

            Never name a real place, business, brand, person, holiday, day or month, and never use \
            numbers. Never mention alcohol, strangers, children, danger, money, or being out at \
            night. Never mention photos, pictures or cameras: the app asks for those itself.

            No emoji, exclamation marks, quotation marks, colons or dashes.
            """
        let shown = examples.map { "- \($0.text) \($0.reason)" }.joined(separator: "\n")
        return "\(rules)\n\nIdeas Sundae already has. Match their tone, but never repeat them:\n\(shown)"
    }

    /// The season, the day's angle, and what this week already has.
    static func prompt(season: String, angle: Angle, thisWeek: [String]) -> String {
        var lines = ["Season: \(season)", "Angle: \(angle.words)"]
        if !thisWeek.isEmpty {
            lines.append("Already chosen this week, so choose something different:")
            lines += thisWeek.map { "- \($0)" }
        }
        lines.append("Write one new idea.")
        return lines.joined(separator: "\n")
    }

    /// Six hand-written ideas to show the model, half of them about the same kind of thing as the
    /// angle when there are enough. Only ideas that would pass the checks themselves.
    static func examples(for angle: Angle, from catalog: SuggestionCatalog) -> [Suggestion] {
        let fitting = catalog.all.filter { accepts(text: $0.text, reason: $0.reason, avoiding: []) }
        let same = Array(fitting.filter { $0.categories.contains(angle.category) }.shuffled().prefix(3))
        let rest = Array(fitting.filter { idea in !same.contains(idea) }.shuffled().prefix(6 - same.count))
        return same + rest
    }

    /// A new idea for `day`, or nil when the model is unavailable or nothing it wrote passed.
    /// Tried twice, from two angles. Never throws.
    static func idea(for day: Date, calendar: Calendar, catalog: SuggestionCatalog,
                     thisWeek: [String], avoiding: [String]) async -> Suggestion? {
        let when = season(for: day, calendar: calendar)
        for attempt in 0..<2 {
            let slant = angle(for: day, calendar: calendar, attempt: attempt)
            let session = LanguageModelSession(instructions: instructions(examples: examples(for: slant, from: catalog)))
            do {
                let response = try await session.respond(to: prompt(season: when, angle: slant, thisWeek: thisWeek),
                                                         generating: Draft.self, options: GenerationOptions(temperature: 0.9))
                let text = IdeaWriter.tidy(response.content.idea)
                let reason = IdeaWriter.tidy(response.content.why)
                guard accepts(text: text, reason: reason, avoiding: avoiding + thisWeek) else { continue }
                return Suggestion(id: Suggestion.writtenID(for: day, calendar: calendar), text: text, reason: reason,
                                  categories: [slant.category], timeOfDay: .any)
            } catch {
                // Unavailable, busy, or refused by Apple's own guardrails: try the other angle.
                continue
            }
        }
        return nil
    }

    // MARK: - The checks

    /// Words that ask for a picture. The app asks for those itself.
    static let pictureWords: Set<String> = [
        "photo", "photos", "pic", "pics", "picture", "pictures", "camera", "cameras", "selfie", "selfies",
        "snapshot", "snapshots", "photography", "photographer", "photogenic",
    ]

    /// Stricter than IdeaGuard, for words nobody checked by hand: nothing after dark, nothing with
    /// fire, water or heights, nothing about money, bodies, faith or dates, and nothing the screen
    /// already says beside the idea.
    static let avoidedWords: Set<String> = Set([
        "night", "nights", "nighttime", "midnight", "dark", "darkness", "stars", "stargazing", "sunrise", "dawn",
        "fire", "fires", "bonfire", "campfire", "firework", "fireworks", "flame", "flames",
        "climb", "climbing", "swim", "swimming", "dive", "diving", "jump", "frozen", "ice",
        "forage", "foraging", "mushroom", "mushrooms", "wild",
        "money", "cash", "price", "prices", "expensive", "dollar", "dollars",
        "diet", "calorie", "calories", "weight", "pray", "prayer", "church", "god",
        "date", "dates", "kiss", "ex", "sad", "lonely", "grief", "cry", "crying",
        "online", "internet", "website", "app", "apps",
    ]).union(IdeaWriter.screenWords)

    /// Words an idea may not start with: it starts with something to do.
    static let notVerbs: Set<String> = [
        "i", "you", "your", "we", "our", "my", "this", "that", "these", "the", "a", "an", "it", "its", "there",
        "today", "sometimes", "why", "how", "what", "when", "if", "every", "maybe",
    ]

    static let bannedCharacters: Set<Character> = [
        "\u{2014}", "\u{2013}", "!", "\"", "\u{201C}", "\u{201D}", ":", ";", "#", "@", "*", "(", ")",
    ]

    /// The checks a written idea has to pass. When in doubt, no.
    static func accepts(text: String, reason: String, avoiding others: [String]) -> Bool {
        guard (16...70).contains(text.count), (16...100).contains(reason.count) else { return false }
        // A real sentence each: one for the idea, one or two for the why, each ending in a full stop.
        guard IdeaWriter.isSentence(text), IdeaWriter.isSentence(reason),
              text.hasSuffix("."), reason.hasSuffix("."),
              IdeaWriter.sentences(in: text).count == 1, IdeaWriter.sentences(in: reason).count <= 2 else { return false }
        let both = "\(text) \(reason)"
        // No dashes, colons, exclamation marks, quotation marks, emoji or numbers.
        guard !both.contains(where: { bannedCharacters.contains($0) }), !both.contains(" - "),
              !both.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }),
              !both.contains(where: \.isNumber) else { return false }
        // No names of anything: no place, brand, person, day or month.
        guard namesNothing(text), namesNothing(reason) else { return false }
        let words = IdeaGuard.words(in: both.lowercased())
        guard words.isDisjoint(with: pictureWords), words.isDisjoint(with: avoidedWords) else { return false }
        // The same checks as every hand-written line.
        guard IdeaGuard.isSafeText(text), IdeaGuard.isSafeText(reason) else { return false }
        // Starts with what to do.
        guard let first = text.split(separator: " ").first.map({ $0.lowercased().filter(\.isLetter) }),
              !notVerbs.contains(first) else { return false }
        // Something new, not a near copy of an idea Sundae already has.
        return !isRepeat(text, of: others)
    }

    /// True when only the first word of each sentence has a capital, or "I".
    static func namesNothing(_ text: String) -> Bool {
        for sentence in IdeaWriter.sentences(in: text) {
            for word in sentence.split(separator: " ").dropFirst() {
                let letters = word.drop { !$0.isLetter }
                guard let first = letters.first, first.isUppercase else { continue }
                if letters == "I" || letters.hasPrefix("I'") { continue }
                return false
            }
        }
        return true
    }

    /// Small words that say nothing about what an idea is.
    static let fillerWords: Set<String> = [
        "a", "an", "the", "to", "of", "and", "or", "for", "in", "on", "at", "with", "your", "you", "it", "its",
        "from", "by", "some", "one", "that", "this", "as", "up", "out", "into", "be", "is", "are", "something",
        "someone", "somewhere", "new", "own", "just", "all", "go", "get",
    ]

    /// True when half or more of the idea's own words are another idea's: "Watch the sunset from
    /// a hill" against "Watch the sunset from somewhere high".
    static func isRepeat(_ text: String, of others: [String]) -> Bool {
        let mine = IdeaGuard.words(in: text.lowercased()).subtracting(fillerWords)
        guard !mine.isEmpty else { return true }
        return others.contains { other in
            let theirs = IdeaGuard.words(in: other.lowercased()).subtracting(fillerWords)
            let union = mine.union(theirs).count
            return union > 0 && Double(mine.intersection(theirs).count) / Double(union) >= 0.5
        }
    }
}

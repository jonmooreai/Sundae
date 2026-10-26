import Foundation

/// The last word on whether an idea may be shown. Every idea, from the bundled catalog, from
/// Apple Maps, from the demo backend or from a server, passes through here before it reaches a
/// screen or a widget. When in doubt it says no, and the app falls back to a catalog idea.
///
/// Three checks:
/// - the words: nothing violent, nothing aimed at strangers, kids or staff, no alcohol or
///   drugs, nothing risky. Taking a picture is only ever "take a photo", "take photos",
///   "take a photograph" or "snap a pic"; "shoot", "capture" or a bare "photograph" fail.
/// - business lines: nothing a place of that kind might not have. No meals, hours, counters,
///   menus, mugs or seating; the copy only says what any café, bakery or shop does.
/// - the place: no memorials, cemeteries, places of worship, hospitals, schools, prisons,
///   police or military sites. A playful idea at a solemn place is wrong however it is worded.
public enum IdeaGuard {
    /// Whole words that never appear in an idea.
    static let blockedWords: Set<String> = [
        // Violence, and words that read as violence out of context.
        "shoot", "shoots", "shooting", "shot", "shots", "gun", "guns", "rifle", "pistol", "weapon", "weapons",
        "kill", "kills", "killing", "murder", "stab", "knife", "knives", "bomb", "bombs", "explode", "explosion",
        "attack", "fight", "fighting", "punch", "hunt", "hunting", "blood", "bleed", "dead", "death", "die",
        "dying", "corpse", "war", "wars", "battle", "target", "trigger", "ammo", "hostage", "victim", "victims",
        // People who did not sign up to be in your photos.
        "guard", "guards", "stranger", "strangers", "crowd", "crowds", "faces", "kid", "kids", "child",
        "children", "toddler", "baby", "babies", "teen", "teens",
        // Alcohol, drugs, smoking.
        "wine", "beer", "beers", "cocktail", "cocktails", "drunk", "alcohol", "booze", "liquor",
        "drug", "drugs", "weed", "smoke", "smoking", "vape",
        // Risk.
        "trespass", "trespassing", "sneak", "dare", "cliff", "cliffs", "tracks", "rooftop", "roof",
        // Solemn places, in case one is named in the copy itself.
        "memorial", "cemetery", "grave", "graves", "funeral", "hospital", "prison", "jail",
        // Any other way of asking for a picture.
        "capture", "captures", "capturing", "photograph", "photographs", "photographing", "photographed",
        "snap", "snaps", "snapping",
    ]

    /// The only ways an idea may ask for a picture. Removed before the word check, so the words
    /// in them do not trip it; anywhere else those words fail.
    static let approvedPhotoPhrases: [String] = [
        "take a photograph", "take photographs", "snap a pic",
    ]

    /// Words a line about a business may not use, because a place of that kind might not have
    /// the thing: a meal, a time, a counter, a menu, a seat by the window.
    static let businessClaimWords: Set<String> = [
        "breakfast", "brunch", "lunch", "dinner", "supper", "counter", "counters", "mug", "mugs", "menu",
        "menus", "special", "specials", "booth", "booths", "window", "windows", "patio", "closing",
        "closes", "close", "open", "opens", "opening", "late", "tonight", "early", "warm", "fresh", "hot",
        "line", "queue", "staff", "barista", "chef", "owner", "famous", "known", "best", "favorite",
    ]

    /// Phrases checked as plain substrings, for things single words miss.
    static let blockedPhrases: [String] = [
        "no signal", "alone at night", "after dark alone", "photo of them", "photograph them",
        "the person ahead", "people who", "someone you don't know", "open fire", "fire at",
        "photograph the staff", "photograph the cashier", "photograph the line", "photograph the queue",
    ]

    /// Whole words that rule a place out.
    static let sensitivePlaceWords: Set<String> = [
        "memorial", "memorials", "monument", "cemetery", "cemeteries", "graveyard", "grave", "tomb",
        "mausoleum", "crypt", "funeral", "mortuary", "crematory", "crematorium", "burial",
        "church", "cathedral", "chapel", "basilica", "mosque", "masjid", "synagogue", "temple", "shrine",
        "parish", "abbey", "monastery", "gurdwara",
        "hospital", "clinic", "medical", "hospice", "emergency", "urgent", "rehab", "rehabilitation",
        "prison", "jail", "correctional", "detention", "penitentiary", "courthouse", "court",
        "police", "sheriff", "military", "armory", "army", "navy", "marine", "marines", "veteran",
        "veterans", "va", "war", "battlefield", "holocaust", "genocide", "massacre", "remembrance",
        "school", "elementary", "kindergarten", "preschool", "daycare", "shelter",
    ]

    public static func isSafe(_ suggestion: Suggestion) -> Bool {
        guard isSafeText(suggestion.text), isSafeText(suggestion.reason) else { return false }
        if let place = suggestion.place, !isSafePlace(named: place.name) { return false }
        return true
    }

    /// Drops anything that fails, keeping the order of the rest.
    public static func filter(_ suggestions: [Suggestion]) -> [Suggestion] {
        suggestions.filter(isSafe)
    }

    public static func isSafeText(_ text: String) -> Bool {
        var lower = text.lowercased()
        if blockedPhrases.contains(where: { lower.contains($0) }) { return false }
        for phrase in approvedPhotoPhrases { lower = lower.replacingOccurrences(of: phrase, with: " ") }
        return words(in: lower).isDisjoint(with: blockedWords)
    }

    /// For lines about a café, a shop, a restaurant: true when nothing in them assumes what the
    /// place has or when it is open.
    public static func makesNoBusinessClaims(_ text: String) -> Bool {
        words(in: text.lowercased()).isDisjoint(with: businessClaimWords)
    }

    public static func isSafePlace(named name: String) -> Bool {
        words(in: name.lowercased()).isDisjoint(with: sensitivePlaceWords)
    }

    /// Letters only, so "Warwick Park" is "warwick" and "park", never "war".
    static func words(in text: String) -> Set<String> {
        Set(text.split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map { $0.replacingOccurrences(of: "'s", with: "").replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty })
    }
}

import Foundation

/// One weekday suggestion. Every suggestion is something you could photograph.
public struct Suggestion: Codable, Identifiable, Hashable, Sendable {
    public enum Category: String, Codable, Sendable, CaseIterable {
        case outdoors, food, people, creative, local
    }

    public enum TimeOfDay: String, Codable, Sendable, CaseIterable {
        case morning, afternoon, evening, any

        public static func current(for date: Date, calendar: Calendar) -> TimeOfDay {
            let hour = calendar.component(.hour, from: date)
            if hour < 12 { return .morning }
            if hour < 17 { return .afternoon }
            return .evening
        }
    }

    public let id: String
    public let text: String
    public let reason: String
    public let categories: [Category]
    public let timeOfDay: TimeOfDay

    public init(id: String, text: String, reason: String, categories: [Category], timeOfDay: TimeOfDay) {
        self.id = id
        self.text = text
        self.reason = reason
        self.categories = categories
        self.timeOfDay = timeOfDay
    }
}

/// The curated list, bundled as JSON. Server-managed later; fixed for v1.
public struct SuggestionCatalog: Sendable {
    public let all: [Suggestion]

    public init(_ all: [Suggestion]) {
        self.all = all
    }

    public static func bundled(_ bundle: Bundle = .main) -> SuggestionCatalog {
        guard let url = bundle.url(forResource: "suggestions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Suggestion].self, from: data) else {
            return SuggestionCatalog([
                Suggestion(id: "fallback", text: "Walk a neighborhood you don't know.",
                           reason: "Pick a direction and take the first street that looks interesting.",
                           categories: [.outdoors], timeOfDay: .any),
            ])
        }
        return SuggestionCatalog(list)
    }

    public func suggestion(id: String) -> Suggestion? {
        all.first { $0.id == id }
    }

    /// Suggestions that fit the time of day. Falls back to the whole list rather than returning nothing.
    public func candidates(for date: Date, calendar: Calendar) -> [Suggestion] {
        let slot = Suggestion.TimeOfDay.current(for: date, calendar: calendar)
        let fitting = all.filter { $0.timeOfDay == .any || $0.timeOfDay == slot }
        return fitting.isEmpty ? all : fitting
    }

    /// Deterministic pick for a given day, so the widget and the app agree before anyone shuffles.
    public func suggestion(forDay date: Date, calendar: Calendar) -> Suggestion? {
        let pool = candidates(for: date, calendar: calendar)
        guard !pool.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return pool[abs(day) % pool.count]
    }

    /// A different suggestion than `current`, chosen at random from what fits right now.
    public func shuffle(from current: Suggestion?, for date: Date, calendar: Calendar, excluding done: Set<String> = []) -> Suggestion? {
        var pool = candidates(for: date, calendar: calendar).filter { $0.id != current?.id && !done.contains($0.id) }
        if pool.isEmpty { pool = all.filter { $0.id != current?.id } }
        return pool.randomElement()
    }
}

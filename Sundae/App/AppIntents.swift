import AppIntents
import Foundation

/// "Show today's Sundae suggestion" and "mark it done" for Siri and Shortcuts.
/// Both work from the shared catalog and app-group defaults, so they never need the UI.
struct ShowSuggestionIntent: AppIntent {
    static let title: LocalizedStringResource = "Show today's suggestion"
    static let description = IntentDescription("One thing to go do this week, and how long until Sunday.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clock = SundayClock()
        if clock.isSunday() {
            return .result(dialog: "It's Sunday. Come share your week.")
        }
        let now = clock.now()
        let catalog = SuggestionCatalog.bundled()
        let shared = SharedDefaults()
        let suggestion: Suggestion?
        if let id = shared.currentSuggestionID(on: now, calendar: clock.calendar),
           let s = TodaysIdea.find(id, clock: clock, catalog: catalog, shared: shared) {
            suggestion = s
        } else {
            suggestion = TodaysIdea.automatic(clock: clock, catalog: catalog, shared: shared)
            if let suggestion { shared.setCurrentSuggestion(id: suggestion.id, on: now) }
        }
        guard let suggestion else {
            return .result(dialog: "Go make something worth posting.")
        }
        let days = clock.daysUntilSunday()
        let countdown = days == 1 ? "Sunday is tomorrow." : "\(days) days until Sunday."
        return .result(dialog: "\(suggestion.text) \(suggestion.reason) \(countdown)")
    }
}

struct MarkSuggestionDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark today's suggestion done"
    static let description = IntentDescription("Sunday's compose screen will remind you to add the photos.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clock = SundayClock()
        let now = clock.now()
        let shared = SharedDefaults()
        let catalog = SuggestionCatalog.bundled()
        let id = shared.currentSuggestionID(on: now, calendar: clock.calendar)
            ?? TodaysIdea.automatic(clock: clock, catalog: catalog, shared: shared)?.id
        guard let id, let suggestion = TodaysIdea.find(id, clock: clock, catalog: catalog, shared: shared) else {
            return .result(dialog: "Nothing to mark today.")
        }
        var done = shared.doneSuggestions()
        done[id] = now
        shared.setDoneSuggestions(done)
        if suggestion.isNearby {
            // Tomorrow's nearby ideas replace today's, so Sunday keeps this one whole.
            shared.setDoneLocalSuggestions(shared.doneLocalSuggestions().filter { $0.id != id } + [suggestion])
        }
        return .result(dialog: "Done: \(suggestion.text) Sunday will remind you to add the photos.")
    }
}

/// Today's idea for Siri, found the way the app finds it: today's nearby ideas, this week's
/// ideas written on the phone, then the catalog.
enum TodaysIdea {
    static func find(_ id: String, clock: SundayClock, catalog: SuggestionCatalog, shared: SharedDefaults) -> Suggestion? {
        let now = clock.now()
        let local = shared.localIdeas(on: now, calendar: clock.calendar) ?? []
        let written = shared.writtenIdeas(forWeekStarting: clock.weekStart(), calendar: clock.calendar)
        return local.first { $0.id == id } ?? written.first { $0.id == id } ?? catalog.suggestion(id: id)
    }

    /// The day's pick before anyone shuffles.
    static func automatic(clock: SundayClock, catalog: SuggestionCatalog, shared: SharedDefaults) -> Suggestion? {
        let written = shared.writtenIdeas(forWeekStarting: clock.weekStart(), calendar: clock.calendar)
        return catalog.suggestion(forDay: clock.now(), calendar: clock.calendar, written: written,
                                  done: Set(shared.doneSuggestions().keys))
    }
}

struct SundaeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowSuggestionIntent(),
            phrases: [
                "Show today's \(.applicationName) suggestion",
                "What's my \(.applicationName) idea",
                "What should I do today in \(.applicationName)",
            ],
            shortTitle: "Sundae",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: MarkSuggestionDoneIntent(),
            phrases: [
                "Mark my \(.applicationName) suggestion done",
                "I did today's \(.applicationName) idea",
            ],
            shortTitle: "Mark done",
            systemImageName: "checkmark"
        )
    }
}

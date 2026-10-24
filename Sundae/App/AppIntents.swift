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
            return .result(dialog: "It's Sunday. Post your week.")
        }
        let now = clock.now()
        let catalog = SuggestionCatalog.bundled()
        let shared = SharedDefaults()
        let suggestion: Suggestion?
        if let id = shared.currentSuggestionID(on: now, calendar: clock.calendar), let s = catalog.suggestion(id: id) {
            suggestion = s
        } else {
            suggestion = catalog.suggestion(forDay: now, calendar: clock.calendar)
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
            ?? catalog.suggestion(forDay: now, calendar: clock.calendar)?.id
        guard let id, let suggestion = catalog.suggestion(id: id) else {
            return .result(dialog: "Nothing to mark today.")
        }
        var done = shared.doneSuggestions()
        done[id] = now
        shared.setDoneSuggestions(done)
        return .result(dialog: "Done: \(suggestion.text) Sunday will remind you to add the photos.")
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
            shortTitle: "Today's idea",
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

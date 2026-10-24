import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class WeekdayStore {
    private let api: any SundaeAPI
    private let catalog: SuggestionCatalog
    private let shared = SharedDefaults()

    private(set) var current: Suggestion?
    /// Suggestion id to the day it was marked done, this week only.
    private(set) var done: [String: Date] = [:]
    var justMarkedDone = false

    init(api: any SundaeAPI, catalog: SuggestionCatalog) {
        self.api = api
        self.catalog = catalog
    }

    var isCurrentDone: Bool {
        guard let current else { return false }
        return done[current.id] != nil
    }

    func load(clock: SundayClock) {
        let now = clock.now()
        let weekStart = clock.weekStart()
        done = shared.doneSuggestions().filter { $0.value >= weekStart }
        if let id = shared.currentSuggestionID(on: now, calendar: clock.calendar),
           let suggestion = catalog.suggestion(id: id) {
            current = suggestion
        } else {
            current = catalog.suggestion(forDay: now, calendar: clock.calendar)
            if let current { shared.setCurrentSuggestion(id: current.id, on: now) }
        }
        justMarkedDone = false
    }

    func shuffle(clock: SundayClock) {
        let now = clock.now()
        current = catalog.shuffle(from: current, for: now, calendar: clock.calendar, excluding: Set(done.keys))
        if let current { shared.setCurrentSuggestion(id: current.id, on: now) }
        justMarkedDone = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    func markDone(clock: SundayClock) async {
        guard let current else { return }
        let now = clock.now()
        done[current.id] = now
        shared.setDoneSuggestions(done)
        justMarkedDone = true
        Haptics.light()
        try? await api.markSuggestionDone(id: current.id, on: now)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// What the user did this week, oldest first, for the Sunday compose prompt.
    func doneThisWeek(clock: SundayClock) -> [(suggestion: Suggestion, day: Date)] {
        let weekStart = clock.weekStart()
        return shared.doneSuggestions()
            .filter { $0.value >= weekStart }
            .compactMap { id, day in catalog.suggestion(id: id).map { (suggestion: $0, day: day) } }
            .sorted { $0.day < $1.day }
    }
}

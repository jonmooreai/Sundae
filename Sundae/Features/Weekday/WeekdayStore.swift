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
    /// Today's ideas for the user's area, when they asked for them. Preferred over the catalog.
    private(set) var local: [Suggestion] = []
    var justMarkedDone = false
    /// Set when the tenth shuffle in a row lands on the only idea that cannot be shuffled away.
    private(set) var restUntil: Date?
    private var shuffles = 0
    /// Ideas shown today, so Shuffle visits everything once before anything comes round again.
    private var shown: Set<String> = []
    private var shownDay: Date?

    /// The Easter egg at the bottom of the shuffle well.
    static let rest = Suggestion(id: "secret:rest", text: "Put the phone down.",
                                 reason: "That's the idea. Come back in a minute.", categories: [.creative], timeOfDay: .any)

    var isResting: Bool {
        guard let restUntil else { return false }
        return restUntil > Date()
    }

    func endRest() {
        restUntil = nil
    }

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
        shared.setDoneLocalSuggestions(shared.doneLocalSuggestions().filter { done[$0.id] != nil })
        local = clock.isSunday() ? [] : (shared.localIdeas(on: now, calendar: clock.calendar) ?? [])
        if let id = shared.currentSuggestionID(on: now, calendar: clock.calendar), let suggestion = resolve(id),
           IdeaGuard.isSafe(suggestion) {
            current = suggestion
        } else if let nearby = preferredLocal(for: now, calendar: clock.calendar) {
            current = nearby
            shared.setCurrentSuggestion(id: nearby.id, on: now)
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            current = catalog.suggestion(forDay: now, calendar: clock.calendar)
            if let current { shared.setCurrentSuggestion(id: current.id, on: now) }
            WidgetCenter.shared.reloadAllTimelines()
        }
        justMarkedDone = false
    }

    /// Today's nearby ideas arrived or changed. They take over only from the automatic pick:
    /// a suggestion the user shuffled to or finished stays put.
    func applyLocal(_ ideas: [Suggestion], clock: SundayClock) {
        let ideas = IdeaGuard.filter(ideas)
        local = ideas
        let now = clock.now()
        guard let current else {
            load(clock: clock)
            return
        }
        let automatic = catalog.suggestion(forDay: now, calendar: clock.calendar)
        if ideas.isEmpty {
            // Turned off, or a quiet area. A nearby idea that was showing gives way to the catalog.
            if current.isNearby, !isCurrentDone, let automatic {
                self.current = automatic
                shared.setCurrentSuggestion(id: automatic.id, on: now)
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        guard !current.isNearby, !isCurrentDone, current.id == automatic?.id,
              let nearby = preferredLocal(for: now, calendar: clock.calendar) else { return }
        self.current = nearby
        shared.setCurrentSuggestion(id: nearby.id, on: now)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func shuffle(clock: SundayClock) {
        let now = clock.now()
        shuffles += 1
        if shuffles >= 10 {
            shuffles = 0
            current = Self.rest
            restUntil = Date().addingTimeInterval(60)
            justMarkedDone = false
            Haptics.light()
            return
        }
        noteShown(current, on: now, calendar: clock.calendar)
        let slot = Suggestion.TimeOfDay.current(for: now, calendar: clock.calendar)
        let fitting = local.filter { $0.timeOfDay == slot || $0.timeOfDay == .any }
        var openLocal = fitting.filter { $0.id != current?.id && done[$0.id] == nil && !shown.contains($0.id) }
        if openLocal.isEmpty, fitting.count > 1 {
            // Every nearby idea for this part of the day has had its turn; let them come round again.
            for idea in fitting { shown.remove(idea.id) }
            openLocal = fitting.filter { $0.id != current?.id && done[$0.id] == nil }
        }
        // Half the time a nearby idea, while any are left; the catalog otherwise, skipping what
        // has already been on screen today.
        if let nearby = openLocal.randomElement(), Bool.random() {
            current = nearby
        } else {
            current = catalog.shuffle(from: current, for: now, calendar: clock.calendar, excluding: Set(done.keys).union(shown))
        }
        noteShown(current, on: now, calendar: clock.calendar)
        if let current { shared.setCurrentSuggestion(id: current.id, on: now) }
        justMarkedDone = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    func markDone(clock: SundayClock) async {
        guard let current else { return }
        let now = clock.now()
        done[current.id] = now
        shared.setDoneSuggestions(done)
        if current.isNearby {
            var kept = shared.doneLocalSuggestions().filter { $0.id != current.id }
            kept.append(current)
            shared.setDoneLocalSuggestions(kept)
        }
        justMarkedDone = true
        Haptics.light()
        // A nearby idea's id names the day and a slot, nothing about where. Safe to send with the account.
        try? await api.markSuggestionDone(id: current.id, on: now)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// What the user did this week, oldest first, for the Sunday compose prompt.
    func doneThisWeek(clock: SundayClock) -> [(suggestion: Suggestion, day: Date)] {
        let weekStart = clock.weekStart()
        return shared.doneSuggestions()
            .filter { $0.value >= weekStart }
            .compactMap { id, day in resolve(id).map { (suggestion: $0, day: day) } }
            .sorted { $0.day < $1.day }
    }

    private func noteShown(_ suggestion: Suggestion?, on day: Date, calendar: Calendar) {
        if let shownDay, !calendar.isDate(shownDay, inSameDayAs: day) { shown.removeAll() }
        shownDay = day
        if let suggestion { shown.insert(suggestion.id) }
    }

    /// First nearby idea for this part of the day, else any nearby idea, skipping finished ones.
    private func preferredLocal(for date: Date, calendar: Calendar) -> Suggestion? {
        let slot = Suggestion.TimeOfDay.current(for: date, calendar: calendar)
        let open = local.filter { done[$0.id] == nil }
        return open.first { $0.timeOfDay == slot || $0.timeOfDay == .any } ?? open.first
    }

    /// Today's nearby ideas, then the catalog, then nearby ideas finished earlier in the week.
    private func resolve(_ id: String) -> Suggestion? {
        local.first { $0.id == id }
            ?? catalog.suggestion(id: id)
            ?? shared.doneLocalSuggestions().first { $0.id == id }
    }
}

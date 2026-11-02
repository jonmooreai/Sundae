import Foundation
import Observation
import WidgetKit

/// This week's ideas from the phone's own model (WeekIdeaWriter): one for each day left in the
/// week, written the first time Sundae opens on a weekday, today's first. Each day starts with its
/// own, and Shuffle mixes them in with the hand-written ones. They are kept with the widget's state
/// so the widget, Siri and the app show the same idea. Phones without Apple Intelligence never get
/// any and keep the hand-written ideas, as does any day whose idea did not pass the checks.
@MainActor
@Observable
final class WrittenIdeasStore {
    private let catalog: SuggestionCatalog
    private let shared: SharedDefaults
    /// The week whose ideas are all written, so the model is not asked again until next week.
    private static let finishedKey = "writtenIdeas.finishedWeek"
    /// The last few weeks' ideas, so a new week does not repeat them.
    private static let recentKey = "writtenIdeas.recent"
    private static let recentLimit = 36
    /// Raised whenever the way ideas are written changes, so this week's are written again.
    private static let version = 1
    private static let versionKey = "writtenIdeas.version"

    /// This week's written ideas, in the order of their days.
    private(set) var ideas: [Suggestion] = []
    private var inFlight: Task<Void, Never>?

    init(catalog: SuggestionCatalog, shared: SharedDefaults = SharedDefaults()) {
        self.catalog = catalog
        self.shared = shared
    }

    /// Writes what is missing for the rest of the week, when the model is there. Safe to call on
    /// every appearance: it does nothing on Sunday, and nothing once the week is written.
    func refresh(clock: SundayClock) async {
        let calendar = clock.calendar
        let weekStart = clock.weekStart()
        if UserDefaults.standard.integer(forKey: Self.versionKey) != Self.version {
            shared.setWrittenIdeas([], forWeekStarting: weekStart)
            UserDefaults.standard.removeObject(forKey: Self.finishedKey)
            UserDefaults.standard.set(Self.version, forKey: Self.versionKey)
        }
        let stored = shared.writtenIdeas(forWeekStarting: weekStart, calendar: calendar)
        if stored != ideas { ideas = stored }
        // Sunday is for sharing the week, not planning it.
        guard !clock.isSunday() else { return }
        if let finished = UserDefaults.standard.object(forKey: Self.finishedKey) as? Date,
           calendar.isDate(finished, inSameDayAs: weekStart) { return }
        guard WeekIdeaWriter.isAvailable else { return }
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await write(clock: clock, weekStart: weekStart) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Today through Saturday, one idea a day, each kept as soon as it passes so today's shows up
    /// while the rest are still being written.
    private func write(clock: SundayClock, weekStart: Date) async {
        let calendar = clock.calendar
        var avoiding = catalog.all.map(\.text) + (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? [])
        for day in Self.daysLeft(clock: clock) {
            let id = Suggestion.writtenID(for: day, calendar: calendar)
            guard !ideas.contains(where: { $0.id == id }) else { continue }
            // Midnight may have passed into Sunday, or a new week, while the model was writing.
            guard !Task.isCancelled, !clock.isSunday(), clock.weekStart() == weekStart else { return }
            guard let idea = await WeekIdeaWriter.idea(for: day, calendar: calendar, catalog: catalog,
                                                       thisWeek: ideas.map(\.text), avoiding: avoiding),
                  IdeaGuard.isSafe(idea) else { continue }
            ideas.append(idea)
            avoiding.append(idea.text)
            shared.setWrittenIdeas(ideas, forWeekStarting: weekStart)
            remember(idea.text)
            WidgetCenter.shared.reloadAllTimelines()
        }
        // A model that went away part way through gets another go next time.
        if WeekIdeaWriter.isAvailable {
            UserDefaults.standard.set(weekStart, forKey: Self.finishedKey)
        }
    }

    /// Today and every day after it up to Saturday.
    nonisolated static func daysLeft(clock: SundayClock) -> [Date] {
        let calendar = clock.calendar
        var days: [Date] = []
        var day = calendar.startOfDay(for: clock.now())
        while !clock.isSunday(day), days.count < 6 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    private func remember(_ text: String) {
        let recent = (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []) + [text]
        UserDefaults.standard.set(Array(recent.suffix(Self.recentLimit)), forKey: Self.recentKey)
    }
}

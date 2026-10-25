import Foundation

/// Small amount of state shared between the app and the widget through the app group.
/// Nothing sensitive goes here: just which suggestion is showing and the approvals badge.
///
/// `UserDefaults` is documented thread-safe but not marked `Sendable`; the struct holds nothing else.
public struct SharedDefaults: @unchecked Sendable {
    public static let appGroup = "group.com.jonmooreai.sundae"

    /// The app group named in the bundle's Info.plist (`SundaeAppGroup`), or nil when the build has no
    /// app group entitlement. Writing to an unentitled suite is silently dropped, so a build without
    /// the capability keeps its state in standard defaults instead.
    public static var configuredAppGroup: String? {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "SundaeAppGroup") as? String,
              !name.isEmpty else { return nil }
        return name
    }

    private let defaults: UserDefaults

    public init(suite: String? = SharedDefaults.configuredAppGroup) {
        if let suite, let d = UserDefaults(suiteName: suite) {
            defaults = d
        } else {
            defaults = .standard
        }
    }

    private enum Key {
        static let suggestionID = "weekday.suggestionID"
        static let suggestionDay = "weekday.suggestionDay"
        static let doneIDs = "weekday.doneIDs"
        static let pendingApprovals = "approvals.pendingCount"
        static let postedWeekStart = "sunday.postedWeekStart"
        static let localIdeas = "weekday.localIdeas"
        static let localIdeasDay = "weekday.localIdeasDay"
        static let localIdeasFetchedAt = "weekday.localIdeasFetchedAt"
        static let localDone = "weekday.localDone"
    }

    /// The suggestion the user is currently looking at, valid only for the day it was chosen.
    public func currentSuggestionID(on day: Date, calendar: Calendar) -> String? {
        guard let id = defaults.string(forKey: Key.suggestionID),
              let stored = defaults.object(forKey: Key.suggestionDay) as? Date,
              calendar.isDate(stored, inSameDayAs: day) else { return nil }
        return id
    }

    public func setCurrentSuggestion(id: String, on day: Date) {
        defaults.set(id, forKey: Key.suggestionID)
        defaults.set(day, forKey: Key.suggestionDay)
    }

    /// Suggestions marked done this week, keyed by id with the day they were done.
    public func doneSuggestions() -> [String: Date] {
        (defaults.dictionary(forKey: Key.doneIDs) as? [String: Date]) ?? [:]
    }

    public func setDoneSuggestions(_ done: [String: Date]) {
        defaults.set(done, forKey: Key.doneIDs)
    }

    public var pendingApprovalCount: Int {
        get { defaults.integer(forKey: Key.pendingApprovals) }
        nonmutating set { defaults.set(newValue, forKey: Key.pendingApprovals) }
    }

    /// Week start of the most recent dump the user posted, so the widget can stop nagging.
    public var postedWeekStart: Date? {
        get { defaults.object(forKey: Key.postedWeekStart) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.postedWeekStart) }
    }

    // MARK: Ideas near you

    /// Today's ideas for the user's area, if any were fetched today. They carry place names and the
    /// places' positions, never the user's position or the cell that was sent.
    public func localIdeas(on day: Date, calendar: Calendar) -> [Suggestion]? {
        guard let stored = defaults.object(forKey: Key.localIdeasDay) as? Date,
              calendar.isDate(stored, inSameDayAs: day),
              let data = defaults.data(forKey: Key.localIdeas),
              let ideas = try? JSONDecoder().decode([Suggestion].self, from: data) else { return nil }
        return ideas
    }

    public func setLocalIdeas(_ ideas: [Suggestion], at moment: Date) {
        guard let data = try? JSONEncoder().encode(ideas) else { return }
        defaults.set(data, forKey: Key.localIdeas)
        defaults.set(moment, forKey: Key.localIdeasDay)
        defaults.set(moment, forKey: Key.localIdeasFetchedAt)
    }

    /// When the area was last looked at. Drives the once-in-a-while refresh.
    public var localIdeasFetchedAt: Date? {
        defaults.object(forKey: Key.localIdeasFetchedAt) as? Date
    }

    /// Turning the feature off leaves nothing behind.
    public func clearLocalIdeas() {
        defaults.removeObject(forKey: Key.localIdeas)
        defaults.removeObject(forKey: Key.localIdeasDay)
        defaults.removeObject(forKey: Key.localIdeasFetchedAt)
    }

    /// Ideas near you that were marked done this week. The catalog cannot look them up, so the
    /// whole idea is kept for the Sunday prompt.
    public func doneLocalSuggestions() -> [Suggestion] {
        guard let data = defaults.data(forKey: Key.localDone),
              let ideas = try? JSONDecoder().decode([Suggestion].self, from: data) else { return [] }
        return ideas
    }

    public func setDoneLocalSuggestions(_ ideas: [Suggestion]) {
        if let data = try? JSONEncoder().encode(ideas) {
            defaults.set(data, forKey: Key.localDone)
        }
    }
}

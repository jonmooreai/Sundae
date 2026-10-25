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
}

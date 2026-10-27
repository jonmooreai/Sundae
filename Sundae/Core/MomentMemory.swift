import Foundation

/// Which small moments have already had their moment, so each shows once. Device-only.
enum MomentMemory {
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let birthday = "moments.birthdayMonthDay"
        static let birthdayFor = "moments.birthdayFor"
        static let seenSeals = "moments.seenSeals"
        static let shownFirstSundays = "moments.shownFirstSundays"
        static let wrapShown = "moments.wrapShownWeekStart"
        static let anniversaryShown = "moments.anniversaryShownWeekStart"
        static let holidayShown = "moments.holidayShownWeekStart"
    }

    /// "MM-DD" of the user's own birthday. Only the day and month, only on this phone.
    static var birthdayMonthDay: String? {
        get { defaults.string(forKey: Key.birthday) }
        set { defaults.set(newValue, forKey: Key.birthday) }
    }

    /// Signing out puts the birthday away, so whoever signs in next never gets it. The same person
    /// signing back in on this phone gets it back.
    static func signedOut(userID: String?) {
        if let userID, let birthday = birthdayMonthDay {
            defaults.set([userID: birthday], forKey: Key.birthdayFor)
        } else {
            defaults.removeObject(forKey: Key.birthdayFor)
        }
        birthdayMonthDay = nil
    }

    static func signedIn(userID: String) {
        let kept = defaults.dictionary(forKey: Key.birthdayFor) as? [String: String]
        defaults.removeObject(forKey: Key.birthdayFor)
        if let birthday = kept?[userID] { birthdayMonthDay = birthday }
    }

    static func isBirthday(_ date: Date, calendar: Calendar) -> Bool {
        guard let stored = birthdayMonthDay else { return false }
        return monthDay(date, calendar: calendar) == stored
    }

    /// "MM-DD" for a date, matching the format friends' birthdays arrive in.
    static func monthDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", parts.month ?? 1, parts.day ?? 1)
    }

    /// True when a "MM-DD" birthday lands in the week starting `weekStart`.
    static func birthday(_ monthDay: String?, fallsInWeekStarting weekStart: Date, calendar: Calendar) -> Bool {
        guard let monthDay else { return false }
        return (0..<7).contains { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return false }
            return self.monthDay(day, calendar: calendar) == monthDay
        }
    }

    // MARK: Seen once

    static var seenSeals: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.seenSeals) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.seenSeals) }
    }

    static var shownFirstSundays: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.shownFirstSundays) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.shownFirstSundays) }
    }

    static var wrapShownWeekStart: Date? {
        get { defaults.object(forKey: Key.wrapShown) as? Date }
        set { defaults.set(newValue, forKey: Key.wrapShown) }
    }

    static var anniversaryShownWeekStart: Date? {
        get { defaults.object(forKey: Key.anniversaryShown) as? Date }
        set { defaults.set(newValue, forKey: Key.anniversaryShown) }
    }

    /// The week whose holiday hello was waved away.
    static var holidayShownWeekStart: Date? {
        get { defaults.object(forKey: Key.holidayShown) as? Date }
        set { defaults.set(newValue, forKey: Key.holidayShown) }
    }
}

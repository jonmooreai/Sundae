import Foundation

/// Week math for Sundae.
///
/// A week runs Monday 00:00 through Sunday 23:59 in the device's current time zone.
/// The client uses this to decide what to draw. The server is the authority for every
/// write, so nothing here is a security boundary.
public struct SundayClock: Sendable {
    /// Injectable so tests and the debug "pretend it's Sunday" switch can move time.
    public var now: @Sendable () -> Date
    public var calendar: Calendar

    public init(now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current) {
        self.now = now
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2
        self.calendar = cal
    }

    public func isSunday(_ date: Date? = nil) -> Bool {
        calendar.component(.weekday, from: date ?? now()) == 1
    }

    /// Monday 00:00 of the week containing `date`. A Sunday belongs to the week that started six days earlier.
    public func weekStart(containing date: Date? = nil) -> Date {
        let d = date ?? now()
        let weekday = calendar.component(.weekday, from: d)   // 1 = Sunday ... 7 = Saturday
        let daysSinceMonday = (weekday + 5) % 7               // Mon 0, Tue 1, ... Sun 6
        let startOfDay = calendar.startOfDay(for: d)
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay) ?? startOfDay
    }

    /// Sunday 00:00 of the week containing `date`.
    public func sundayStart(forWeekContaining date: Date? = nil) -> Date {
        let start = weekStart(containing: date)
        return calendar.date(byAdding: .day, value: 6, to: start) ?? start
    }

    /// Monday 00:00 of the following week. The dump locks here.
    public func weekEnd(containing date: Date? = nil) -> Date {
        let start = weekStart(containing: date)
        return calendar.date(byAdding: .day, value: 7, to: start) ?? start
    }

    /// 0 on Sunday, otherwise the number of days until the coming Sunday.
    public func daysUntilSunday(from date: Date? = nil) -> Int {
        let weekday = calendar.component(.weekday, from: date ?? now())
        return weekday == 1 ? 0 : 8 - weekday
    }

    /// The next instant the app flips modes: Sunday 00:00 on a weekday, Monday 00:00 on Sunday.
    public func nextBoundary(after date: Date? = nil) -> Date {
        let d = date ?? now()
        return isSunday(d) ? weekEnd(containing: d) : sundayStart(forWeekContaining: d)
    }

    /// Week starts going back from the current week, newest first.
    public func recentWeekStarts(count: Int, endingWith date: Date? = nil) -> [Date] {
        let current = weekStart(containing: date)
        return (0..<max(count, 0)).compactMap { calendar.date(byAdding: .day, value: -7 * $0, to: current) }
    }

    /// "Nov 2nd - Nov 8th": the week from Monday to Sunday, each end with its month.
    public func rangeLabel(weekStart: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(dayLabel(weekStart)) - \(dayLabel(end))"
    }

    /// "Nov 2nd".
    public func dayLabel(_ date: Date) -> String {
        let month = DateFormatter()
        month.calendar = calendar
        month.timeZone = calendar.timeZone
        month.locale = Locale(identifier: "en_US")
        month.dateFormat = "MMM"
        let ordinal = NumberFormatter()
        ordinal.numberStyle = .ordinal
        ordinal.locale = Locale(identifier: "en_US")
        let day = calendar.component(.day, from: date)
        return "\(month.string(from: date)) \(ordinal.string(from: NSNumber(value: day)) ?? "\(day)")"
    }

    /// "Thursday" for a date in the current week, used by the Sunday caption prompt.
    public func weekdayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f.string(from: date)
    }
}

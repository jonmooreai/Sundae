import Foundation
import Testing
@testable import Sundae

/// One Sunday a year dresses up: the one nearest Halloween, and only that day.
struct HalloweenTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func theSundayNearestHalloweenEachYear() {
        for (year, month, day) in [(2026, 11, 1), (2027, 10, 31), (2028, 10, 29), (2029, 10, 28), (2030, 11, 3)] {
            #expect(Halloween.isHalloweenSunday(date(year, month, day), calendar: calendar), "\(year)-\(month)-\(day)")
        }
    }

    @Test func noOtherDay() {
        #expect(!Halloween.isHalloweenSunday(date(2026, 10, 31), calendar: calendar), "Halloween itself is a Saturday this year")
        #expect(!Halloween.isHalloweenSunday(date(2026, 10, 25), calendar: calendar), "a week early")
        #expect(!Halloween.isHalloweenSunday(date(2026, 11, 8), calendar: calendar), "a week late")
        #expect(!Halloween.isHalloweenSunday(date(2026, 11, 2), calendar: calendar), "the Monday after")
    }
}

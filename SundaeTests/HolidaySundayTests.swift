import Foundation
import Testing
import UIKit
@testable import Sundae

/// Three Sundays a year dress up: the ones nearest Valentine's Day, Halloween and Christmas, and
/// only that day.
struct HolidaySundayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func theSundayNearestValentinesDayEachYear() {
        for (year, month, day) in [(2026, 2, 15), (2027, 2, 14), (2028, 2, 13), (2029, 2, 11), (2030, 2, 17)] {
            #expect(HolidaySunday.on(date(year, month, day), calendar: calendar) == .valentines, "\(year)-\(month)-\(day)")
        }
    }

    @Test func theSundayNearestHalloweenEachYear() {
        for (year, month, day) in [(2026, 11, 1), (2027, 10, 31), (2028, 10, 29), (2029, 10, 28), (2030, 11, 3)] {
            #expect(HolidaySunday.on(date(year, month, day), calendar: calendar) == .halloween, "\(year)-\(month)-\(day)")
        }
    }

    @Test func theSundayNearestChristmasEachYear() {
        for (year, month, day) in [(2026, 12, 27), (2027, 12, 26), (2028, 12, 24), (2029, 12, 23), (2030, 12, 22)] {
            #expect(HolidaySunday.on(date(year, month, day), calendar: calendar) == .winter, "\(year)-\(month)-\(day)")
        }
    }

    @Test func noOtherDay() {
        #expect(HolidaySunday.on(date(2026, 10, 31), calendar: calendar) == nil, "Halloween itself is a Saturday this year")
        #expect(HolidaySunday.on(date(2026, 10, 25), calendar: calendar) == nil, "a week early")
        #expect(HolidaySunday.on(date(2026, 11, 8), calendar: calendar) == nil, "a week late")
        #expect(HolidaySunday.on(date(2026, 11, 2), calendar: calendar) == nil, "the Monday after")
        #expect(HolidaySunday.on(date(2026, 12, 20), calendar: calendar) == nil, "five days before Christmas")
        #expect(HolidaySunday.on(date(2026, 2, 8), calendar: calendar) == nil, "a week before Valentine's Day")
    }

    @Test(arguments: HolidaySunday.allCases)
    func everyHolidayHasItsFeltPiece(_ holiday: HolidaySunday) {
        #expect(UIImage(named: holiday.image, in: .main, compatibleWith: nil) != nil, "\(holiday.image) is missing from Assets.xcassets")
    }
}

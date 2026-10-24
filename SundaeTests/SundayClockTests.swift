import Foundation
import Testing
@testable import Sundae

/// Week math against a fixed calendar. October 25, 2026 is a Sunday; the 19th is its Monday.
struct SundayClockTests {
    let zone = TimeZone(identifier: "America/Indiana/Indianapolis")!

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func clock(at moment: Date) -> SundayClock {
        SundayClock(now: { moment }, timeZone: zone)
    }

    @Test func sundayIsSunday() {
        #expect(clock(at: date(2026, 10, 25)).isSunday())
        #expect(!clock(at: date(2026, 10, 24)).isSunday())
        #expect(!clock(at: date(2026, 10, 26)).isSunday())
    }

    @Test func sundayBelongsToTheWeekThatJustEnded() {
        let c = clock(at: date(2026, 10, 25, hour: 23))
        #expect(c.weekStart() == date(2026, 10, 19, hour: 0))
    }

    @Test func mondayStartsANewWeek() {
        let c = clock(at: date(2026, 10, 26, hour: 0))
        #expect(c.weekStart() == date(2026, 10, 26, hour: 0))
    }

    @Test func daysUntilSunday() {
        #expect(clock(at: date(2026, 10, 19)).daysUntilSunday() == 6)
        #expect(clock(at: date(2026, 10, 21)).daysUntilSunday() == 4)
        #expect(clock(at: date(2026, 10, 24)).daysUntilSunday() == 1)
        #expect(clock(at: date(2026, 10, 25)).daysUntilSunday() == 0)
    }

    @Test func boundariesFlipAtMidnight() {
        #expect(clock(at: date(2026, 10, 21)).nextBoundary() == date(2026, 10, 25, hour: 0))
        #expect(clock(at: date(2026, 10, 25)).nextBoundary() == date(2026, 10, 26, hour: 0))
        #expect(clock(at: date(2026, 10, 25)).weekEnd() == date(2026, 10, 26, hour: 0))
    }

    @Test func rangeLabels() {
        let c = clock(at: date(2026, 10, 25))
        #expect(c.rangeLabel(weekStart: date(2026, 10, 19, hour: 0)) == "Oct 19 to 25")
        #expect(c.rangeLabel(weekStart: date(2026, 10, 26, hour: 0)) == "Oct 26 to Nov 1")
    }

    @Test func recentWeeksAreNewestFirst() {
        let starts = clock(at: date(2026, 10, 25)).recentWeekStarts(count: 3)
        #expect(starts == [date(2026, 10, 19, hour: 0), date(2026, 10, 12, hour: 0), date(2026, 10, 5, hour: 0)])
    }
}

struct SuggestionCatalogTests {
    let catalog = SuggestionCatalog.bundled(Bundle.main)

    @Test func catalogIsCuratedAndComplete() {
        #expect(catalog.all.count >= 100)
        #expect(catalog.all.allSatisfy { !$0.text.isEmpty && !$0.reason.isEmpty && !$0.categories.isEmpty })
        #expect(Set(catalog.all.map(\.id)).count == catalog.all.count)
    }

    @Test func dailyPickIsStableWithinADay() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9))!
        let a = catalog.suggestion(forDay: morning, calendar: calendar)
        let b = catalog.suggestion(forDay: morning.addingTimeInterval(600), calendar: calendar)
        #expect(a == b)
    }

    @Test func shuffleNeverRepeatsTheCurrentOne() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let current = catalog.suggestion(forDay: now, calendar: calendar)
        for _ in 0..<20 {
            #expect(catalog.shuffle(from: current, for: now, calendar: calendar) != current)
        }
    }
}

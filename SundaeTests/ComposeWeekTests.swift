import Foundation
import Testing
@testable import Sundae

/// What went wrong on Sunday, November 1, 2026: the app had been kept in memory since the Sunday
/// before, still holding last week's post, so posting opened on last week's photos. A new week
/// starts from nothing, whatever was loaded before.
@MainActor
struct ComposeWeekTests {
    let zone = TimeZone(identifier: "America/Indiana/Indianapolis")!

    @Test func aNewWeekNeverOpensOnLastWeeksPost() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        // The Sunday the clocks went back, at lunch.
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let clock = SundayClock(now: { sunday }, timeZone: zone)
        let api = MockSundaeAPI(clock: clock)
        _ = try await api.createAccount(ticket: "mock-signup-ticket", username: "", name: nil)
        let thisWeek = clock.weekStart()
        let lastWeek = try #require(clock.calendar.date(byAdding: .day, value: -7, to: thisWeek))

        let compose = ComposeStore(api: api)
        // Last week was posted (the demo data has it), and that is what was in memory.
        await compose.load(weekStart: lastWeek)
        #expect(compose.hasPosted)
        #expect(!compose.draft.isEmpty)

        await compose.load(weekStart: thisWeek)
        #expect(compose.loadedWeekStart == thisWeek)
        #expect(!compose.hasPosted, "this week has no post yet")
        #expect(compose.draft.isEmpty, "nothing of last week's post carries over")
    }

    /// Within one week, coming back to it keeps whatever has been picked.
    @Test func theSameWeekKeepsItsDraft() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let clock = SundayClock(now: { sunday }, timeZone: zone)
        let api = MockSundaeAPI(clock: clock)
        _ = try await api.createAccount(ticket: "mock-signup-ticket", username: "", name: nil)
        let lastWeek = try #require(clock.calendar.date(byAdding: .day, value: -7, to: clock.weekStart()))

        let compose = ComposeStore(api: api)
        await compose.load(weekStart: lastWeek)
        let count = compose.draft.photos.count
        await compose.load(weekStart: lastWeek)
        #expect(compose.draft.photos.count == count)
        #expect(compose.hasPosted)
    }
}

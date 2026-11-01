import Foundation
import Testing
import UIKit
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

    /// A photo taken with the camera joins the draft like any other: sized, dated now, and counted
    /// as one of the post's photos, not one of the library's.
    @Test func aPhotoFromTheCameraJoinsTheDraft() async throws {
        let api = MockSundaeAPI(clock: SundayClock(timeZone: zone))
        let compose = ComposeStore(api: api)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { context in
            UIColor(red: 0.85, green: 0.3, blue: 0.3, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        await compose.addCameraPhoto(image)
        #expect(compose.draft.photos.count == 1)
        #expect(compose.nonLibraryPhotoCount == 1)
        let photo = try #require(compose.draft.photos.first)
        #expect(photo.takenAt != nil)
        #expect(photo.width > 0 && photo.height > 0)
    }
}

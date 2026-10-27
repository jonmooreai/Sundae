import Foundation
import Testing
@testable import Sundae

/// The widget's day logic. October 25, 2026 is a Sunday.
struct WidgetSnapshotTests {
    let zone = TimeZone(identifier: "America/Indiana/Indianapolis")!
    let catalog = SuggestionCatalog([
        Suggestion(id: "a", text: "Walk a neighborhood you don't know.", reason: "", categories: [.outdoors], timeOfDay: .any),
        Suggestion(id: "b", text: "Find the oldest book in the library.", reason: "", categories: [.local], timeOfDay: .any),
        Suggestion(id: "c", text: "Cook something you can't pronounce.", reason: "", categories: [.food], timeOfDay: .any),
    ])

    private func date(_ day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func snapshot(_ day: Int, mode: WidgetSnapshot.Mode? = nil) -> WidgetSnapshot {
        WidgetSnapshotBuilder.snapshot(at: date(day), timeZone: zone, mode: mode, catalog: catalog, shared: SharedDefaults())
    }

    @Test func sundayTurnsToTheWeeksPhotos() {
        let s = snapshot(25)
        #expect(s.mode == .sunday)
        #expect(s.countdown == "It's Sunday")
    }

    @Test func weekdaysShowTodayAndTheNextTwoDays() {
        let s = snapshot(21)
        #expect(s.mode == .weekday)
        #expect(s.idea != nil)
        #expect(s.upcoming.count == 2)
        #expect(s.countdown == "4 days to Sunday")
    }

    @Test func fridayLooksAheadToSunday() {
        let s = snapshot(23)
        #expect(s.upcoming.count == 2)
        #expect(s.upcoming.last?.text == "Post your week.")
    }

    @Test func saturdayOnlyHasSundayLeft() {
        let s = snapshot(24)
        #expect(s.upcoming.map(\.text) == ["Post your week."])
        #expect(s.countdown == "Sunday is tomorrow")
    }

    @Test func thePreviewCanShowSundayOnAWeekday() {
        #expect(snapshot(21, mode: .sunday).mode == .sunday)
        #expect(snapshot(25, mode: .weekday).mode == .weekday)
    }

    @Test func theLargeWidgetListsTodaysIdeaFirstWithNoRepeats() {
        let s = snapshot(21)
        #expect(!s.list.isEmpty)
        #expect(s.list.count <= 5)
        #expect(s.list.first?.id == s.idea?.id)
        #expect(Set(s.list.map(\.id)).count == s.list.count)
    }

    @Test func aMapsButtonOnlyEverOpensAppleMaps() throws {
        let place = Suggestion.Place(name: "Juniper Bakery", latitude: 40.0, longitude: -86.0)
        let link = try #require(WidgetSnapshot.mapsLink(for: place))
        #expect(link.scheme == "sundae")
        let target = try #require(WidgetSnapshot.mapsDestination(from: link))
        #expect(target == place.mapsURL)
        #expect(WidgetSnapshot.mapsDestination(from: URL(string: "sundae://maps?to=https://example.com")!) == nil)
        #expect(WidgetSnapshot.mapsDestination(from: URL(string: "sundae://other?to=maps://?q=x")!) == nil)
        #expect(WidgetSnapshot.mapsDestination(from: URL(string: "https://maps?to=maps://?q=x")!) == nil)
    }
}

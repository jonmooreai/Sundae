import Foundation
import Testing
@testable import Sundae

/// Ideas near you: never on Sunday, never without opting in, never with an account attached.
struct LocalIdeasTests {
    let zone = TimeZone(identifier: "America/Indiana/Indianapolis")!

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    @Test func sundayNeverLooks() {
        let sunday = date(2026, 10, 25)
        #expect(!LocalIdeasPolicy.shouldFetch(enabled: true, isSunday: true, lastFetch: nil, now: sunday, calendar: calendar))
    }

    @Test func offNeverLooks() {
        let wednesday = date(2026, 10, 21)
        #expect(!LocalIdeasPolicy.shouldFetch(enabled: false, isSunday: false, lastFetch: nil, now: wednesday, calendar: calendar))
    }

    @Test func looksOnceADayAndAgainAfterAWhile() {
        let wednesday = date(2026, 10, 21)
        #expect(LocalIdeasPolicy.shouldFetch(enabled: true, isSunday: false, lastFetch: nil, now: wednesday, calendar: calendar))
        #expect(!LocalIdeasPolicy.shouldFetch(enabled: true, isSunday: false, lastFetch: date(2026, 10, 21, hour: 10), now: wednesday, calendar: calendar))
        #expect(LocalIdeasPolicy.shouldFetch(enabled: true, isSunday: false, lastFetch: date(2026, 10, 21, hour: 7), now: wednesday, calendar: calendar))
        #expect(LocalIdeasPolicy.shouldFetch(enabled: true, isSunday: false, lastFetch: date(2026, 10, 20), now: wednesday, calendar: calendar))
    }

    @Test func approximateLocationMeansACoarserCell() {
        #expect(LocalIdeasPolicy.precision(accuracyLimited: false) == 6)
        #expect(LocalIdeasPolicy.precision(accuracyLimited: true) == 5)
    }

    @Test func mockRefusesSunday() async {
        let sunday = date(2026, 10, 25)
        let api = MockSundaeAPI(clock: SundayClock(now: { sunday }, timeZone: zone))
        await #expect(throws: SundaeError.sundayClosed) {
            _ = try await api.localIdeas(cell: "9q8yyk", day: sunday)
        }
    }

    @Test func mockIdeasNeedNoAccountAndNameNoArea() async throws {
        let wednesday = date(2026, 10, 21)
        let api = MockSundaeAPI(clock: SundayClock(now: { wednesday }, timeZone: zone))
        let first = try await api.localIdeas(cell: "9q8yyk", day: wednesday)
        let again = try await api.localIdeas(cell: "9q8yyk", day: wednesday)
        #expect(first == again)
        #expect(first.count == 3)
        for idea in first {
            #expect(idea.isNearby)
            #expect(idea.place != nil)
            #expect(!idea.id.contains("9q8yyk"))
        }
    }

    @Test func placeLinksPinThePlaceNotThePerson() {
        let place = Suggestion.Place(name: "Arizmendi Bakery", walkMinutes: 6, latitude: 37.76, longitude: -122.42)
        let url = place.mapsURL?.absoluteString ?? ""
        #expect(url.hasPrefix("maps://"))
        #expect(url.contains("ll=37.76,-122.42"))
        #expect(Suggestion.Place(name: "Somewhere").mapsURL?.absoluteString.contains("ll=") == false)
    }
}

extension HTTPClientTests {
    /// The one request that may say something about where the phone is says nothing about whose it is.
    @Test func localIdeasCarryNoAccount() async throws {
        StubURLProtocol.reset { _ in
            (200, Data(#"[{"id":"local:2026-10-21:0","text":"Be first in line at Arizmendi.","reason":"Steam.","time_of_day":"morning","place":{"name":"Arizmendi Bakery","walk_minutes":6,"latitude":37.76,"longitude":-122.42}}]"#.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let tokens = TokenStore(storage: InMemorySecretStorage())
        tokens.store(accessToken: "access-1", refreshToken: "refresh-1", expiresIn: 3600)
        let client = HTTPClient(baseURL: URL(string: "https://api.sundae.test")!, tokens: tokens,
                                session: URLSession(configuration: configuration))
        let api = LiveSundaeAPI(client: client)

        let ideas = try await api.localIdeas(cell: "9q8yyk", day: Date())

        let request = try #require(StubURLProtocol.requests.withLock { $0.last })
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.path() == "/v1/ideas/local")
        #expect(request.url?.query()?.contains("cell=9q8yyk") == true)
        #expect(ideas.first?.isNearby == true)
        #expect(ideas.first?.timeOfDay == .morning)
        #expect(ideas.first?.place?.name == "Arizmendi Bakery")
    }
}

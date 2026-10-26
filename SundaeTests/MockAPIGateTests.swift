import Foundation
import Testing
@testable import Sundae

/// The mock enforces the server's rules, so the app can be developed honestly against it.
struct MockAPIGateTests {
    let zone = TimeZone(identifier: "America/Indiana/Indianapolis")!

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func signedInAPI(at moment: Date) async throws -> MockSundaeAPI {
        let api = MockSundaeAPI(clock: SundayClock(now: { moment }, timeZone: zone))
        _ = try await api.createAccount(ticket: "mock-signup-ticket", username: "", name: nil)
        return api
    }

    @Test func feedIsClosedOnAWednesday() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 21))
        await #expect(throws: SundaeError.sundayClosed) {
            _ = try await api.feed(olderThan: nil, limit: 10)
        }
        await #expect(throws: SundaeError.sundayClosed) {
            _ = try await api.profile(userID: "u_maya")
        }
    }

    @Test func approvalsStayOpenAllWeek() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 21))
        let requests = try await api.pendingTagRequests()
        #expect(!requests.isEmpty)
        try await api.respondToTag(id: requests[0].tag.id, approve: true)
        let after = try await api.pendingTagRequests()
        #expect(after.count == requests.count - 1)
    }

    @Test func feedOpensOnSunday() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 25))
        let feed = try await api.feed(olderThan: nil, limit: 10)
        #expect(!feed.isEmpty)
        #expect(feed == feed.sorted { $0.createdAt > $1.createdAt })
    }

    @Test func oneDumpPerWeekAndPhotoCap() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 25))
        let weekStart = date(2026, 10, 19, hour: 0)
        let photo = DraftPhoto(source: .placeholder(seed: 1), width: 100, height: 100)

        var draft = DumpDraft(photos: [photo], caption: "Quiet one.")
        let first = try await api.saveDump(draft, weekStart: weekStart)
        draft.caption = "Quiet one. Lots of soup."
        let second = try await api.saveDump(draft, weekStart: weekStart)
        #expect(first.id == second.id)
        #expect(second.caption == "Quiet one. Lots of soup.")

        let tooMany = DumpDraft(photos: Array(repeating: photo, count: 16).map { _ in
            DraftPhoto(source: .placeholder(seed: 2), width: 10, height: 10)
        })
        await #expect(throws: SundaeError.tooManyPhotos) {
            _ = try await api.saveDump(tooMany, weekStart: weekStart)
        }
    }

    @Test func taggingIsLimitedToFollows() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 25))
        let stranger = User(id: "u_noor", username: "noor", name: "Noor", bio: "", avatar: nil, isPublic: true, timezone: "UTC")
        let friend = try await api.taggableUsers().first!
        let photo = DraftPhoto(source: .placeholder(seed: 1), width: 10, height: 10, taggedUsers: [stranger, friend])
        let dump = try await api.saveDump(DumpDraft(photos: [photo]), weekStart: date(2026, 10, 19, hour: 0))
        #expect(dump.photos[0].tags.map(\.taggedUser.id) == [friend.id])
        #expect(dump.photos[0].tags[0].status == .pending)
    }

    @Test func declinedTagsDisappearAndApprovedOnesLandOnTheProfile() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 25))
        let requests = try await api.pendingTagRequests()
        let approve = requests[0]
        let decline = requests[1]
        try await api.respondToTag(id: approve.tag.id, approve: true)
        try await api.respondToTag(id: decline.tag.id, approve: false)

        let me = try await api.profile(userID: "u_me")
        let week = me.weeks.first { $0.weekStart == approve.weekStart }
        #expect(week?.tagged.contains { $0.tag.id == approve.tag.id } == true)

        let declinedDump = try await api.dump(id: decline.photo.dumpID)
        let declinedPhoto = declinedDump.photos.first { $0.id == decline.photo.id }
        #expect(declinedPhoto?.visibleTags.contains { $0.id == decline.tag.id } == false)
    }
}

import Foundation
import Testing
@testable import Sundae

/// Anyone who follows you can be seen and removed on any day, and someone asking for something
/// shows their username beside their name.
struct FollowersTests {
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

    @Test func followersOpenOnAWeekday() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 21))
        let followers = try await api.followers()
        #expect(followers.contains { $0.id == "u_maya" })
        // Riley has only asked.
        #expect(!followers.contains { $0.id == "u_riley" })
        #expect(followers.map(\.username) == followers.map(\.username).sorted())
    }

    @Test func followingListsOnlyAcceptedFollowsInOrder() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 25))
        let following = try await api.following()
        let count = try await api.profile(userID: "u_me").followingCount ?? -1
        #expect(following.count == count)
        #expect(following.map(\.username) == following.map(\.username).sorted())
        guard let first = following.first else { return }
        try await api.unfollow(userID: first.id)
        let after = try await api.following()
        #expect(!after.contains { $0.id == first.id })
    }

    @Test func listsShowHowYouStandWithEachPerson() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 25))
        let mine = try await api.followList(of: "u_me", .followers)
        #expect(mine.allSatisfy(\.followsYou))
        let count = try await api.profile(userID: "u_me").followerCount ?? -1
        #expect(mine.count == count)
        let following = try await api.followList(of: "u_me", .following)
        #expect(following.allSatisfy { $0.relationship == .following })
    }

    @Test func aRemovedFollowerIsGone() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 25))
        let before = try await api.profile(userID: "u_me").followerCount ?? 0
        try await api.removeFollower(userID: "u_maya")
        let followers = try await api.followers()
        #expect(!followers.contains { $0.id == "u_maya" })
        let after = try await api.profile(userID: "u_me").followerCount ?? 0
        #expect(after == before - 1)
        // Removing someone twice is fine.
        try await api.removeFollower(userID: "u_maya")
    }

    @Test func removingSomeoneWhoAskedDeclinesTheRequest() async throws {
        let api = try await signedInAPI(at: date(2026, 10, 21))
        let before = try await api.followRequests()
        #expect(before.contains { $0.id == "u_riley" })
        try await api.removeFollower(userID: "u_riley")
        let after = try await api.followRequests()
        #expect(!after.contains { $0.id == "u_riley" })
    }

    @Test func theUsernameStandsBesideTheName() {
        let pat = User(id: "u_pat", username: "patdoe", name: "Pat Doe", bio: "", avatar: nil, isPublic: false, timezone: "UTC")
        #expect(pat.handle == "@patdoe")
        #expect(PeopleListView.removeTitle(pat) == "Remove Pat Doe?")
        #expect(PeopleListView.unfollowTitle(pat) == "Unfollow Pat Doe?")
        var nameless = pat
        nameless.name = ""
        #expect(PeopleListView.removeTitle(nameless) == "Remove patdoe?")
    }
}

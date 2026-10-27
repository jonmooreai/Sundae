import Foundation
import SwiftUI
import Testing
@testable import Sundae

/// Replies one level deep, and @mentions that link only people Sundae knows.
struct RepliesAndMentionsTests {
    let zone = TimeZone(identifier: "America/Indiana/Indianapolis")!

    /// Sunday, October 25, 2026, at noon.
    private var sunday: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
    }

    private func signedInAPI() async throws -> MockSundaeAPI {
        let moment = sunday
        let api = MockSundaeAPI(clock: SundayClock(now: { moment }, timeZone: zone))
        _ = try await api.createAccount(ticket: "mock-signup-ticket", username: "", name: nil)
        return api
    }

    private let pat = User(id: "u_pat", username: "pat.doe", name: "Pat Doe", bio: "", avatar: nil, isPublic: false, timezone: "UTC")

    @Test func aReplyToAReplyGoesUnderTheSameComment() async throws {
        let api = try await signedInAPI()
        let feed = try await api.feed(olderThan: nil, limit: 20)
        let dump = try #require(feed.first(where: { $0.commentsEnabled }))
        let first = try await api.addComment(dumpID: dump.id, body: "Love this", replyingTo: nil)
        let reply = try await api.addComment(dumpID: dump.id, body: "@maya me too", replyingTo: first.id)
        let deeper = try await api.addComment(dumpID: dump.id, body: "Same", replyingTo: reply.id)
        #expect(reply.parentID == first.id)
        #expect(deeper.parentID == first.id)

        try await api.deleteComment(id: first.id)
        let left = try await api.comments(dumpID: dump.id)
        #expect(!left.contains { [first.id, reply.id, deeper.id].contains($0.id) }, "replies go with their comment")
    }

    @Test func mentionsLinkOnlyPeopleSundaeKnows() {
        let text = CommentRow.attributed("Thanks @pat.doe. And @nobody too", people: ["pat.doe": pat])
        let links = text.runs.compactMap { run -> String? in
            run.link == nil ? nil : String(text[run.range].characters)
        }
        #expect(links == ["@pat.doe"], "the full stop ends the sentence, not the username")
    }
}

import Foundation
import Testing
import UIKit
@testable import Sundae

/// The feed is this week until earlier weeks are asked for; Notifications gathers requests and
/// what happened, and its badge drops once looked at; the widget shows what was posted; a
/// fingerprint tells the same picture from a different one.
@MainActor
struct FeedAndNotificationsTests {
    let zone = TimeZone(identifier: "America/Indiana/Indianapolis")!

    private func signedIn() async throws -> (MockSundaeAPI, SundayClock) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))!
        let clock = SundayClock(now: { sunday }, timeZone: zone)
        let api = MockSundaeAPI(clock: clock)
        _ = try await api.createAccount(ticket: "mock-signup-ticket", username: "", name: nil)
        return (api, clock)
    }

    @Test func theFeedIsThisWeekUntilEarlierWeeksAreAskedFor() async throws {
        let (api, clock) = try await signedIn()
        let feed = FeedStore(api: api)
        let week = clock.weekStart()
        await feed.load(refresh: true)
        #expect(!feed.thisWeek(week).isEmpty)
        #expect(feed.thisWeek(week).allSatisfy { $0.weekStart >= week })
        #expect(!feed.showsEarlier)
        #expect(feed.mayHaveEarlier(week), "the demo has earlier weeks")

        // Scrolling to the end of this week loads nothing older on its own.
        let before = feed.dumps.count
        if let last = feed.thisWeek(week).last, feed.dumps.contains(where: { $0.weekStart < week }) {
            await feed.loadMoreIfNeeded(current: last, weekStart: week)
            #expect(feed.dumps.count == before)
        }

        await feed.showEarlier(weekStart: week)
        #expect(feed.showsEarlier)
        let earlier = feed.earlierWeeks(week)
        #expect(!earlier.isEmpty)
        #expect(earlier.allSatisfy { group in group.weekStart < week && group.dumps.allSatisfy { $0.weekStart == group.weekStart } })
        #expect(earlier.map(\.weekStart) == earlier.map(\.weekStart).sorted(by: >), "newest week first")

        feed.reset()
        #expect(!feed.showsEarlier, "a new week starts on this week again")
    }

    @Test func notificationsGatherRequestsAndActivityAndTheBadgeDropsOnceSeen() async throws {
        let (api, _) = try await signedIn()
        let store = NotificationsStore(api: api)
        store.forget()
        await store.load()
        #expect(store.followRequests.map(\.user.username).contains("riley"))
        #expect(!store.tagRequests.isEmpty)
        #expect(store.activity.contains { $0.kind == .like })
        #expect(store.activity.contains { $0.kind == .follow && $0.actor.username == "noor" })
        #expect(store.activity.map(\.at) == store.activity.map(\.at).sorted(by: >), "newest first")
        let waiting = store.followRequests.count + store.tagRequests.count
        #expect(store.badge > waiting)

        store.markSeen()
        #expect(store.badge == waiting, "looked at: only what waits on you")

        // Confirming a request never follows them back.
        let riley = try #require(store.followRequests.first { $0.user.username == "riley" })
        #expect(await store.respond(to: riley, accept: true))
        let profile = try await api.profile(userID: riley.id)
        #expect(profile.relationship == .notFollowing)
        store.forget()
    }

    /// A load that set out before an answer never brings the request back.
    @Test func anAnsweredRequestStaysAnswered() async throws {
        let (api, _) = try await signedIn()
        let store = NotificationsStore(api: api)
        await store.load()
        let riley = try #require(store.followRequests.first { $0.user.username == "riley" })
        let tag = try #require(store.tagRequests.first)
        store.dismiss(riley)
        store.dismiss(tag)
        // The server has not heard yet, so it still lists both: they stay off the list.
        await store.load()
        #expect(!store.followRequests.contains { $0.id == riley.id })
        #expect(!store.tagRequests.contains { $0.id == tag.id })
        store.forget()
    }

    @Test func activityLinesAreWarmAndQuoteWhatWasSaid() {
        let pat = User(id: "u_pat", username: "patdoe", name: "Pat Doe", bio: "", avatar: nil, isPublic: false, timezone: "UTC")
        func item(_ kind: ActivityItem.Kind, _ body: String? = nil) -> ActivityItem {
            ActivityItem(id: kind.rawValue, kind: kind, actor: pat, at: Date(), dumpID: nil, weekStart: nil, photo: nil,
                         commentID: nil, commentBody: body, relationship: .notFollowing)
        }
        #expect(ActivityRow.phrase(for: item(.like)) == "liked your week.")
        #expect(ActivityRow.phrase(for: item(.comment, "So good")) == "commented: \u{201C}So good\u{201D}")
        #expect(ActivityRow.phrase(for: item(.follow)) == "started following you.")
        #expect(ActivityRow.phrase(for: item(.tag)) == "tagged you in a photo.")
        #expect(ActivityRow.phrase(for: item(.followRequest)) == "asked to follow you, and you said yes.")
        for kind in [ActivityItem.Kind.like, .comment, .reply, .mention, .commentLike, .tag, .follow, .followRequest, .followAccepted, .tagApproved] {
            #expect(!ActivityRow.phrase(for: item(kind, "Hi")).contains("!"), "no exclamation marks")
        }
    }

    /// The log goes by day for the last week, then by month, with the year once it isn't this one.
    @Test func theLogIsInSectionsByDayThenMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 15))!
        let pat = User(id: "u_pat", username: "patdoe", name: "Pat Doe", bio: "", avatar: nil, isPublic: false, timezone: "UTC")
        func at(_ month: Int, _ day: Int, _ year: Int = 2026) -> ActivityItem {
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
            return ActivityItem(id: "\(year)-\(month)-\(day)", kind: .like, actor: pat, at: date, dumpID: nil, weekStart: nil,
                                photo: nil, commentID: nil, commentBody: nil, relationship: .following)
        }
        let items = [at(11, 28), at(11, 27), at(11, 24), at(11, 3), at(10, 30), at(10, 2), at(12, 25, 2025)]
        let sections = ActivityLog.sections(items, now: now, calendar: calendar)
        #expect(sections.map(\.title) == ["Today", "Yesterday", "This week", "November", "October", "December 2025"])
        #expect(sections.map(\.items.count) == [1, 1, 1, 1, 2, 1])
        #expect(ActivityRow.when(at(11, 28).at, now: now, calendar: calendar) == "6h")
        #expect(ActivityRow.when(at(10, 30).at, now: now, calendar: calendar) == "Oct 30")
        #expect(ActivityRow.when(at(12, 25, 2025).at, now: now, calendar: calendar) == "Dec 25, 2025")
    }

    /// Unread is what came after the last look; before any look, only the last week of it, so a
    /// first visit to a long history isn't all marked new. A fresh newest page keeps older pages.
    @Test func unreadIsSinceTheLastLookAndOlderPagesStayOnARefresh() {
        let pat = User(id: "u_pat", username: "patdoe", name: "Pat Doe", bio: "", avatar: nil, isPublic: false, timezone: "UTC")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func item(_ id: String, daysAgo: Double) -> ActivityItem {
            ActivityItem(id: id, kind: .like, actor: pat, at: now.addingTimeInterval(-daysAgo * 86_400), dumpID: nil, weekStart: nil,
                         photo: nil, commentID: nil, commentBody: nil, relationship: .following)
        }
        let log = [item("a", daysAgo: 0), item("b", daysAgo: 3), item("c", daysAgo: 30)]
        let firstLook = NotificationsStore.unreadAfter(seenThrough: nil, activity: log)
        #expect(log.filter { $0.at > firstLook }.map(\.id) == ["a", "b"])
        let later = NotificationsStore.unreadAfter(seenThrough: now.addingTimeInterval(-86_400), activity: log)
        #expect(log.filter { $0.at > later }.map(\.id) == ["a"])
        #expect(NotificationsStore.unreadAfter(seenThrough: nil, activity: []) == .distantFuture)

        let older = [item("b", daysAgo: 3), item("c", daysAgo: 30), item("d", daysAgo: 60)]
        let fresh = [item("new", daysAgo: 0), item("a", daysAgo: 0.5), item("b", daysAgo: 3)]
        #expect(NotificationsStore.merged(newest: fresh, into: older).map(\.id) == ["new", "a", "b", "c", "d"])
        #expect(NotificationsStore.merged(newest: [], into: older).isEmpty, "nothing now means nothing older either")
    }

    /// The Sunday wrap counts this week's friends, each once, and never the earlier weeks the feed
    /// has loaded: two people in the app read "3 friends posted" before.
    @Test func theSundayWrapCountsThisWeeksFriendsOnce() {
        func user(_ id: String, _ name: String) -> User {
            User(id: id, username: id, name: name, bio: "", avatar: nil, isPublic: false, timezone: "UTC")
        }
        let me = user("u_pat", "Pat Doe"), sam = user("u_sam", "Sam Doe")
        func week(_ id: String, by author: User, tagging tagged: [User] = [], likedBy: [User] = []) -> Dump {
            let tags = tagged.map { Tag(id: "t_\($0.id)", photoID: "p_\(id)", taggerID: author.id, taggedUser: $0, status: .approved, respondedAt: nil) }
            let photo = Photo(id: "p_\(id)", dumpID: id, order: 0, source: .remote(URL(string: "https://example.com/p.jpg")!),
                              width: 1, height: 1, altText: nil, tags: tags)
            return Dump(id: id, author: author, weekStart: Date(), caption: "", createdAt: Date(), lockedAt: nil, photos: [photo],
                        commentsEnabled: true, likedBy: likedBy, likedByMe: false, commentCount: 0)
        }
        // Sam's week twice over (once more as a photo shared onto Pat's), plus Pat's own.
        let thisWeek = [week("d_sam", by: sam, tagging: [me]), week("d_sam2", by: sam, tagging: [me]), week("d_pat", by: me, likedBy: [sam])]
        let wrap = WrapSummary(thisWeek: thisWeek, me: me.id, tomorrowsIdea: nil)
        #expect(wrap.friendsPosted == 1)
        #expect(wrap.taggedIn == 1)
        #expect(wrap.firstLiker == "Sam")
        #expect(wrap.posted)
        #expect(wrap.lines.prefix(3) == ["One friend posted their week.", "You were in it.", "Sam was first to like yours."])
        let quiet = WrapSummary(thisWeek: [], me: me.id, tomorrowsIdea: nil)
        #expect(quiet.lines.first == "A quiet Sundae. Nobody you follow posted.")
        #expect(quiet.lines.last == "Yours is still open until midnight.")
    }

    /// The large widget shows only the post's photos: a week's library photos never.
    @Test func theLargeWidgetShowsOnlyPostedPhotos() {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.mode = .sunday
        snapshot.photos = [Data([1]), Data([2]), Data([3]), Data([4])]
        snapshot.photosArePosted = false
        #expect(!SundaeWidgetView.largeShowsPhotos(snapshot), "library photos, not the post")
        snapshot.photosArePosted = true
        #expect(SundaeWidgetView.largeShowsPhotos(snapshot))
        snapshot.photos = []
        #expect(!SundaeWidgetView.largeShowsPhotos(snapshot))
    }

    @Test func theWidgetSaysHowManyPhotosArePosted() {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.mode = .sunday
        snapshot.hasPosted = true
        snapshot.photosArePosted = true
        snapshot.weekPhotoCount = 6
        snapshot.photos = Array(repeating: Data(), count: 4)
        #expect(snapshot.photosArePosted)
        let shared = SharedDefaults()
        let week = Date(timeIntervalSince1970: 1_800_000_000)
        shared.setPostedAssetIDs(["a", "b", "c", "d", "e"], weekStart: week)
        #expect(shared.postedAssetIDs(forWeekStarting: week) == ["a", "b", "c", "d", "e"])
        #expect(shared.postedAssetIDs(forWeekStarting: week.addingTimeInterval(7 * 86_400)).isEmpty, "another week has none")
        shared.setPostedAssetIDs([], weekStart: week)
    }

    private func picture(_ draw: (CGContext, CGSize) -> Void) -> Data {
        let size = CGSize(width: 300, height: 200)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, size) }.jpegData(compressionQuality: 0.9)!
    }

    @Test func theSamePictureHasTheSameFingerprintAndADifferentOneDoesNot() throws {
        let sunset = picture { context, size in
            context.setFillColor(UIColor.orange.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(UIColor.purple.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 3))
            context.setFillColor(UIColor.yellow.cgColor)
            context.fillEllipse(in: CGRect(x: 120, y: 90, width: 60, height: 60))
        }
        let checks = picture { context, size in
            for x in stride(from: 0, to: Int(size.width), by: 50) {
                context.setFillColor((x / 50) % 2 == 0 ? UIColor.black.cgColor : UIColor.white.cgColor)
                context.fill(CGRect(x: CGFloat(x), y: 0, width: 50, height: size.height))
            }
        }
        let a = try #require(PhotoFingerprint.of(sunset))
        #expect(a.count == 16)
        // Sent again: shrunk and saved as a new JPEG, as the app does to every photo.
        let resent = try #require(PhotoProcessor.process(sunset, maxPixelSize: 150))
        let b = try #require(PhotoFingerprint.of(resent.data))
        let c = try #require(PhotoFingerprint.of(checks))
        func apart(_ x: String, _ y: String) -> Int { ((UInt64(x, radix: 16) ?? 0) ^ (UInt64(y, radix: 16) ?? 0)).nonzeroBitCount }
        #expect(apart(a, b) <= 6, "the same picture")
        #expect(apart(a, c) > 6, "a different one")
    }
}

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
        for kind in [ActivityItem.Kind.like, .comment, .reply, .mention, .commentLike, .follow, .followAccepted, .tagApproved] {
            #expect(!ActivityRow.phrase(for: item(kind, "Hi")).contains("!"), "no exclamation marks")
        }
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

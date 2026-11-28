import Foundation
import Observation

/// Everything behind the heart: people asking to follow, photos you were tagged in, and the log of
/// everything that happened around you, all the way back, a page at a time. The badge counts what
/// is waiting on you and what is new since you last looked; what you have seen is remembered on
/// this phone only.
@MainActor
@Observable
final class NotificationsStore {
    private let api: any SundaeAPI
    private(set) var followRequests: [ListedPerson] = []
    private(set) var tagRequests: [TagRequest] = []
    private(set) var activity: [ActivityItem] = []
    /// Whether older activity may be left to load.
    private(set) var hasMoreActivity = true
    private(set) var isLoadingMore = false
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?
    /// The newest activity already looked at.
    private(set) var seenThrough: Date?
    /// Requests and tags answered here. A load that set out before the answer would bring them
    /// back; these stay gone.
    private var answered: Set<ID> = []

    private static let seenKey = "notifications.seenThrough"

    init(api: any SundaeAPI) {
        self.api = api
        seenThrough = UserDefaults.standard.object(forKey: Self.seenKey) as? Date
    }

    /// Requests waiting on you, and activity you have not looked at yet.
    var badge: Int { followRequests.count + tagRequests.count + activity.filter { isNew($0) }.count }

    var isEmpty: Bool { followRequests.isEmpty && tagRequests.isEmpty && activity.isEmpty }

    func isNew(_ item: ActivityItem) -> Bool {
        item.at > Self.unreadAfter(seenThrough: seenThrough, activity: activity)
    }

    /// Activity after this moment is unread. Before Notifications has ever been opened, that is
    /// the last week of it, never the whole history, so a first look isn't a wall of new.
    static func unreadAfter(seenThrough: Date?, activity: [ActivityItem]) -> Date {
        if let seenThrough { return seenThrough }
        guard let newest = activity.map(\.at).max() else { return .distantFuture }
        return newest.addingTimeInterval(-7 * 86_400)
    }

    func reset() {
        followRequests = []
        tagRequests = []
        activity = []
        hasMoreActivity = true
        answered = []
        hasLoaded = false
        errorMessage = nil
    }

    /// Forgets what was seen too, for a different account on this phone.
    func forget() {
        reset()
        seenThrough = nil
        UserDefaults.standard.removeObject(forKey: Self.seenKey)
    }

    /// The requests, and the newest page of activity. What older pages were already loaded stays
    /// below it, unless `fresh` (a pull to refresh), which starts the log over.
    func load(fresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let client = api
        async let follows = client.followRequests()
        async let tags = client.pendingTagRequests()
        async let recent = client.activity()
        do {
            let (waiting, tagged) = try await (follows, tags)
            followRequests = waiting.filter { !answered.contains($0.id) }
            tagRequests = tagged.filter { !answered.contains($0.id) }
            errorMessage = nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
        // Activity is extra: when it cannot load, what was there stays.
        if let items = try? await recent {
            activity = fresh ? items : Self.merged(newest: items, into: activity)
            if fresh || activity.count == items.count { hasMoreActivity = !items.isEmpty }
        }
        hasLoaded = true
    }

    /// The next page back, from the oldest loaded. Asked for as the end of the list comes on screen.
    func loadMoreActivity() async {
        guard hasMoreActivity, !isLoadingMore, !isLoading, let oldest = activity.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.activity(before: oldest.at)
            let known = Set(activity.map(\.id))
            let older = page.filter { !known.contains($0.id) }
            activity += older
            hasMoreActivity = !older.isEmpty
        } catch {
            // Scrolling back to the end tries again.
        }
    }

    /// A fresh newest page on top of what was loaded: everything in it, then what was already
    /// here from before it began, each once.
    static func merged(newest: [ActivityItem], into current: [ActivityItem]) -> [ActivityItem] {
        // Nothing at all now (everyone blocked, say): nothing older either.
        guard let start = newest.last?.at else { return [] }
        let ids = Set(newest.map(\.id))
        return newest + current.filter { $0.at <= start && !ids.contains($0.id) }
    }

    /// Everything showing has been looked at, so the badge drops to what is waiting on you.
    func markSeen() {
        guard let newest = activity.map(\.at).max(), seenThrough.map({ newest > $0 }) ?? true else { return }
        seenThrough = newest
        UserDefaults.standard.set(newest, forKey: Self.seenKey)
    }

    // MARK: - Tags

    /// Takes the request off the list. Wrap in `withAnimation` to let the card leave gracefully.
    func dismiss(_ request: TagRequest) {
        answered.insert(request.id)
        tagRequests.removeAll { $0.id == request.id }
    }

    /// Tells the server; on failure the list reloads so nothing is silently lost.
    func submit(_ request: TagRequest, approve: Bool) async {
        do {
            try await api.respondToTag(id: request.tag.id, approve: approve)
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
            answered.remove(request.id)
            await load()
        }
    }

    // MARK: - Follow requests

    func dismiss(_ person: ListedPerson) {
        answered.insert(person.id)
        followRequests.removeAll { $0.id == person.id }
    }

    /// Accepting lets them follow you. It never follows them back; that is its own button.
    func respond(to person: ListedPerson, accept: Bool) async -> Bool {
        do {
            try await api.respondToFollowRequest(from: person.id, accept: accept)
            return true
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
            answered.remove(person.id)
            await load()
            return false
        }
    }
}

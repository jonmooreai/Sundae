import Foundation
import Observation

/// Everything behind the heart: people asking to follow, photos you were tagged in, and what
/// happened around you lately. The badge counts what is waiting on you and what is new since you
/// last looked; what you have seen is remembered on this phone only.
@MainActor
@Observable
final class NotificationsStore {
    private let api: any SundaeAPI
    private(set) var followRequests: [ListedPerson] = []
    private(set) var tagRequests: [TagRequest] = []
    private(set) var activity: [ActivityItem] = []
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
        seenThrough.map { item.at > $0 } ?? true
    }

    func reset() {
        followRequests = []
        tagRequests = []
        activity = []
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

    func load() async {
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
        if let items = try? await recent { activity = items }
        hasLoaded = true
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

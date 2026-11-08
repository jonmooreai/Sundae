import Foundation
import Observation

@MainActor
@Observable
final class FeedStore {
    private let api: any SundaeAPI
    private let pageSize = 10

    private(set) var dumps: [Dump] = []
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var hasLoaded = false
    /// The feed is this week; earlier weeks show once asked for, at the bottom.
    private(set) var showsEarlier = false
    var errorMessage: String?

    init(api: any SundaeAPI) {
        self.api = api
    }

    func reset() {
        dumps = []
        hasMore = true
        hasLoaded = false
        showsEarlier = false
        errorMessage = nil
    }

    /// This week's posts, newest first.
    func thisWeek(_ weekStart: Date) -> [Dump] {
        dumps.filter { $0.weekStart >= weekStart }
    }

    /// Earlier posts, by week, newest week first.
    func earlierWeeks(_ weekStart: Date) -> [(weekStart: Date, dumps: [Dump])] {
        let earlier = dumps.filter { $0.weekStart < weekStart }
        let weeks = Array(Set(earlier.map(\.weekStart))).sorted(by: >)
        return weeks.map { week in (week, earlier.filter { $0.weekStart == week }) }
    }

    /// Whether there may be earlier weeks to show: some already loaded, or more to ask for.
    func mayHaveEarlier(_ weekStart: Date) -> Bool {
        hasMore || dumps.contains { $0.weekStart < weekStart }
    }

    /// The bottom of this week, tapped: earlier weeks join the feed and keep loading as you scroll.
    func showEarlier(weekStart: Date) async {
        showsEarlier = true
        if !dumps.contains(where: { $0.weekStart < weekStart }), let last = dumps.last {
            await loadMore(after: last)
        }
    }

    func load(refresh: Bool) async {
        if hasLoaded && !refresh { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.feed(olderThan: nil, limit: pageSize)
            dumps = page
            // A page can come back short when a bad item is skipped, so only an empty page ends the feed.
            hasMore = !page.isEmpty
            hasLoaded = true
            errorMessage = nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }

    /// Called as each post appears. Loads the next page at the last one, but past this week only
    /// once earlier weeks were asked for.
    func loadMoreIfNeeded(current dump: Dump, weekStart: Date) async {
        guard hasMore, !isLoading, dump.id == dumps.last?.id else { return }
        guard showsEarlier || !dumps.contains(where: { $0.weekStart < weekStart }) else { return }
        await loadMore(after: dump)
    }

    private func loadMore(after dump: Dump) async {
        guard hasMore, !isLoading else { return }
        let oldest = dump.createdAt
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.feed(olderThan: oldest, limit: pageSize)
            dumps.append(contentsOf: page)
            hasMore = !page.isEmpty
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }

    /// Optimistic like, rolled back if the server disagrees.
    func toggleLike(_ dump: Dump, me: User?) async {
        guard let index = dumps.firstIndex(where: { $0.id == dump.id }) else { return }
        let liked = !dump.likedByMe
        var optimistic = dump
        optimistic.likedByMe = liked
        if let me {
            optimistic.likedBy.removeAll { $0.id == me.id }
            if liked { optimistic.likedBy.insert(me, at: 0) }
        }
        dumps[index] = optimistic
        do {
            let updated = try await api.setLike(dumpID: dump.id, liked: liked)
            replace(updated)
        } catch {
            replace(dump)
        }
    }

    func replace(_ dump: Dump) {
        if let index = dumps.firstIndex(where: { $0.id == dump.id }) {
            dumps[index] = dump
        }
    }

    func remove(dumpID: ID) {
        dumps.removeAll { $0.id == dumpID }
    }

    func setCommentCount(dumpID: ID, count: Int) {
        if let index = dumps.firstIndex(where: { $0.id == dumpID }) {
            dumps[index].commentCount = count
        }
    }

    /// A user changed (name, photo): update every copy already on screen.
    func replaceUser(_ user: User) {
        dumps = dumps.map { dump in
            var dump = dump
            if dump.author.id == user.id { dump.author = user }
            dump.likedBy = dump.likedBy.map { $0.id == user.id ? user : $0 }
            dump.photos = dump.photos.map { photo in
                var photo = photo
                photo.tags = photo.tags.map { tag in
                    var tag = tag
                    if tag.taggedUser.id == user.id { tag.taggedUser = user }
                    return tag
                }
                return photo
            }
            return dump
        }
    }

    /// A freshly posted dump goes straight to the top so the author sees it without a refresh.
    func insertOwn(_ dump: Dump) {
        dumps.removeAll { $0.id == dump.id }
        dumps.insert(dump, at: 0)
    }
}

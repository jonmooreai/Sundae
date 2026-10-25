import Foundation

/// In-memory backend with seeded friends, dumps, tags and follow requests.
///
/// It enforces the same rules the real server will: the Sunday gate on every social read
/// and write, one dump per week, the end-of-Sunday lock, the photo and tag caps, and the
/// "only follows can tag" rule. Swapping in the live client should not change app behavior.
actor MockSundaeAPI: SundaeAPI {
    private var clock: SundayClock
    private static let meID = "u_me"
    private let meID = MockSundaeAPI.meID

    private struct SeedData {
        var users: [ID: User]
        var follows: [Follow]
        var dumps: [ID: Dump]
        var comments: [ID: [Comment]]
    }

    private var users: [ID: User] = [:]
    private var follows: [Follow] = []
    private var dumps: [ID: Dump] = [:]
    private var comments: [ID: [Comment]] = [:]
    private var done: [SuggestionDone] = []
    private var blocked: Set<ID> = []
    private var settings = AccountSettings()
    private var signedInUserID: ID?

    private static let avatarKey = "mock.avatarData"

    init(clock: SundayClock) {
        self.clock = clock
        var seed = Self.makeSeed(clock: clock)
        // A profile photo chosen in an earlier run comes back, so the demo feels saved.
        if let data = UserDefaults.standard.data(forKey: Self.avatarKey), var me = seed.users[Self.meID] {
            me.avatar = .data(data)
            Self.propagate(me, users: &seed.users, dumps: &seed.dumps, comments: &seed.comments)
        }
        users = seed.users
        follows = seed.follows
        dumps = seed.dumps
        comments = seed.comments
    }

    /// Every copy of a user (authors, likers, tagged people, commenters) takes the new value.
    private static func propagate(_ user: User, users: inout [ID: User], dumps: inout [ID: Dump], comments: inout [ID: [Comment]]) {
        users[user.id] = user
        for (id, var dump) in dumps {
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
            dumps[id] = dump
        }
        for (id, list) in comments {
            comments[id] = list.map { comment in
                var comment = comment
                if comment.author.id == user.id { comment.author = user }
                return comment
            }
        }
    }

    /// The debug "pretend it's Sunday" switch moves the mock's clock too, so the gate agrees with the UI.
    func setClock(_ clock: SundayClock) {
        self.clock = clock
        let seed = Self.makeSeed(clock: clock)
        users = seed.users
        follows = seed.follows
        dumps = seed.dumps
        comments = seed.comments
        blocked = []
    }

    // MARK: - Guards

    private func latency() async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    private func requireSignedIn() throws -> User {
        guard let id = signedInUserID, let me = users[id] else { throw SundaeError.notAuthorized }
        return me
    }

    private func requireSunday() throws {
        guard clock.isSunday() else { throw SundaeError.sundayClosed }
    }

    private func isFollowing(_ follower: ID, _ followee: ID) -> Bool {
        follows.contains { $0.followerID == follower && $0.followeeID == followee && $0.status == .accepted }
    }

    private func canRead(_ dump: Dump, as viewer: ID) -> Bool {
        if blocked.contains(dump.author.id) { return false }
        return dump.author.id == viewer || dump.author.isPublic || isFollowing(viewer, dump.author.id)
    }

    private func relationship(of viewer: ID, to target: ID) -> Relationship {
        if viewer == target { return .me }
        if blocked.contains(target) { return .blocked }
        if let f = follows.first(where: { $0.followerID == viewer && $0.followeeID == target }) {
            return f.status == .accepted ? .following : .requested
        }
        return .notFollowing
    }

    // MARK: - Session

    func signIn(_ method: SignInMethod, username: String?, name: String?) async throws -> Session {
        try await latency()
        if case .phone(_, let code) = method, code.count != 6 { throw SundaeError.invalidCode }
        var me = users[meID]!
        if let username, !username.isEmpty { me.username = username }
        if let name, !name.isEmpty { me.name = name }
        users[meID] = me
        signedInUserID = meID
        return Session(token: "mock-session-token", user: me)
    }

    func restoreSession(token: String) async throws -> User? {
        guard token == "mock-session-token" else { return nil }
        signedInUserID = meID
        return users[meID]
    }

    func signOut() async throws {
        signedInUserID = nil
    }

    func updateProfile(name: String, username: String, bio: String) async throws -> User {
        var me = try requireSignedIn()
        me.name = name
        me.username = username
        me.bio = bio
        Self.propagate(me, users: &users, dumps: &dumps, comments: &comments)
        return me
    }

    func updateAvatar(_ photo: ProcessedPhoto) async throws -> User {
        var me = try requireSignedIn()
        me.avatar = .data(photo.data)
        Self.propagate(me, users: &users, dumps: &dumps, comments: &comments)
        UserDefaults.standard.set(photo.data, forKey: Self.avatarKey)
        return me
    }

    func accountSettings() async throws -> AccountSettings {
        _ = try requireSignedIn()
        return settings
    }

    func updateAccountSettings(_ settings: AccountSettings) async throws {
        var me = try requireSignedIn()
        self.settings = settings
        me.isPublic = settings.isPublic
        users[me.id] = me
    }

    func deleteAccount() async throws {
        let me = try requireSignedIn()
        dumps = dumps.filter { $0.value.author.id != me.id }
        for (id, var dump) in dumps {
            dump.photos = dump.photos.map { photo in
                var p = photo
                p.tags.removeAll { $0.taggedUser.id == me.id }
                return p
            }
            dumps[id] = dump
        }
        signedInUserID = nil
    }

    // MARK: - Feed and dumps

    func feed(olderThan: Date?, limit: Int) async throws -> [Dump] {
        let me = try requireSignedIn()
        try requireSunday()
        try await latency()
        return dumps.values
            .filter { canRead($0, as: me.id) }
            .filter { dump in olderThan.map { dump.createdAt < $0 } ?? true }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func dump(id: ID) async throws -> Dump {
        let me = try requireSignedIn()
        try requireSunday()
        guard let dump = dumps[id] else { throw SundaeError.notFound }
        guard canRead(dump, as: me.id) else { throw SundaeError.notAuthorized }
        return dump
    }

    func myDump(weekStart: Date) async throws -> Dump? {
        let me = try requireSignedIn()
        try requireSunday()
        return dumps.values.first { $0.author.id == me.id && $0.weekStart == weekStart }
    }

    func saveDump(_ draft: DumpDraft, weekStart: Date) async throws -> Dump {
        let me = try requireSignedIn()
        try requireSunday()
        guard (1...DumpDraft.maxPhotos).contains(draft.photos.count) else { throw SundaeError.tooManyPhotos }
        guard draft.photos.allSatisfy({ $0.taggedUsers.count <= DumpDraft.maxTagsPerPhoto }) else { throw SundaeError.tooManyTags }
        guard draft.caption.count <= DumpDraft.maxCaptionLength else { throw SundaeError.captionTooLong }
        guard weekStart == clock.weekStart() else { throw SundaeError.dumpLocked }
        try await latency()

        let taggable = Set(taggableIDs(for: me.id))
        let existing = dumps.values.first { $0.author.id == me.id && $0.weekStart == weekStart }
        if let existing, existing.isLocked { throw SundaeError.dumpLocked }

        let dumpID = existing?.id ?? "d_\(UUID().uuidString)"
        let oldPhotos = Dictionary(uniqueKeysWithValues: (existing?.photos ?? []).map { ($0.id, $0) })

        let photos: [Photo] = draft.photos.enumerated().map { index, draftPhoto in
            let old = oldPhotos[draftPhoto.id]
            let tags: [Tag] = draftPhoto.taggedUsers.filter { taggable.contains($0.id) }.map { user in
                if let kept = old?.tags.first(where: { $0.taggedUser.id == user.id && $0.status != .declined && $0.status != .removed }) {
                    return kept
                }
                return Tag(id: "t_\(UUID().uuidString)", photoID: draftPhoto.id, taggerID: me.id,
                           taggedUser: user, status: .pending, respondedAt: nil)
            }
            return Photo(id: draftPhoto.id, dumpID: dumpID, order: index, source: draftPhoto.source,
                         width: draftPhoto.width, height: draftPhoto.height,
                         altText: draftPhoto.altText.isEmpty ? nil : draftPhoto.altText, tags: tags)
        }

        let dump = Dump(id: dumpID, author: me, weekStart: weekStart, caption: draft.caption,
                        createdAt: existing?.createdAt ?? clock.now(), lockedAt: nil, photos: photos,
                        commentsEnabled: draft.commentsEnabled,
                        likedBy: existing?.likedBy ?? [], likedByMe: false,
                        commentCount: existing?.commentCount ?? 0)
        dumps[dumpID] = dump
        return dump
    }

    func deleteDump(id: ID) async throws {
        let me = try requireSignedIn()
        guard let dump = dumps[id] else { throw SundaeError.notFound }
        guard dump.author.id == me.id else { throw SundaeError.notAuthorized }
        dumps[id] = nil
        comments[id] = nil
    }

    func setLike(dumpID: ID, liked: Bool) async throws -> Dump {
        let me = try requireSignedIn()
        try requireSunday()
        guard var dump = dumps[dumpID], canRead(dump, as: me.id) else { throw SundaeError.notFound }
        dump.likedBy.removeAll { $0.id == me.id }
        if liked { dump.likedBy.insert(me, at: 0) }
        dump.likedByMe = liked
        dumps[dumpID] = dump
        return dump
    }

    func comments(dumpID: ID) async throws -> [Comment] {
        let me = try requireSignedIn()
        try requireSunday()
        guard let dump = dumps[dumpID], canRead(dump, as: me.id) else { throw SundaeError.notFound }
        return (comments[dumpID] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    func addComment(dumpID: ID, body: String) async throws -> Comment {
        let me = try requireSignedIn()
        try requireSunday()
        guard var dump = dumps[dumpID], canRead(dump, as: me.id) else { throw SundaeError.notFound }
        guard dump.commentsEnabled else { throw SundaeError.notAuthorized }
        let comment = Comment(id: "c_\(UUID().uuidString)", dumpID: dumpID, author: me, body: body, createdAt: clock.now())
        comments[dumpID, default: []].append(comment)
        dump.commentCount += 1
        dumps[dumpID] = dump
        return comment
    }

    // MARK: - Profiles

    func profile(userID: ID) async throws -> Profile {
        let me = try requireSignedIn()
        try requireSunday()
        guard let user = users[userID] else { throw SundaeError.notFound }
        try await latency()
        let rel = relationship(of: me.id, to: userID)
        let canSee = rel == .me || rel == .following || user.isPublic
        let starts = clock.recentWeekStarts(count: 12)
        var weeks: [ProfileWeek] = []
        if canSee {
            for start in starts {
                let own = dumps.values.first { $0.author.id == userID && $0.weekStart == start }
                let tagged: [TaggedPhoto] = dumps.values
                    .filter { $0.weekStart == start && $0.author.id != userID && canRead($0, as: me.id) }
                    .flatMap { dump in
                        dump.photos.compactMap { photo in
                            photo.tags.first { $0.taggedUser.id == userID && $0.status == .approved }
                                .map { TaggedPhoto(photo: photo, from: dump.author, tag: $0) }
                        }
                    }
                    .sorted { ($0.tag.respondedAt ?? .distantPast) < ($1.tag.respondedAt ?? .distantPast) }
                let week = ProfileWeek(weekStart: start, dump: own, tagged: tagged)
                // Other people's current week only shows once something is in it.
                if start == starts.first, rel != .me, week.isEmpty { continue }
                weeks.append(week)
            }
            // Trim leading empties older than the user's first activity so a new account isn't a wall of gaps.
            while let last = weeks.last, last.isEmpty, weeks.count > 1 { weeks.removeLast() }
        }
        let followers = follows.filter { $0.followeeID == userID && $0.status == .accepted }.count
        let following = follows.filter { $0.followerID == userID && $0.status == .accepted }.count
        return Profile(user: user, relationship: rel, weeks: weeks,
                       followerCount: rel == .me ? followers : nil,
                       followingCount: rel == .me ? following : nil)
    }

    func searchUsers(_ query: String) async throws -> [User] {
        let me = try requireSignedIn()
        try requireSunday()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return users.values
            .filter { $0.id != me.id && !blocked.contains($0.id) }
            .filter { $0.username.lowercased().contains(q) || $0.name.lowercased().contains(q) }
            .sorted { $0.username < $1.username }
            .map { withContext($0, viewer: me.id) }
    }

    /// Fills in "followed by" with the viewer's follows who follow this user.
    private func withContext(_ user: User, viewer: ID) -> User {
        let mine = Set(follows.filter { $0.followerID == viewer && $0.status == .accepted }.map(\.followeeID))
        let names = follows
            .filter { $0.followeeID == user.id && $0.status == .accepted && mine.contains($0.followerID) }
            .compactMap { users[$0.followerID]?.username }
            .sorted()
        var copy = user
        copy.followedBy = names
        return copy
    }

    func suggestedUsers() async throws -> [User] {
        let me = try requireSignedIn()
        try requireSunday()
        let myFollows = Set(follows.filter { $0.followerID == me.id }.map(\.followeeID))
        let friendsOfFriends = follows
            .filter { myFollows.contains($0.followerID) && $0.status == .accepted }
            .map(\.followeeID)
        var seen = Set<ID>()
        return friendsOfFriends
            .filter { $0 != me.id && !myFollows.contains($0) && !blocked.contains($0) && seen.insert($0).inserted }
            .compactMap { users[$0] }
            .map { withContext($0, viewer: me.id) }
    }

    func follow(userID: ID) async throws -> Relationship {
        let me = try requireSignedIn()
        try requireSunday()
        guard let target = users[userID], userID != me.id else { throw SundaeError.notFound }
        follows.removeAll { $0.followerID == me.id && $0.followeeID == userID }
        let status: Follow.Status = target.isPublic ? .accepted : .requested
        follows.append(Follow(followerID: me.id, followeeID: userID, status: status))
        return status == .accepted ? .following : .requested
    }

    func unfollow(userID: ID) async throws {
        let me = try requireSignedIn()
        try requireSunday()
        follows.removeAll { $0.followerID == me.id && $0.followeeID == userID }
    }

    func followRequests() async throws -> [User] {
        let me = try requireSignedIn()
        return follows
            .filter { $0.followeeID == me.id && $0.status == .requested }
            .compactMap { users[$0.followerID] }
    }

    func respondToFollowRequest(from userID: ID, accept: Bool) async throws {
        let me = try requireSignedIn()
        guard let index = follows.firstIndex(where: { $0.followerID == userID && $0.followeeID == me.id && $0.status == .requested }) else { return }
        if accept { follows[index].status = .accepted } else { follows.remove(at: index) }
    }

    private func taggableIDs(for userID: ID) -> [ID] {
        var ids = Set<ID>()
        for f in follows where f.status == .accepted {
            if f.followerID == userID { ids.insert(f.followeeID) }
            if f.followeeID == userID { ids.insert(f.followerID) }
        }
        return ids.subtracting(blocked).sorted()
    }

    func taggableUsers() async throws -> [User] {
        let me = try requireSignedIn()
        return taggableIDs(for: me.id).compactMap { users[$0] }.sorted { $0.displayName < $1.displayName }
    }

    func contactsHashingKey() async throws -> ContactsHashingKey {
        _ = try requireSignedIn()
        return ContactsHashingKey(keyID: "mock-key", key: Data(repeating: 0x42, count: 32), expiresAt: clock.now().addingTimeInterval(900))
    }

    func matchContacts(hashes: [String], keyID: String) async throws -> [User] {
        let me = try requireSignedIn()
        try await latency()
        guard !hashes.isEmpty else { return [] }
        // The mock cannot know real numbers; pretend two people from the address book are here.
        return ["u_riley", "u_dev"].compactMap { users[$0] }.filter { $0.id != me.id && !blocked.contains($0.id) }.map { withContext($0, viewer: me.id) }
    }

    // MARK: - Tags (every day)

    func pendingTagRequests() async throws -> [TagRequest] {
        let me = try requireSignedIn()
        return dumps.values
            .filter { !blocked.contains($0.author.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .flatMap { dump in
                dump.photos.flatMap { photo in
                    photo.tags
                        .filter { $0.taggedUser.id == me.id && $0.status == .pending }
                        .map { TagRequest(tag: $0, photo: photo, tagger: dump.author, weekStart: dump.weekStart) }
                }
            }
    }

    private func updateTag(id: ID, _ change: (inout Tag) -> Void) throws {
        for (dumpID, var dump) in dumps {
            for p in dump.photos.indices {
                if let t = dump.photos[p].tags.firstIndex(where: { $0.id == id }) {
                    change(&dump.photos[p].tags[t])
                    dumps[dumpID] = dump
                    return
                }
            }
        }
        throw SundaeError.notFound
    }

    func respondToTag(id: ID, approve: Bool) async throws {
        let me = try requireSignedIn()
        let now = clock.now()
        try updateTag(id: id) { tag in
            guard tag.taggedUser.id == me.id else { return }
            tag.status = approve ? .approved : .declined
            tag.respondedAt = now
        }
    }

    func removeTaggedPhoto(tagID: ID) async throws {
        let me = try requireSignedIn()
        let now = clock.now()
        try updateTag(id: tagID) { tag in
            guard tag.taggedUser.id == me.id else { return }
            tag.status = .removed
            tag.respondedAt = now
        }
    }

    // MARK: - Suggestions, safety

    func suggestionsDone(weekStart: Date) async throws -> [SuggestionDone] {
        _ = try requireSignedIn()
        let end = clock.weekEnd(containing: weekStart)
        return done.filter { $0.doneOn >= weekStart && $0.doneOn < end }
    }

    func markSuggestionDone(id: String, on day: Date) async throws {
        _ = try requireSignedIn()
        done.removeAll { $0.suggestionID == id }
        done.append(SuggestionDone(suggestionID: id, doneOn: day))
    }

    func block(userID: ID) async throws {
        let me = try requireSignedIn()
        blocked.insert(userID)
        follows.removeAll { ($0.followerID == me.id && $0.followeeID == userID) || ($0.followerID == userID && $0.followeeID == me.id) }
        for (dumpID, var dump) in dumps {
            let authorID = dump.author.id
            for p in dump.photos.indices {
                dump.photos[p].tags.removeAll {
                    ($0.taggedUser.id == me.id && authorID == userID) || ($0.taggedUser.id == userID && authorID == me.id)
                }
            }
            dumps[dumpID] = dump
        }
    }

    func report(_ report: Report) async throws {
        _ = try requireSignedIn()
        // Reports go to the moderation queue on the server. Nothing to do locally.
    }

    // MARK: - Seed data

    /// Builds the seed world for a given clock. Static so the actor's init can call it.
    private static func makeSeed(clock: SundayClock) -> SeedData {
        var users: [ID: User] = [:]
        var follows: [Follow] = []
        var dumps: [ID: Dump] = [:]
        var comments: [ID: [Comment]] = [:]
        let meID = Self.meID

        let tz = TimeZone.current.identifier
        func avatar(_ n: Int) -> PhotoSource { .remote(URL(string: "https://i.pravatar.cc/300?img=\(n)")!) }
        func photo(_ seed: Int, _ size: (Int, Int)) -> PhotoSource {
            .remote(URL(string: "https://picsum.photos/seed/sundae\(seed)/\(size.0 / 2)/\(size.1 / 2)")!)
        }
        let me = User(id: meID, username: "jon", name: "Jon Moore", bio: "Sundays only.", avatar: avatar(12), isPublic: false, timezone: tz)
        let friendSpecs: [(ID, String, String, String)] = [
            ("u_maya", "maya", "Maya Chen", "Farmers market regular."),
            ("u_theo", "theo", "Theo Park", "Bikes, bread, bad puns."),
            ("u_priya", "priya", "Priya Nair", "Always the one holding the camera."),
            ("u_jonah", "jonah", "Jonah Reyes", ""),
            ("u_sam", "sam", "Sam Okafor", "Sunset collector."),
            ("u_lena", "lena", "Lena Fischer", "New in town. Show me around."),
        ]
        let avatarIDs = [47, 59, 32, 68, 25, 16]
        let friends = friendSpecs.enumerated().map { i, s in
            User(id: s.0, username: s.1, name: s.2, bio: s.3, avatar: avatar(avatarIDs[i]), isPublic: false, timezone: tz)
        }
        let riley = User(id: "u_riley", username: "riley", name: "Riley Brooks", bio: "", avatar: avatar(36), isPublic: false, timezone: tz)
        let noor = User(id: "u_noor", username: "noor", name: "Noor Haddad", bio: "Street photos, mostly.", avatar: avatar(44), isPublic: true, timezone: tz)
        let dev = User(id: "u_dev", username: "dev", name: "Dev Patel", bio: "", avatar: avatar(53), isPublic: false, timezone: tz)
        for u in [me] + friends + [riley, noor, dev] { users[u.id] = u }

        for f in friends {
            follows.append(Follow(followerID: me.id, followeeID: f.id, status: .accepted))
            follows.append(Follow(followerID: f.id, followeeID: me.id, status: .accepted))
        }
        for (a, b) in [(friends[0], friends[1]), (friends[1], friends[2]), (friends[0], friends[2]), (friends[3], friends[4]), (friends[4], friends[5])] {
            follows.append(Follow(followerID: a.id, followeeID: b.id, status: .accepted))
            follows.append(Follow(followerID: b.id, followeeID: a.id, status: .accepted))
        }
        follows.append(Follow(followerID: riley.id, followeeID: me.id, status: .requested))
        follows.append(Follow(followerID: friends[0].id, followeeID: dev.id, status: .accepted))
        follows.append(Follow(followerID: friends[1].id, followeeID: noor.id, status: .accepted))

        let captions = [
            "Bikes, a very long lunch, and the first cold morning.",
            "Mostly rain. Found the good bakery though.",
            "Lena's first week here. We showed her the bad view and the good one.",
            "Market haul, a hike that was mostly uphill, Sam's birthday.",
            "Quiet one. Lots of soup.",
            "Three sunsets, one sunrise, zero regrets.",
            "The week the car broke down and we walked everywhere. Recommended.",
            "Theo made bread. It was bread-shaped.",
            "Cold water swim. Never again. (Next week.)",
            "Golden hour every single evening somehow.",
        ]
        let sizes = [(1600, 1200), (1200, 1600), (1600, 1600), (2048, 1536), (1536, 2048)]
        let starts = clock.recentWeekStarts(count: 10)
        let sundayNow = clock.isSunday()
        var seedCounter = 100

        for (w, start) in starts.enumerated() {
            if w == 0 && !sundayNow { continue }
            let sunday = clock.sundayStart(forWeekContaining: start)
            let locked: Date? = w == 0 ? nil : clock.weekEnd(containing: start)

            for (i, friend) in friends.enumerated() {
                if (w + i) % 4 == 3 { continue }
                if w == 0 && i >= 4 { continue }
                let dumpID = "d_\(friend.username)_\(w)"
                let count = 3 + (w + i * 2) % 6
                var photos: [Photo] = []
                for n in 0..<count {
                    seedCounter += 1
                    let size = sizes[(n + i + w) % sizes.count]
                    let photoID = "\(dumpID)_p\(n)"
                    var tags: [Tag] = []
                    if n == 0 {
                        let status: Tag.Status = w <= 1 ? .pending : .approved
                        tags.append(Tag(id: "t_\(photoID)_me", photoID: photoID, taggerID: friend.id, taggedUser: me,
                                        status: status, respondedAt: status == .approved ? sunday.addingTimeInterval(3600 * 5) : nil))
                    }
                    if n == 1 {
                        let other = friends[(i + 1) % friends.count]
                        tags.append(Tag(id: "t_\(photoID)_\(other.username)", photoID: photoID, taggerID: friend.id, taggedUser: other,
                                        status: .approved, respondedAt: sunday.addingTimeInterval(3600 * 6)))
                    }
                    photos.append(Photo(id: photoID, dumpID: dumpID, order: n, source: photo(seedCounter, size),
                                        width: size.0, height: size.1, altText: nil, tags: tags))
                }
                let likers = friends.filter { $0.id != friend.id }.prefix((w + i) % 4 + (w == 0 ? 0 : 1)).map { $0 }
                let createdAt = sunday.addingTimeInterval(3600 * 8 + Double(i) * 1500)
                dumps[dumpID] = Dump(id: dumpID, author: friend, weekStart: start, caption: captions[(w + i) % captions.count],
                                     createdAt: createdAt, lockedAt: locked, photos: photos, commentsEnabled: true,
                                     likedBy: likers, likedByMe: false, commentCount: 0)
                if (w + i) % 3 == 0 {
                    let commenter = friends[(i + 2) % friends.count]
                    let body = [
                        "The third one is my favorite. You can tell the light was about to go and nobody wanted to leave yet. Put that one on the fridge.",
                        "Ok that view. I had no idea that was twenty minutes from your place. We are doing this next Sunday and I am bringing the good coffee.",
                        "We need to go back when the trees have turned. Also I am fairly sure that is the same bench from Theo's week, which is a little funny.",
                        "The bread looked great actually, do not let anyone tell you otherwise. Save me a slice if there is a next time and I will bring the butter.",
                    ][(w + i) % 4]
                    comments[dumpID] = [Comment(id: "c_\(dumpID)", dumpID: dumpID, author: commenter, body: body, createdAt: createdAt.addingTimeInterval(5400))]
                    dumps[dumpID]?.commentCount = 1
                }
            }

            // My own past weeks, with gaps so the profile shows honest empty rows.
            if w != 0 && ![3, 6, 8, 9].contains(w) {
                let dumpID = "d_me_\(w)"
                let count = 4 + w % 4
                let photos: [Photo] = (0..<count).map { n in
                    seedCounter += 1
                    let size = sizes[(n + w) % sizes.count]
                    let photoID = "\(dumpID)_p\(n)"
                    var tags: [Tag] = []
                    if n == 0 || n == 2 {
                        let f = friends[(n + w) % friends.count]
                        tags.append(Tag(id: "t_\(photoID)_\(f.username)", photoID: photoID, taggerID: me.id, taggedUser: f,
                                        status: .approved, respondedAt: sunday.addingTimeInterval(3600 * 7)))
                    }
                    return Photo(id: photoID, dumpID: dumpID, order: n, source: photo(seedCounter, size),
                                 width: size.0, height: size.1, altText: nil, tags: tags)
                }
                dumps[dumpID] = Dump(id: dumpID, author: me, weekStart: start, caption: captions[(w + 3) % captions.count],
                                     createdAt: sunday.addingTimeInterval(3600 * 10), lockedAt: locked, photos: photos,
                                     commentsEnabled: true, likedBy: Array(friends.prefix(2 + w % 3)), likedByMe: false, commentCount: 0)
            }
        }
        return SeedData(users: users, follows: follows, dumps: dumps, comments: comments)
    }
}

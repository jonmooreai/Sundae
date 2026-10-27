import SwiftUI

/// Your followers and the people you follow, opened from the counts on your profile. A search
/// narrows the list; a follower can be removed, and anyone you follow unfollowed. Only ever your
/// own lists: nobody else sees who you follow or who follows you.
struct PeopleListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var list: PeopleList
    @State private var query = ""
    /// Nil until they load.
    @State private var followers: [User]?
    @State private var following: [User]?
    /// Anyone unfollowed or followed again here. They keep their row, so a slip can be undone.
    @State private var relationships: [ID: Relationship] = [:]
    @State private var loadFailed = false
    @State private var confirmRemove: User?
    @State private var confirmUnfollow: User?
    @State private var working: Set<ID> = []
    @State private var actionFailed = false

    init(initial: PeopleList) {
        _list = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: list == .followers ? "Followers" : "Following", showsBack: true) { EmptyView() }
            ChipPicker(options: [(PeopleList.followers, "Followers"), (PeopleList.following, "Following")], selection: $list)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            SearchField(text: $query, placeholder: "Search")
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 6)
            List {
                content
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 70)
            .refreshable { await load() }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .confirmationDialog(confirmRemove.map { Self.removeTitle($0) } ?? "Remove follower?",
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                            titleVisibility: .visible,
                            presenting: confirmRemove) { user in
            Button("Remove", role: .destructive) { Task { await remove(user) } }
        } message: { _ in
            Text("They stop seeing your weeks and aren't told. If your account is private they would have to ask again.")
        }
        .confirmationDialog(confirmUnfollow.map { Self.unfollowTitle($0) } ?? "Unfollow?",
                            isPresented: Binding(get: { confirmUnfollow != nil }, set: { if !$0 { confirmUnfollow = nil } }),
                            titleVisibility: .visible,
                            presenting: confirmUnfollow) { user in
            Button("Unfollow", role: .destructive) { Task { await unfollow(user) } }
        } message: { user in
            Text(user.isPublic
                 ? "Their weeks leave your feed. You can follow again any time."
                 : "Their weeks leave your feed. Their account is private, so following again is a new request.")
        }
        .alert("Couldn't reach Sundae", isPresented: $actionFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Nothing changed. Try again when you're online.")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var content: some View {
        if let people = shown {
            if people.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .listRowInsets(rowInsets)
                    .listRowSeparator(.hidden)
            }
            ForEach(people) { user in
                row(user)
            }
        } else if loadFailed {
            VStack(alignment: .leading, spacing: 10) {
                Text("Couldn't load them. Check your connection.")
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await load() } }
                    .buttonStyle(.pill(.secondary, size: .small))
            }
            .listRowInsets(rowInsets)
            .listRowSeparator(.hidden)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                .listRowSeparator(.hidden)
        }
    }

    /// Row content with an invisible link behind it to their profile, so there is no chevron.
    private func row(_ user: User) -> some View {
        HStack(spacing: 8) {
            // The name and the username together: a name can be copied, a username can't.
            UserRow(user: user, title: user.displayName, subtitle: user.handle)
            switch list {
            case .followers:
                Button { confirmRemove = user } label: { Text("Remove").frame(width: 70) }
                    .buttonStyle(.pill(.secondary, size: .small))
                    .disabled(working.contains(user.id))
            case .following:
                FollowButton(relationship: relationships[user.id] ?? .following) { tapFollow(user) }
                    .disabled(working.contains(user.id))
            }
        }
        .background { NavigationLink(value: Route.profile(user.id)) { EmptyView() }.opacity(0) }
        .listRowInsets(rowInsets)
        .listRowSeparator(.hidden)
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 8, leading: Theme.pagePadding, bottom: 8, trailing: Theme.pagePadding)
    }

    /// The list on screen, narrowed by the search: by username or any part of the name.
    private var shown: [User]? {
        guard let everyone = list == .followers ? followers : following else { return nil }
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !words.isEmpty else { return everyone }
        return everyone.filter { $0.username.lowercased().contains(words) || $0.name.lowercased().contains(words) }
    }

    private var emptyText: String {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return "Nobody by that name." }
        return list == .followers ? "Nobody follows you yet." : "You don't follow anyone yet. Find your friends in Search."
    }

    // MARK: - Titles

    /// "Remove Pat Doe?"
    nonisolated static func removeTitle(_ user: User) -> String {
        "Remove \(user.displayName)?"
    }

    /// "Unfollow Pat Doe?"
    nonisolated static func unfollowTitle(_ user: User) -> String {
        "Unfollow \(user.displayName)?"
    }

    // MARK: - Actions

    private func load() async {
        loadFailed = false
        let api = model.api
        do {
            async let theirs = api.followers()
            async let mine = api.following()
            let (loadedFollowers, loadedFollowing) = try await (theirs, mine)
            followers = loadedFollowers
            following = loadedFollowing
        } catch {
            if followers == nil || following == nil { loadFailed = true }
        }
    }

    /// Following asks first; a request is simply taken back; and someone unfollowed here can be
    /// followed again from the same row.
    private func tapFollow(_ user: User) {
        switch relationships[user.id] ?? .following {
        case .following: confirmUnfollow = user
        case .requested: Task { await unfollow(user) }
        case .notFollowing: Task { await follow(user) }
        case .me, .blocked: break
        }
    }

    /// Leaves the list only once the server has removed them.
    private func remove(_ user: User) async {
        guard working.insert(user.id).inserted else { return }
        defer { working.remove(user.id) }
        do {
            try await model.api.removeFollower(userID: user.id)
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                followers = followers?.filter { $0.id != user.id }
            }
            Haptics.light()
            changed()
        } catch {
            actionFailed = true
        }
    }

    private func unfollow(_ user: User) async {
        guard working.insert(user.id).inserted else { return }
        defer { working.remove(user.id) }
        do {
            try await model.api.unfollow(userID: user.id)
            relationships[user.id] = .notFollowing
            Haptics.light()
            changed()
        } catch {
            actionFailed = true
        }
    }

    private func follow(_ user: User) async {
        guard working.insert(user.id).inserted else { return }
        defer { working.remove(user.id) }
        do {
            relationships[user.id] = try await model.api.follow(userID: user.id)
            Haptics.light()
            changed()
        } catch {
            actionFailed = true
        }
    }

    /// The profile under this shows the new counts, and tagging knows who is still a friend.
    private func changed() {
        model.followsChanged += 1
        Task { await model.compose.refreshTaggable() }
    }
}

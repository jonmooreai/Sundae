import SwiftUI

/// Someone's followers and the people they follow, opened from the counts on their profile, for
/// whoever can see that profile. Two tabs with the counts, a search, and each person with a Follow,
/// Follow back or Following button. On your own followers, Remove.
struct PeopleListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabSpace

    let userID: ID
    let username: String
    @State private var list: PeopleList
    @State private var query = ""
    /// Nil until they load.
    @State private var followers: [ListedPerson]?
    @State private var following: [ListedPerson]?
    /// How the viewer stands with people followed, unfollowed or asked here. Rows stay, so a slip
    /// can be undone from the same button.
    @State private var changed: [ID: Relationship] = [:]
    @State private var loadFailed = false
    @State private var confirmRemove: User?
    @State private var confirmUnfollow: User?
    @State private var working: Set<ID> = []
    @State private var actionFailed = false

    init(userID: ID, username: String, initial: PeopleList) {
        self.userID = userID
        self.username = username
        _list = State(initialValue: initial)
    }

    private var isOwn: Bool { userID == model.currentUser?.id }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: username, showsBack: true) { EmptyView() }
            tabs
            SearchField(text: $query, placeholder: "Search username or name")
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 12)
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

    // MARK: - Tabs

    private var tabs: some View {
        HStack(spacing: 0) {
            tab(.followers, title: followers.map { "\($0.count) \($0.count == 1 ? "follower" : "followers")" } ?? "Followers")
            tab(.following, title: following.map { "\($0.count) following" } ?? "Following")
        }
        .padding(.horizontal, Theme.pagePadding)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func tab(_ which: PeopleList, title: String) -> some View {
        let isOn = list == which
        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { list = which }
        } label: {
            VStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ZStack {
                    Color.clear.frame(height: 2)
                    if isOn {
                        Capsule()
                            .fill(Color.primary)
                            .frame(height: 2)
                            .padding(.horizontal, 20)
                            .matchedGeometryEffect(id: "tab", in: tabSpace)
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
            ForEach(people) { person in
                row(person)
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

    /// The username first, the name under it; the button for how you stand with them; behind it
    /// all, an invisible link to their profile, so there is no chevron.
    private func row(_ person: ListedPerson) -> some View {
        let relationship = changed[person.id] ?? person.relationship
        let removable = isOwn && list == .followers
        return HStack(spacing: 12) {
            AvatarView(user: person.user, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(person.user.username)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    // On your own followers the button is Remove, so following back is a word here.
                    if removable, relationship == .notFollowing {
                        Text("\u{00B7}").foregroundStyle(.secondary)
                        Button("Follow back") { Task { await follow(person.user) } }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .buttonStyle(.plain)
                            .disabled(working.contains(person.id))
                    }
                }
                if !person.user.name.isEmpty {
                    Text(person.user.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if relationship == .me {
                EmptyView()
            } else if removable {
                Button { confirmRemove = person.user } label: { Text("Remove").frame(width: FollowButton.width) }
                    .buttonStyle(.pill(.secondary, size: .small))
                    .disabled(working.contains(person.id))
            } else {
                FollowButton(relationship: relationship, followsYou: person.followsYou) { tapFollow(person.user, relationship) }
                    .disabled(working.contains(person.id))
            }
        }
        .contentShape(Rectangle())
        .background { NavigationLink(value: Route.profile(person.id)) { EmptyView() }.opacity(0) }
        .listRowInsets(rowInsets)
        .listRowSeparator(.hidden)
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 8, leading: Theme.pagePadding, bottom: 8, trailing: Theme.pagePadding)
    }

    /// The list on screen, narrowed by the search: by username or any part of the name.
    private var shown: [ListedPerson]? {
        guard let everyone = list == .followers ? followers : following else { return nil }
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !words.isEmpty else { return everyone }
        return everyone.filter { $0.user.username.lowercased().contains(words) || $0.user.name.lowercased().contains(words) }
    }

    private var emptyText: String {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return "Nobody by that name." }
        switch (list, isOwn) {
        case (.followers, true): return "Nobody follows you yet."
        case (.following, true): return "You don't follow anyone yet. Find your friends in Search."
        case (.followers, false): return "Nobody follows \(username) yet."
        case (.following, false): return "\(username) doesn't follow anyone yet."
        }
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
        let id = userID
        do {
            async let theirs = api.followList(of: id, .followers)
            async let mine = api.followList(of: id, .following)
            let (loadedFollowers, loadedFollowing) = try await (theirs, mine)
            followers = loadedFollowers
            following = loadedFollowing
            changed = [:]
        } catch {
            if followers == nil || following == nil { loadFailed = true }
        }
    }

    /// Following asks first; a request is simply taken back; Follow and Follow back follow.
    private func tapFollow(_ user: User, _ relationship: Relationship) {
        switch relationship {
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
            noteChange()
        } catch {
            actionFailed = true
        }
    }

    private func unfollow(_ user: User) async {
        guard working.insert(user.id).inserted else { return }
        defer { working.remove(user.id) }
        do {
            try await model.api.unfollow(userID: user.id)
            changed[user.id] = .notFollowing
            Haptics.light()
            noteChange()
        } catch {
            actionFailed = true
        }
    }

    private func follow(_ user: User) async {
        guard working.insert(user.id).inserted else { return }
        defer { working.remove(user.id) }
        do {
            changed[user.id] = try await model.api.follow(userID: user.id)
            Haptics.light()
            noteChange()
        } catch {
            actionFailed = true
        }
    }

    /// The profile under this shows the new counts, and tagging knows who is still a friend.
    private func noteChange() {
        model.followsChanged += 1
        Task { await model.compose.refreshTaggable() }
    }
}

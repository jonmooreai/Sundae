import SwiftUI

struct SearchScreen: View {
    /// Taps on the tab while it shows: back to search, then a fresh search at the top.
    var reselects = 0
    @State private var path: [Route] = []
    @State private var scrollSignal = 0

    var body: some View {
        NavigationStack(path: $path) {
            SearchView()
                .environment(\.scrollToTop, scrollSignal)
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
                .aboveBottomBar()
                .swipeBackEnabled()
        }
        .onChange(of: reselects) { _, _ in
            if path.isEmpty { scrollSignal += 1 } else { path.removeAll() }
        }
    }
}

/// Find people by name or username. No hashtags, no explore.
///
/// A plain stack, not a List: in a List a tap on the row can land on a button in it, and a tap
/// meant to open someone's profile must never follow them. Here the name opens the profile and
/// the button is only the button.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [ListedPerson] = []
    @State private var suggested: [ListedPerson] = []
    /// How you stand with people since you followed or unfollowed them here.
    @State private var relationships: [ID: Relationship] = [:]
    @State private var working: Set<ID> = []
    @State private var confirmUnfollow: User?
    @State private var isSearching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scrollToTop) private var scrollToTop

    var body: some View {
        searchBody
            .centeredColumn()
            // The column is cream; so are the sides, edge to edge, on a screen wider than it.
            .background(Theme.background)
            .sideBarChrome()
    }

    private var searchBody: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Search") { EmptyView() }
            SearchField(text: $query, placeholder: "Name or username")
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ScrollTop()
                        if query.isEmpty {
                            if !suggested.isEmpty {
                                header("Suggested for you")
                                ForEach(suggested) { person in row(person) }
                            }
                            ShareLink(item: Invite.note, subject: Text(Invite.subject)) {
                                actionRow(Glyph.share, "Invite your group", "Sundae works when the whole group is here.")
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, Theme.pagePadding)
                            .padding(.vertical, 8)
                            .padding(.top, suggested.isEmpty ? 0 : 8)
                        } else {
                            ForEach(results) { person in row(person) }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
                .overlay {
                    if !query.isEmpty && results.isEmpty && !isSearching {
                        EmptyState(glyph: Glyph.search, message: "Nobody by that name yet.")
                    }
                }
                // The tab tapped again: a fresh search, from the top.
                .onChange(of: scrollToTop) { _, _ in
                    query = ""
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.4)) { proxy.scrollTo(ScrollTop.id, anchor: .top) }
                }
            }
        }
        .background(Theme.background)
        .task {
            await loadInitial()
        }
        .task(id: query) {
            guard !query.isEmpty else {
                results = []
                return
            }
            isSearching = true
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            results = (try? await model.api.searchUsers(query)) ?? []
            isSearching = false
        }
        .confirmationDialog(confirmUnfollow.map { PeopleListView.unfollowTitle($0) } ?? "Unfollow?",
                            isPresented: Binding(get: { confirmUnfollow != nil }, set: { if !$0 { confirmUnfollow = nil } }),
                            titleVisibility: .visible,
                            presenting: confirmUnfollow) { user in
            Button("Unfollow", role: .destructive) { Task { await setFollowing(user, false) } }
        } message: { user in
            Text(user.isPublic
                 ? "Their weeks leave your feed. You can follow again any time."
                 : "Their weeks leave your feed. Their account is private, so following again is a new request.")
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func actionRow(_ glyph: Ph, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Icon(glyph, size: 22)
                .frame(width: 54, height: 54)
                .background(Theme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// The person opens their profile; the button beside them says how you stand with them now:
    /// Follow, Follow back, Requested or Following.
    private func row(_ person: ListedPerson) -> some View {
        let relationship = relationships[person.id] ?? person.relationship
        return HStack(spacing: 8) {
            NavigationLink(value: Route.profile(person.id)) {
                UserRow(user: person.user)
            }
            .buttonStyle(.plain)
            FollowButton(relationship: relationship, followsYou: person.followsYou) {
                tapFollow(person.user, relationship)
            }
            .disabled(working.contains(person.id))
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 8)
    }

    private func loadInitial() async {
        suggested = (try? await model.api.suggestedUsers()) ?? []
    }

    /// Follow and Follow back follow; a request is simply taken back; Following asks first.
    private func tapFollow(_ user: User, _ relationship: Relationship) {
        switch relationship {
        case .notFollowing: Task { await setFollowing(user, true) }
        case .requested: Task { await setFollowing(user, false) }
        case .following: confirmUnfollow = user
        case .me, .blocked: break
        }
    }

    private func setFollowing(_ user: User, _ follow: Bool) async {
        guard working.insert(user.id).inserted else { return }
        defer { working.remove(user.id) }
        do {
            if follow {
                relationships[user.id] = try await model.api.follow(userID: user.id)
                Haptics.light()
            } else {
                try await model.api.unfollow(userID: user.id)
                relationships[user.id] = .notFollowing
            }
            model.followsChanged += 1
            Task { await model.compose.refreshTaggable() }
        } catch {
            // The server decides; the row stays as it was.
        }
    }
}

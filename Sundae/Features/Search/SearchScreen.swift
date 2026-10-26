import SwiftUI
import PhosphorSwift

struct SearchScreen: View {
    var body: some View {
        NavigationStack {
            SearchView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
                .aboveBottomBar()
                .swipeBackEnabled()
        }
    }
}

/// Find people by name or username. No hashtags, no explore.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [User] = []
    @State private var suggested: [User] = []
    @State private var requests: [User] = []
    @State private var relationships: [ID: Relationship] = [:]
    @State private var isSearching = false
    /// Requests just confirmed, showing their moment before the row leaves.
    @State private var confirmed: Set<ID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Search") { EmptyView() }
            SearchField(text: $query, placeholder: "Name or username")
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 6)
            List {
                if !requests.isEmpty && query.isEmpty {
                    Section {
                        ForEach(requests) { user in
                            HStack(spacing: 8) {
                                UserRow(user: user, subtitle: user.name)
                                if confirmed.contains(user.id) {
                                    HStack(spacing: 5) {
                                        Icon(Glyph.done, weight: .bold, size: 14)
                                        Text("Friends")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(height: 36)
                                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                                } else {
                                    Button("Confirm") { respond(user, accept: true) }
                                        .buttonStyle(.pill(.primary, size: .small))
                                    Button("Delete") { respond(user, accept: false) }
                                        .buttonStyle(.pill(.secondary, size: .small))
                                }
                            }
                            .background { NavigationLink(value: Route.profile(user.id)) { EmptyView() }.opacity(0) }
                            .listRowInsets(rowInsets)
                            .listRowSeparator(.hidden)
                            .transition(.asymmetric(insertion: .opacity,
                                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                        }
                    } header: {
                        header("Follow requests")
                    }
                }

                if query.isEmpty {
                    if !suggested.isEmpty {
                        Section {
                            ForEach(suggested) { user in row(user) }
                        } header: {
                            header("Suggested for you")
                        }
                    }
                    Section {
                        ShareLink(item: Invite.note, subject: Text(Invite.subject)) {
                            actionRow(Glyph.share, "Invite your group", "Sundae works when the whole group is here.")
                        }
                        .foregroundStyle(.primary)
                        .listRowInsets(rowInsets)
                        .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        if results.isEmpty && !isSearching {
                            Text("Nobody by that name yet.")
                                .foregroundStyle(.secondary)
                                .listRowInsets(rowInsets)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(results) { user in row(user) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 70)
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
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 8, leading: Theme.pagePadding, bottom: 8, trailing: Theme.pagePadding)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 12, leading: Theme.pagePadding, bottom: 4, trailing: Theme.pagePadding))
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
    }

    /// Row content with an invisible navigation link behind it, so there is no chevron.
    private func row(_ user: User) -> some View {
        HStack(spacing: 8) {
            UserRow(user: user)
            FollowButton(relationship: relationships[user.id] ?? .notFollowing) {
                Task { await toggleFollow(user) }
            }
        }
        .background { NavigationLink(value: Route.profile(user.id)) { EmptyView() }.opacity(0) }
        .listRowInsets(rowInsets)
        .listRowSeparator(.hidden)
    }

    private func loadInitial() async {
        requests = (try? await model.api.followRequests()) ?? []
        suggested = (try? await model.api.suggestedUsers()) ?? []
    }

    private func toggleFollow(_ user: User) async {
        let current = relationships[user.id] ?? .notFollowing
        do {
            if current == .notFollowing {
                relationships[user.id] = try await model.api.follow(userID: user.id)
                Haptics.light()
            } else {
                try await model.api.unfollow(userID: user.id)
                relationships[user.id] = .notFollowing
            }
        } catch {
            // The server decides; the row stays as it was.
        }
    }

    /// Confirm shows a brief "Friends" before the row slides away; Delete just slides away.
    private func respond(_ user: User, accept: Bool) {
        if accept {
            Haptics.success()
            withAnimation(reduceMotion ? nil : .bouncy(duration: 0.4)) { _ = confirmed.insert(user.id) }
        } else {
            Haptics.light()
        }
        Task {
            if accept, !reduceMotion {
                try? await Task.sleep(for: .milliseconds(700))
            }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { requests.removeAll { $0.id == user.id } }
            confirmed.remove(user.id)
            try? await model.api.respondToFollowRequest(from: user.id, accept: accept)
            await model.compose.refreshTaggable()
        }
    }
}

import SwiftUI

struct SearchScreen: View {
    var body: some View {
        NavigationStack {
            SearchView()
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
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
    @State private var contacts: ContactsMatcher?

    var body: some View {
        List {
            if !requests.isEmpty && query.isEmpty {
                Section {
                    ForEach(requests) { user in
                        HStack(spacing: 8) {
                            UserRow(user: user, subtitle: user.name)
                            Button("Confirm") { Task { await respond(user, accept: true) } }
                                .buttonStyle(.borderedProminent)
                                .fontWeight(.semibold)
                            Button("Delete") { Task { await respond(user, accept: false) } }
                                .buttonStyle(.bordered)
                                .tint(.gray)
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)
                        }
                        .background { NavigationLink(value: Route.profile(user.id)) { EmptyView() }.opacity(0) }
                        .listRowInsets(rowInsets)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    header("Follow requests")
                }
            }

            if query.isEmpty {
                contactsSection
                if !suggested.isEmpty {
                    Section {
                        ForEach(suggested) { user in row(user) }
                    } header: {
                        header("Suggested for you")
                    }
                }
                Section {
                    ShareLink(item: URL(string: "https://sundae.app/join")!,
                              subject: Text("Join me on Sundae"),
                              message: Text("Sundays only. Come post your week with us.")) {
                        HStack(spacing: 12) {
                            Image(systemName: Icon.share)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(Theme.surface, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Invite your group").font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("Sundae works when the whole group is here.").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .listRowInsets(rowInsets)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    if results.isEmpty && !isSearching {
                        Text("Nobody by that name yet.").foregroundStyle(.secondary)
                    }
                    ForEach(results) { user in row(user) }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 70)
        .searchable(text: $query, prompt: "Search")
        .navigationTitle("Search")
        .task {
            if contacts == nil { contacts = ContactsMatcher(api: model.api) }
            await loadInitial()
            if let contacts, contacts.isOptedIn, contacts.matches.isEmpty { await contacts.match() }
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

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 12, leading: Theme.pagePadding, bottom: 4, trailing: Theme.pagePadding))
    }

    @ViewBuilder
    private var contactsSection: some View {
        if let contacts {
            Section {
                if !contacts.matches.isEmpty {
                    ForEach(contacts.matches) { user in row(user) }
                } else if contacts.isMatching {
                    HStack { ProgressView(); Text("Checking your contacts").foregroundStyle(.secondary) }
                } else if contacts.isOptedIn {
                    Text("Nobody from your contacts is here yet.").foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Button {
                        Task { await contacts.match() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: Icon.personAdd)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(Theme.surface, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Find friends from your contacts").font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("Numbers are hashed on your phone, never stored.").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .disabled(!contacts.canUse)
                    .listRowInsets(rowInsets)
                    .listRowSeparator(.hidden)
                }
                if let message = contacts.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                header("From your contacts")
            }
        }
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 8, leading: Theme.pagePadding, bottom: 8, trailing: Theme.pagePadding)
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

    private func respond(_ user: User, accept: Bool) async {
        requests.removeAll { $0.id == user.id }
        try? await model.api.respondToFollowRequest(from: user.id, accept: accept)
        await model.compose.refreshTaggable()
    }
}

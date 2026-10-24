import SwiftUI

struct SearchScreen: View {
    var body: some View {
        NavigationStack {
            SearchView()
                .toolbar(.hidden, for: .navigationBar)
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
                                Button("Confirm") { Task { await respond(user, accept: true) } }
                                    .buttonStyle(.pill(.primary, size: .small))
                                Button("Delete") { Task { await respond(user, accept: false) } }
                                    .buttonStyle(.pill(.secondary, size: .small))
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

    @ViewBuilder
    private var contactsSection: some View {
        if let contacts {
            Section {
                if !contacts.matches.isEmpty {
                    ForEach(contacts.matches) { user in row(user) }
                } else if contacts.isMatching {
                    HStack { ProgressView(); Text("Checking your contacts").foregroundStyle(.secondary) }
                        .listRowInsets(rowInsets)
                        .listRowSeparator(.hidden)
                } else if contacts.isOptedIn {
                    Text("Nobody from your contacts is here yet.")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .listRowInsets(rowInsets)
                        .listRowSeparator(.hidden)
                } else {
                    Button {
                        Task { await contacts.match() }
                    } label: {
                        actionRow(Glyph.personAdd, "Find friends from your contacts", "Numbers are hashed on your phone, never stored.")
                    }
                    .buttonStyle(.plain)
                    .disabled(!contacts.canUse)
                    .listRowInsets(rowInsets)
                    .listRowSeparator(.hidden)
                }
                if let message = contacts.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
            } header: {
                header("From your contacts")
            }
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

    private func respond(_ user: User, accept: Bool) async {
        requests.removeAll { $0.id == user.id }
        try? await model.api.respondToFollowRequest(from: user.id, accept: accept)
        await model.compose.refreshTaggable()
    }
}

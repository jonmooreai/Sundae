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
                Section("Follow requests") {
                    ForEach(requests) { user in
                        HStack {
                            NavigationLink(value: Route.profile(user.id)) { UserRow(user: user) }
                            Button("Decline") { Task { await respond(user, accept: false) } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("Accept") { Task { await respond(user, accept: true) } }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if query.isEmpty {
                contactsSection
                if !suggested.isEmpty {
                    Section("People your friends follow") {
                        ForEach(suggested) { user in row(user) }
                    }
                }
                Section {
                    ShareLink(item: URL(string: "https://sundae.app/join")!,
                              subject: Text("Join me on Sundae"),
                              message: Text("Sundays only. Come post your week with us.")) {
                        Label("Invite your group", systemImage: Icon.share)
                    }
                } footer: {
                    Text("Sundae works when the whole group is here. Friend groups adopt together or not at all.")
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
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Name or username")
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

    @ViewBuilder
    private var contactsSection: some View {
        if let contacts {
            Section {
                if !contacts.matches.isEmpty {
                    ForEach(contacts.matches) { user in row(user) }
                } else if contacts.isMatching {
                    HStack { ProgressView(); Text("Checking your contacts").foregroundStyle(.secondary) }
                } else if contacts.isOptedIn {
                    Text("Nobody from your contacts is here yet. Invite them below.").foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await contacts.match() }
                    } label: {
                        Label("Find friends from your contacts", systemImage: Icon.personAdd)
                    }
                    .disabled(!contacts.canUse)
                }
                if let message = contacts.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("From your contacts")
            } footer: {
                if !contacts.isOptedIn {
                    Text("Phone numbers are hashed on your phone with a one-time key. Only the hashes are sent, matched in memory, and thrown away.")
                }
            }
        }
    }

    private func row(_ user: User) -> some View {
        HStack {
            NavigationLink(value: Route.profile(user.id)) { UserRow(user: user) }
            FollowButton(relationship: relationships[user.id] ?? .notFollowing) {
                Task { await toggleFollow(user) }
            }
        }
        .buttonStyle(.plain)
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

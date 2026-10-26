import SwiftUI

/// Everyone who follows you, each with a way to remove them. Open every day.
struct FollowersList: View {
    @Environment(AppModel.self) private var model
    /// Nil until they load, or when they couldn't.
    @State private var followers: [User]?
    @State private var loadFailed = false
    /// The person whose removal is waiting on a yes.
    @State private var confirming: User?
    @State private var removing: Set<ID> = []
    @State private var removeFailed = false

    var body: some View {
        SettingsScreen(title: "Followers") {
            if let followers {
                if followers.isEmpty {
                    note("Nobody follows you yet.")
                } else {
                    SettingsGroup(footer: "They aren't told. Photos they have already seen can't be taken back.") {
                        ForEach(followers) { user in
                            HStack(spacing: 10) {
                                UserRow(user: user, title: user.displayName, subtitle: user.handle)
                                Button("Remove") { confirming = user }
                                    .buttonStyle(.pill(.secondary, size: .small))
                                    .disabled(removing.contains(user.id))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                }
            } else if loadFailed {
                SettingsGroup(footer: "Couldn't load your followers. Check your connection.") {
                    SettingsActionRow(title: "Try again") { Task { await load() } }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
        }
        .task {
            if followers == nil { await load() }
        }
        .confirmationDialog(confirming.map { Self.removeTitle($0) } ?? "Remove follower?",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible,
                            presenting: confirming) { user in
            Button("Remove", role: .destructive) { Task { await remove(user) } }
        } message: { _ in
            Text("They stop seeing your weeks. If your account is private they would have to ask again.")
        }
        .alert("Couldn't remove them", isPresented: $removeFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("They still follow you. Try again when you're online.")
        }
    }

    /// "Remove Pat Doe?"
    nonisolated static func removeTitle(_ user: User) -> String {
        "Remove \(user.displayName)?"
    }

    private func load() async {
        loadFailed = false
        do {
            followers = try await model.api.followers()
        } catch {
            loadFailed = true
        }
    }

    /// Leaves the list only once the server has removed them.
    private func remove(_ user: User) async {
        guard !removing.contains(user.id) else { return }
        removing.insert(user.id)
        defer { removing.remove(user.id) }
        do {
            try await model.api.removeFollower(userID: user.id)
            withAnimation(.snappy(duration: 0.25)) { followers = followers?.filter { $0.id != user.id } }
            Haptics.light()
            await model.compose.refreshTaggable()
        } catch {
            removeFailed = true
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }
}

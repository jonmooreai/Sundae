import SwiftUI

/// The Profile tab: your own archive.
struct ProfileScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            if let id = model.currentUser?.id {
                ProfileView(userID: id)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        }
    }
}

/// Header, then a vertical list of weeks, newest first. Each week is a horizontal strip of
/// the user's own photos followed by approved tagged photos with a "from Maya" chip.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    let userID: ID

    @State private var profile: Profile?
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showEdit = false
    @State private var reporting = false

    private var isOwn: Bool { userID == model.currentUser?.id }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let profile {
                    ProfileHeader(profile: profile, onFollow: { Task { await toggleFollow() } }, onEdit: { showEdit = true })
                        .padding(.horizontal, Theme.pagePadding)
                    weekRows(for: profile)
                } else if let errorMessage {
                    ErrorBanner(message: errorMessage).padding(.horizontal, Theme.pagePadding)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(profile?.user.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isOwn {
                    Button { showSettings = true } label: { Image(systemName: Icon.settings) }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("profile-settings")
                } else if let profile {
                    Menu {
                        Button("Report", systemImage: Icon.flag) { reporting = true }
                        Button("Block \(profile.user.firstName)", systemImage: Icon.block, role: .destructive) {
                            Task {
                                try? await model.api.block(userID: userID)
                                await load()
                            }
                        }
                    } label: {
                        Image(systemName: Icon.more)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showEdit, onDismiss: { Task { await load() } }) {
            if let user = profile?.user { EditProfileSheet(user: user) }
        }
        .sheet(isPresented: $reporting) {
            ReportSheet(target: .profile, targetID: userID)
        }
        .task(id: userID) { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func weekRows(for profile: Profile) -> some View {
        let items = ProfileRowItem.build(from: profile.weeks, currentWeekStart: model.currentWeekStart)
        if profile.relationship == .notFollowing || profile.relationship == .requested, !profile.user.isPublic {
            ContentUnavailableView("Private account", systemImage: Icon.lock,
                                   description: Text(profile.relationship == .requested
                                                     ? "Your request is waiting on \(profile.user.firstName)."
                                                     : "Follow \(profile.user.firstName) to see their weeks."))
                .padding(.top, 20)
        } else if items.isEmpty {
            ContentUnavailableView("Nothing here yet", systemImage: Icon.calendar,
                                   description: Text(isOwn ? "Your weeks will stack up here." : "No weeks posted yet."))
                .padding(.top, 20)
        } else {
            ForEach(items) { item in
                switch item {
                case .week(let week):
                    WeekRow(week: week, isOwn: isOwn, isCurrent: week.weekStart == model.currentWeekStart,
                            onRemoveTagged: { tagged in
                                Task {
                                    try? await model.api.removeTaggedPhoto(tagID: tagged.tag.id)
                                    await load()
                                }
                            })
                case .gap(let count, let newest):
                    Text(count == 1 ? model.clock.rangeLabel(weekStart: newest) : "\(count) weeks without a post")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private func load() async {
        do {
            profile = try await model.api.profile(userID: userID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFollow() async {
        guard let current = profile?.relationship else { return }
        do {
            if current == .notFollowing {
                profile?.relationship = try await model.api.follow(userID: userID)
                Haptics.light()
            } else {
                try await model.api.unfollow(userID: userID)
                profile?.relationship = .notFollowing
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Weeks interleaved with collapsed gaps. Consecutive empty weeks collapse into one line.
enum ProfileRowItem: Identifiable {
    case week(ProfileWeek)
    case gap(count: Int, newest: Date)

    var id: Date {
        switch self {
        case .week(let w): w.weekStart
        case .gap(_, let newest): newest
        }
    }

    static func build(from weeks: [ProfileWeek], currentWeekStart: Date) -> [ProfileRowItem] {
        var items: [ProfileRowItem] = []
        var pendingGap: (count: Int, newest: Date)?
        for week in weeks {
            let isCurrent = week.weekStart == currentWeekStart
            if week.isEmpty && !isCurrent {
                if let gap = pendingGap {
                    pendingGap = (gap.count + 1, gap.newest)
                } else {
                    pendingGap = (1, week.weekStart)
                }
            } else {
                if let gap = pendingGap {
                    items.append(.gap(count: gap.count, newest: gap.newest))
                    pendingGap = nil
                }
                items.append(.week(week))
            }
        }
        if let gap = pendingGap { items.append(.gap(count: gap.count, newest: gap.newest)) }
        return items
    }
}

struct ProfileHeader: View {
    let profile: Profile
    let onFollow: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 24) {
                AvatarView(user: profile.user, size: 86)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.user.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if let followers = profile.followerCount, let following = profile.followingCount {
                        // Visible only to the owner. Never shown publicly.
                        HStack(spacing: 18) {
                            stat(followers, "followers")
                            stat(following, "following")
                        }
                    } else {
                        Text("Sundays only")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if !profile.user.bio.isEmpty {
                Text(profile.user.bio)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            if profile.relationship == .me {
                Button(action: onEdit) {
                    Text("Edit profile").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else if profile.relationship == .notFollowing {
                Button(action: onFollow) {
                    Text("Follow").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: onFollow) {
                    Text(profile.relationship == .requested ? "Requested" : "Following").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func stat(_ count: Int, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.subheadline.weight(.semibold))
            Text(label).font(.subheadline)
        }
        .lineLimit(1)
    }
}

struct EditProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let user: User
    @State private var name = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Bio", text: $bio, axis: .vertical).lineLimit(2...4)
                if let error { Text(error).foregroundStyle(.secondary) }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await model.updateProfile(name: name, username: username.lowercased(), bio: bio)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = user.name
                username = user.username
                bio = user.bio
            }
        }
    }
}

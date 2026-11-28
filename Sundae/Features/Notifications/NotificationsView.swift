import SwiftUI

struct NotificationsScreen: View {
    /// Taps on the tab while it shows: back to this screen, then to its top.
    var reselects = 0
    @State private var path: [Route] = []
    @State private var scrollSignal = 0

    var body: some View {
        NavigationStack(path: $path) {
            NotificationsView()
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

/// The heart: people asking to follow you and photos you were tagged in, waiting on you, then the
/// log of everything that happened around you, all the way back, by day and then by month. What
/// you haven't seen yet wears a soft sage wash and a small dot until you next come back. Saying
/// yes to a request lets them follow you and never follows them back; Follow back is its own
/// button, there for you to choose.
struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tag requests showing their "added to your week" moment before they leave.
    @State private var approved: Set<ID> = []
    /// Follow requests said yes to here, staying on with a Follow back button.
    @State private var accepted: [ListedPerson] = []
    /// How you stand with people since you followed them from here.
    @State private var changed: [ID: Relationship] = [:]
    @State private var working: Set<ID> = []
    /// What was already seen when the screen opened, so the new stays marked new while you look.
    @State private var seenAtOpen: Date?
    @State private var opened = false
    @State private var isShowing = false

    private var store: NotificationsStore { model.notifications }

    /// Unread is judged against what was seen when the screen opened, so it stays marked while
    /// you look, and anything arriving while you are here is marked too.
    private func isUnread(_ item: ActivityItem) -> Bool {
        item.at > NotificationsStore.unreadAfter(seenThrough: seenAtOpen, activity: store.activity)
    }

    private var isEmpty: Bool { store.isEmpty && accepted.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(title: "Notifications") { EmptyView() }
                        .id(ScrollTop.id)
                    if let message = store.errorMessage {
                        ErrorBanner(message: message)
                            .padding(.horizontal, Theme.pagePadding)
                            .padding(.bottom, 12)
                    }
                    followRequests
                    tagRequests
                    activityLog
                }
                if isEmpty {
                    if store.hasLoaded {
                        EmptyState("All caught up", glyph: Glyph.notifications,
                                   message: "Likes, comments, tags and new followers show up here and stay, along with anything waiting on you.")
                    } else if store.errorMessage == nil {
                        LoadingState()
                    }
                }
            }
            .padding(.bottom, 24)
            .centeredColumn()
            .fillsVisibleHeight(isEmpty)
        }
        .scrollsToTopOnTabTap()
        .background(Theme.background)
        .sideBarChrome()
        .task {
            isShowing = true
            if !opened {
                opened = true
                seenAtOpen = store.seenThrough
            }
            await store.load()
            store.markSeen()
        }
        .refreshable {
            seenAtOpen = store.seenThrough
            accepted = []
            await store.load(fresh: true)
            store.markSeen()
        }
        .onChange(of: store.activity.first?.id) { _, _ in
            // Something arrived while you are looking: it's seen, and stays marked until you leave.
            if isShowing { store.markSeen() }
        }
        .onDisappear {
            // Next time, what was new now is read.
            opened = false
            isShowing = false
        }
    }

    // MARK: - Follow requests

    @ViewBuilder
    private var followRequests: some View {
        let waiting = store.followRequests
        if !waiting.isEmpty || !accepted.isEmpty {
            sectionHeader("Follow requests")
            ForEach(accepted) { person in
                acceptedRow(person)
                    .id("accepted-\(person.id)")
            }
            ForEach(waiting.filter { person in !accepted.contains { $0.id == person.id } }) { person in
                requestRow(person)
                    .transition(.opacity)
            }
        }
    }

    private func requestRow(_ person: ListedPerson) -> some View {
        HStack(spacing: 8) {
            NavigationLink(value: Route.profile(person.id)) {
                // The name and the username together: a name can be copied, a username can't.
                UserRow(user: person.user, title: person.user.displayName, subtitle: person.user.handle)
            }
            .buttonStyle(.plain)
            Button("Confirm") { respond(to: person, accept: true) }
                .buttonStyle(.pill(.primary, size: .small))
                .disabled(working.contains(person.id))
            Button("Delete") { respond(to: person, accept: false) }
                .buttonStyle(.pill(.secondary, size: .small))
                .disabled(working.contains(person.id))
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 8)
    }

    /// Said yes to: they follow you now. Following them is up to you.
    private func acceptedRow(_ person: ListedPerson) -> some View {
        let relationship = changed[person.id] ?? person.relationship
        return HStack(spacing: 8) {
            NavigationLink(value: Route.profile(person.id)) {
                UserRow(user: person.user, title: person.user.displayName, subtitle: "Follows you now")
            }
            .buttonStyle(.plain)
            FollowButton(relationship: relationship, followsYou: true) { tapFollow(person.user, relationship) }
                .disabled(working.contains(person.id))
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 8)
        .transition(.opacity)
    }

    private func respond(to person: ListedPerson, accept: Bool) {
        guard working.insert(person.id).inserted else { return }
        if accept { Haptics.success() } else { Haptics.light() }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
            store.dismiss(person)
            if accept { accepted.append(person) }
        }
        Task {
            defer { working.remove(person.id) }
            let done = await store.respond(to: person, accept: accept)
            if !done { withAnimation { accepted.removeAll { $0.id == person.id } } }
            if done, accept { noteFollowsChanged() }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagRequests: some View {
        if !store.tagRequests.isEmpty {
            sectionHeader("Tagged you")
            VStack(spacing: 28) {
                ForEach(store.tagRequests) { request in
                    TagRequestCard(request: request, isApproved: approved.contains(request.id)) { approve in
                        respond(to: request, approve: approve)
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.94).combined(with: .opacity)))
                }
            }
            .padding(.bottom, 12)
        }
    }

    /// Approve stamps the photo and shows the chip it will wear on your week, then the card
    /// folds away and the week it came from is in your feed. Decline just folds away.
    private func respond(to request: TagRequest, approve: Bool) {
        if approve {
            Haptics.success()
            withAnimation(reduceMotion ? nil : .bouncy(duration: 0.5)) { _ = approved.insert(request.id) }
        } else {
            Haptics.light()
        }
        Task {
            if approve, !reduceMotion {
                try? await Task.sleep(for: .milliseconds(1100))
            }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.4)) { store.dismiss(request) }
            approved.remove(request.id)
            await store.submit(request, approve: approve)
            // The week it is from is in the feed now, and your profile shows the photo.
            if approve {
                await model.feed.load(refresh: true)
                model.followsChanged += 1
            }
        }
    }

    // MARK: - Activity

    @ViewBuilder
    private var activityLog: some View {
        let sections = ActivityLog.sections(store.activity, now: model.clock.now(), calendar: model.clock.calendar)
        ForEach(sections) { section in
            sectionHeader(section.title)
            ForEach(section.items) { item in
                ActivityRow(item: item, relationship: changed[item.actor.id] ?? item.relationship,
                            isUnread: isUnread(item), isWorking: working.contains(item.actor.id)) {
                    tapFollow(item.actor, changed[item.actor.id] ?? item.relationship)
                }
            }
        }
        if !store.activity.isEmpty {
            if store.hasMoreActivity {
                // Comes on screen near the end of what is loaded, and asks for the page before it.
                Group {
                    if store.isLoadingMore { ProgressView() } else { Color.clear }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .task(id: store.activity.count) { await store.loadMoreActivity() }
            } else {
                Text("That's everything, all the way back.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Following

    /// Follow and Follow back follow; a request is taken back; Following unfollows.
    private func tapFollow(_ user: User, _ relationship: Relationship) {
        guard working.insert(user.id).inserted else { return }
        Task {
            defer { working.remove(user.id) }
            do {
                switch relationship {
                case .notFollowing:
                    changed[user.id] = try await model.api.follow(userID: user.id)
                    Haptics.light()
                case .following, .requested:
                    try await model.api.unfollow(userID: user.id)
                    changed[user.id] = .notFollowing
                case .me, .blocked:
                    return
                }
                noteFollowsChanged()
            } catch {
                store.errorMessage = "We couldn't reach Sundae. Nothing changed; give it another try once you're online."
            }
        }
    }

    /// Your profile shows the new counts, and tagging knows who is a friend now.
    private func noteFollowsChanged() {
        model.followsChanged += 1
        Task { await model.compose.refreshTaggable() }
    }
}

/// One thing that happened: who, what, when, and what it was on. The whole row opens the week it
/// was about, or the person for a follow; a new follower you don't follow yet gets Follow back.
struct ActivityRow: View {
    @Environment(AppModel.self) private var model
    let item: ActivityItem
    let relationship: Relationship
    /// Not seen yet: a soft sage wash behind the row and a small dot at its edge.
    var isUnread = false
    var isWorking = false
    let onFollow: () -> Void

    private var destination: Route {
        if let dump = item.dumpID { return .dump(dump) }
        return .profile(item.actor.id)
    }

    /// A new follower gets Follow back until you follow them; nobody else gets a button.
    private var showsFollow: Bool {
        (item.kind == .follow || item.kind == .followRequest) && relationship != .me && relationship != .blocked
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: destination) {
                HStack(spacing: 12) {
                    AvatarView(user: item.actor, size: 44)
                    sentence
                        .font(.subheadline)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !showsFollow, let photo = item.photo {
                        PhotoView(source: photo)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isUnread ? Text("New") : Text(""))
            if showsFollow {
                FollowButton(relationship: relationship, followsYou: true, action: onFollow)
                    .disabled(isWorking)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 8)
        .background {
            if isUnread { Color.accentColor.opacity(0.08) }
        }
        .overlay(alignment: .leading) {
            if isUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .padding(.leading, 5)
                    .accessibilityHidden(true)
            }
        }
    }

    private var sentence: Text {
        let name = Text(item.actor.username).fontWeight(.semibold)
        let when = Text(Self.when(item.at, now: model.clock.now(), calendar: model.clock.calendar)).foregroundStyle(.secondary)
        let phrase = Self.phrase(for: item)
        let line: LocalizedStringKey = "\(name) \(phrase) \(when)"
        return Text(line)
    }

    /// "3h" for the last week; a date further back, where the log goes by month: "Oct 12".
    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        guard now.timeIntervalSince(date) >= 7 * 86_400 else { return relativeTime(date, now: now) }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        return date.formatted(sameYear ? style : style.year())
    }

    /// What they did, after their name: "liked your week."
    static func phrase(for item: ActivityItem) -> String {
        let said = item.commentBody.map { "\u{201C}\($0)\u{201D}" } ?? ""
        switch item.kind {
        case .like: return "liked your week."
        case .comment: return "commented: \(said)"
        case .reply: return "replied: \(said)"
        case .mention: return "mentioned you: \(said)"
        case .commentLike: return "liked your comment: \(said)"
        case .tag: return "tagged you in a photo."
        case .follow: return "started following you."
        case .followRequest: return "asked to follow you, and you said yes."
        case .followAccepted: return "said yes. You're following them now."
        case .tagApproved: return "said yes to your tag. It's on their week now."
        }
    }
}

/// The log by when it happened: today, yesterday, the rest of the last week, then each month,
/// with the year once it isn't this one.
enum ActivityLog {
    struct Section: Identifiable, Equatable {
        let title: String
        var items: [ActivityItem]
        var id: String { title }
    }

    /// Items newest first, as the server sends them, in sections in the same order.
    static func sections(_ items: [ActivityItem], now: Date, calendar: Calendar) -> [Section] {
        var out: [Section] = []
        for item in items {
            let title = title(for: item.at, now: now, calendar: calendar)
            if out.last?.title == title { out[out.count - 1].items.append(item) } else { out.append(Section(title: title, items: [item])) }
        }
        return out
    }

    static func title(for date: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        if date >= today { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), date >= yesterday { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: today), date >= weekAgo { return "This week" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: calendar.timeZone).month(.wide)
        return date.formatted(sameYear ? style : style.year())
    }
}

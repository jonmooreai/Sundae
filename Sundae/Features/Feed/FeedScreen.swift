import SwiftUI

/// Sunday opens here. Compact width is a plain stack; regular width (iPad, Duo unfolded) is
/// two columns with the feed on the left and the open dump or profile on the right.
struct FeedScreen: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path: [Route] = []
    @State private var selection: Route?
    let onPost: () -> Void

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                FeedList(open: { selection = $0 }, onPost: onPost)
                    .navigationTitle("Sunday")
                    .navigationSplitViewColumnWidth(min: 380, ideal: 460, max: 560)
            } detail: {
                if let selection {
                    RouteStack(root: selection).id(selection)
                } else {
                    ContentUnavailableView("Pick a dump", systemImage: Icon.photos, description: Text("Tap a photo or a name on the left."))
                }
            }
        } else {
            NavigationStack(path: $path) {
                FeedList(open: { path.append($0) }, onPost: onPost)
                    .navigationTitle("Sunday")
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        }
    }
}

struct FeedList: View {
    @Environment(AppModel.self) private var model
    let open: (Route) -> Void
    let onPost: () -> Void

    private var feed: FeedStore { model.feed }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                PostYourWeekCard(onPost: onPost)
                    .padding(.horizontal, Theme.pagePadding)

                if let message = feed.errorMessage {
                    ErrorBanner(message: message).padding(.horizontal, Theme.pagePadding)
                }

                ForEach(feed.dumps) { dump in
                    DumpCard(
                        dump: dump,
                        open: open,
                        onLike: { Task { await feed.toggleLike(dump, me: model.currentUser) } }
                    )
                    .task { await feed.loadMoreIfNeeded(current: dump) }
                }

                if feed.isLoading {
                    ProgressView().padding()
                } else if feed.hasLoaded && feed.dumps.isEmpty {
                    ContentUnavailableView(
                        "Quiet Sunday",
                        systemImage: Icon.sun,
                        description: Text("Nobody you follow has posted yet. Post your week, or find your friends in Search.")
                    )
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .refreshable {
            await feed.load(refresh: true)
            await model.compose.load(weekStart: model.currentWeekStart)
        }
        .task {
            await feed.load(refresh: false)
            await model.compose.load(weekStart: model.currentWeekStart)
        }
    }
}

/// Pinned at the top until you post. Afterwards it turns into a quiet "your week is up" card.
struct PostYourWeekCard: View {
    @Environment(AppModel.self) private var model
    let onPost: () -> Void

    var body: some View {
        let compose = model.compose
        HStack(spacing: 14) {
            if let user = model.currentUser { AvatarView(user: user, size: 44) }
            VStack(alignment: .leading, spacing: 3) {
                Text(compose.hasPosted ? "Your week is up" : "Post your week")
                    .font(.headline)
                Text(compose.hasPosted
                     ? "Edit any time until midnight."
                     : model.clock.rangeLabel(weekStart: model.currentWeekStart))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if compose.hasPosted {
                Button("Edit", action: onPost).buttonStyle(.bordered)
            } else {
                Button("Post", action: onPost).buttonStyle(.borderedProminent)
            }
        }
        .card()
    }
}

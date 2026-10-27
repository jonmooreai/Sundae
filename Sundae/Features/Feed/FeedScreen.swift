import SwiftUI

/// Sunday's home. Compact width is a plain stack; regular width (iPad) is two columns with the
/// feed on the left and the open dump or profile on the right.
struct FeedScreen: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path: [Route] = []
    @State private var selection: Route?
    @State private var scrollSignal = 0
    let onPost: () -> Void
    /// Counts taps on Feed while it is showing: back to the feed itself, then to its top.
    var reselects = 0

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                FeedList(open: { selection = $0 }, onPost: onPost)
                    .environment(\.scrollToTop, scrollSignal)
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationSplitViewColumnWidth(min: 380, ideal: 460, max: 560)
            } detail: {
                if let selection {
                    // A tap on Feed brings the open post back from anything opened from it.
                    RouteStack(root: selection, reselects: reselects).id(selection)
                } else {
                    ContentUnavailableView("Pick a post", systemImage: "photo.on.rectangle", description: Text("Tap a photo or a name on the left."))
                }
            }
            .onChange(of: reselects) { _, _ in scrollSignal += 1 }
        } else {
            NavigationStack(path: $path) {
                FeedList(open: { path.append($0) }, onPost: onPost)
                    .environment(\.scrollToTop, scrollSignal)
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
                    .aboveBottomBar()
                    .swipeBackEnabled()
            }
            // From a post, or anything opened from one, straight back to the feed where it was;
            // already there, up to the top.
            .onChange(of: reselects) { _, _ in
                if path.isEmpty { scrollSignal += 1 } else { path.removeAll() }
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
            VStack(spacing: 0) {
                LazyVStack(spacing: 0) {
                    ScrollTop()
                    ScreenHeader(title: "Sunday", subtitle: model.clock.rangeLabel(weekStart: model.currentWeekStart)) { EmptyView() }
                    .accessibilityElement(children: .contain)

                    PostYourWeekRow(onPost: onPost)
                    FeedMoments(open: open)

                    if let message = feed.errorMessage {
                        ErrorBanner(message: message).padding(Theme.pagePadding)
                    }

                    ForEach(feed.dumps) { dump in
                        DumpCard(
                            dump: dump,
                            open: open,
                            onLike: { Task { await feed.toggleLike(dump, me: model.currentUser) } }
                        )
                        .padding(.top, 18)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                        .task { await feed.loadMoreIfNeeded(current: dump) }
                    }

                    if feed.isLoading && !feed.dumps.isEmpty {
                        ProgressView().padding(32)
                    }
                }
                if feed.dumps.isEmpty {
                    if feed.isLoading {
                        LoadingState()
                    } else if feed.hasLoaded {
                        EmptyState("Quiet Sunday", glyph: Glyph.sun,
                                   message: "Nobody you follow has posted yet. Post your week, or find your friends in Search.")
                    }
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            // Nothing posted yet: the spinner or the quiet Sunday sits in the middle of the space left.
            .fillsVisibleHeight(feed.dumps.isEmpty)
            .animation(.easeOut(duration: 0.3), value: feed.dumps.count)
        }
        .scrollsToTopOnTabTap()
        .background(Theme.background)
        .goldenHour(calendar: model.clock.calendar)
        .birthdayPaper(calendar: model.clock.calendar)
        .halloweenNight(date: model.clock.now(), calendar: model.clock.calendar)
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

/// A flat row at the top of the feed until you post; afterwards a quiet "your week is up".
struct PostYourWeekRow: View {
    @Environment(AppModel.self) private var model
    let onPost: () -> Void

    var body: some View {
        let compose = model.compose
        HStack(spacing: 12) {
            if let user = model.currentUser {
                AvatarView(user: user, size: 44)
                    .overlay {
                        if !compose.hasPosted {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(compose.hasPosted ? "Your week is up" : "Post your week")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(compose.hasPosted ? "Edit any time until midnight." : "\(compose.draft.photos.isEmpty ? "Pick the photos" : "Finish your draft") from this week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(compose.hasPosted ? "Edit" : "Post", action: onPost)
                .buttonStyle(.pill(compose.hasPosted ? .secondary : .primary, size: .small))
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Hairline().padding(.horizontal, Theme.pagePadding)
        }
    }
}

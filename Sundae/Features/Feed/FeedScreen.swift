import SwiftUI

/// Sunday's home. A plain stack on a phone; two columns, the feed on the left and the open post
/// or profile on the right, on an iPad (SundayShell decides). An iPhone Duo open gets the stack,
/// centered.
struct FeedScreen: View {
    @Environment(\.splitLayout) private var splitLayout
    @State private var path: [Route] = []
    @State private var selection: Route?
    @State private var scrollSignal = 0
    let onPost: () -> Void
    /// Counts taps on Feed while it is showing: back to the feed itself, then to its top.
    var reselects = 0

    var body: some View {
        if splitLayout {
            NavigationSplitView {
                FeedList(open: { selection = $0 }, onPost: onPost)
                    .environment(\.scrollToTop, scrollSignal)
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
    private var weekStart: Date { model.currentWeekStart }
    /// Pulled far enough past the end of this week that letting go loads earlier weeks.
    @State private var releaseToLoad = false
    @State private var scrollPhase: ScrollPhase = .idle
    private static let pullDistance: CGFloat = 70
    private var thisWeek: [Dump] { feed.thisWeek(weekStart) }

    private func card(_ dump: Dump) -> some View {
        DumpCard(
            dump: dump,
            open: open,
            onLike: { Task { await feed.toggleLike(dump, me: model.currentUser) } }
        )
        .padding(.top, 18)
        .padding(.bottom, 10)
        .transition(.opacity)
        .task { await feed.loadMoreIfNeeded(current: dump, weekStart: weekStart) }
    }

    private var canPullForEarlier: Bool {
        feed.hasLoaded && !feed.showsEarlier && feed.mayHaveEarlier(weekStart)
    }

    /// At the bottom of this week: earlier weeks, only for whoever wants them.
    @ViewBuilder
    private var earlierButton: some View {
        if feed.hasLoaded, !feed.showsEarlier, feed.mayHaveEarlier(weekStart) {
            VStack(spacing: 12) {
                if !thisWeek.isEmpty {
                    Text("That's everyone's week so far.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await feed.showEarlier(weekStart: weekStart) }
                } label: {
                    Text(releaseToLoad ? "Release to load\u{2026}" : "Show earlier weeks")
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: releaseToLoad)
                }
                .buttonStyle(.pill(releaseToLoad ? .primary : .secondary, size: .small))
                .accessibilityIdentifier("show-earlier-weeks")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, thisWeek.isEmpty ? 0 : 28)
            .padding(.bottom, 12)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVStack(spacing: 0) {
                    ScrollTop()
                    ScreenHeader(title: "Sundae", subtitle: model.clock.rangeLabel(weekStart: model.currentWeekStart)) { EmptyView() }
                    .accessibilityElement(children: .contain)

                    PostYourWeekRow(onPost: onPost)
                    FeedMoments(open: open)

                    if let message = feed.errorMessage {
                        ErrorBanner(message: message).padding(Theme.pagePadding)
                    }

                    ForEach(thisWeek) { dump in card(dump) }

                    if feed.showsEarlier {
                        ForEach(feed.earlierWeeks(weekStart), id: \.weekStart) { week in
                            WeekDivider(label: model.clock.rangeLabel(weekStart: week.weekStart))
                            ForEach(week.dumps) { dump in card(dump) }
                        }
                    }

                    if feed.isLoading && !feed.dumps.isEmpty {
                        ProgressView().padding(32)
                    }
                }
                if thisWeek.isEmpty {
                    if feed.isLoading && !feed.hasLoaded {
                        LoadingState()
                    } else if feed.hasLoaded {
                        EmptyState("Quiet Sundae", glyph: Glyph.sun,
                                   message: "Nobody you follow has posted this week yet. Post yours, or find your friends in Search.")
                    }
                }
                earlierButton
            }
            .padding(.bottom, 24)
            .centeredColumn(Theme.postWidth)
            // Nothing posted yet: the spinner or the quiet Sunday sits in the middle of the space left.
            .fillsVisibleHeight(thisWeek.isEmpty && !feed.showsEarlier)
            .animation(.easeOut(duration: 0.3), value: feed.dumps.count)
        }
        .scrollsToTopOnTabTap()
        .sideBarChrome()
        // Pulled up past the end of this week: the button says to let go, and letting go loads
        // the weeks before, as a pull down refreshes.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let restingEnd = max(geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height,
                                 -geometry.contentInsets.top)
            return geometry.contentOffset.y - restingEnd
        } action: { _, pulled in
            guard scrollPhase == .interacting, canPullForEarlier else {
                if releaseToLoad, scrollPhase != .interacting { return }
                releaseToLoad = false
                return
            }
            let armed = pulled > Self.pullDistance
            if armed != releaseToLoad {
                releaseToLoad = armed
                if armed { Haptics.light() }
            }
        }
        .onScrollPhaseChange { _, phase in
            scrollPhase = phase
            guard phase != .interacting, releaseToLoad else { return }
            releaseToLoad = false
            if canPullForEarlier { Task { await feed.showEarlier(weekStart: weekStart) } }
        }
        .background(Theme.background)
        .goldenHour(calendar: model.clock.calendar)
        .birthdayPaper(calendar: model.clock.calendar)
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

/// A flat row at the top of the feed until you post; afterwards a quiet thank you.
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
                // Wraps to a second line on a narrow screen (the Duo closed) rather than trailing off.
                Text(compose.hasPosted ? "Thanks for sharing your week" : "Come share your week")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !compose.hasPosted {
                    Text("\(compose.draft.photos.isEmpty ? "Pick your favorites" : "Finish your draft") from this week.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(compose.hasPosted ? "Edit" : "Post", action: onPost)
                .buttonStyle(.pill(compose.hasPosted ? .secondary : .primary, size: .small))
                .fixedSize()
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Hairline().padding(.horizontal, Theme.pagePadding)
        }
    }
}

/// Where an earlier week starts in the feed: its dates, between two hairlines.
struct WeekDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Hairline()
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            Hairline()
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 28)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

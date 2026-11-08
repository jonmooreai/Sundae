import SwiftUI

/// Decides between onboarding, the weekday screen and the Sunday shell.
/// The decision comes from `AppModel.phase`, which flips itself at midnight.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isRestoringSession {
                ProgressView()
            } else if !model.isSignedIn || model.isFinishingOnboarding {
                OnboardingView()
            } else if model.isSunday {
                SundayShell()
            } else {
                WeekdayView()
            }
        }
        .animation(.default, value: model.isSunday)
        .animation(.default, value: model.isSignedIn)
        .animation(.default, value: model.isFinishingOnboarding)
    }
}

enum SundayTab: Hashable, CaseIterable {
    case feed, search, post, notifications, profile
}

/// Familiar skeleton with our own bottom bar: Feed, Search, Post, Notifications, Profile.
/// The system TabView does the paging (so every tab keeps its scroll position and navigation)
/// with its own bar hidden; the bar you see is `SundaeTabBar`.
///
/// Where the system lays its bars out down the side of the screen instead (an iPhone Duo closed,
/// or open on its side), the system's own tab bar shows instead of ours: the Duo moves it into the
/// strip it keeps for the clock and the camera, and the pages get the whole screen beside it.
struct SundayShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab: SundayTab = .feed
    /// True while the system's bars run down the side of the screen (iOS 27.1 and an iPhone Duo).
    @State private var sideBars = false
    @State private var barHeight: CGFloat = 50
    /// The shell's width: two columns need room for two, which regular width alone does not promise.
    @State private var width: CGFloat = 0
    /// A pinched photo, drawn over everything including the bar.
    @State private var zoom = PhotoZoom()
    /// Taps on a tab that is already showing, by tab: back to its first screen, then to the top.
    @State private var reselects: [SundayTab: Int] = [:]

    private var compose: ComposeStore { model.compose }

    /// The tab the system bar asks for. Post is a button, not a page: it opens the posting flow
    /// and the page you were on stays. The tab already showing, tapped again, goes back to its
    /// first screen, then to the top, as in our own bar.
    private var systemSelection: Binding<SundayTab> {
        Binding(get: { tab }, set: { next in
            if next == .post {
                Haptics.light()
                openCompose()
            } else if next == tab {
                reselects[next, default: 0] += 1
            } else {
                tab = next
            }
        })
    }

    private var pageInset: CGFloat { sideBars ? 0 : barHeight }

    var body: some View {
        TabView(selection: systemSelection) {
            Tab(value: SundayTab.feed) {
                FeedScreen(onPost: openCompose, reselects: reselects[.feed, default: 0]).tabPage(barHeight: pageInset, systemBar: sideBars)
            } label: { Label { Text("Feed") } icon: { TabIcon.image(Glyph.feed) } }
            Tab(value: SundayTab.search) {
                SearchScreen(reselects: reselects[.search, default: 0]).tabPage(barHeight: pageInset, systemBar: sideBars)
            } label: { Label { Text("Search") } icon: { TabIcon.image(Glyph.search) } }
            // Never shown: choosing it opens the posting flow (systemSelection).
            Tab(value: SundayTab.post) {
                Color.clear.tabPage(barHeight: pageInset, systemBar: sideBars)
            } label: { Label { Text("Share your week") } icon: { TabIcon.image(Glyph.post) } }
            Tab(value: SundayTab.notifications) {
                NotificationsScreen(reselects: reselects[.notifications, default: 0]).tabPage(barHeight: pageInset, systemBar: sideBars)
            } label: { Label { Text("Notifications") } icon: { TabIcon.image(Glyph.notifications) } }
            .badge(model.notificationBadge)
            Tab(value: SundayTab.profile) {
                ProfileScreen(reselects: reselects[.profile, default: 0]).tabPage(barHeight: pageInset, systemBar: sideBars)
            } label: { Label { Text("Profile") } icon: { TabIcon.image(Glyph.profile) } }
        }
        // The bar is an overlay and every page reserves its height. A safe area inset on the
        // TabView itself never reached the pages, so a screen's bottom composer sat under the bar.
        .overlay(alignment: .bottom) {
            if !sideBars {
                SundaeTabBar(selected: $tab, badge: model.notificationBadge, user: model.currentUser, onPost: openCompose,
                             onReselect: { reselects[$0, default: 0] += 1 })
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                    // Stays at the bottom when the keyboard comes up, hidden behind it, instead of riding on top.
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .background {
            if #available(iOS 27.1, *) {
                SideBarsReader { sideBars = $0 }
            }
        }
        .overlay(alignment: .top) {
            Theme.background.opacity(0.94)
                .frame(height: 0)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .overlay { PhotoZoomLayer() }
        .environment(zoom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(\.splitLayout, UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular && width >= 820)
        .filmGrain()
        .onChange(of: model.requestedTab) { _, requested in
            guard let requested else { return }
            tab = requested
            model.requestedTab = nil
        }
        .fullScreenCover(isPresented: Binding(get: { compose.isPresented }, set: { if !$0 { compose.dismiss() } })) {
            ComposeFlow()
                .environment(model)
        }
        .task {
            // Sunday opens on the prompt until you have posted, so you can start right away.
            await compose.load(weekStart: model.currentWeekStart)
            presentPromptIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the background counts as opening the app, and may be a new week:
            // the app can be kept in memory from one Sunday to the next. Before the first load
            // finishes the task above handles it.
            guard phase == .active, let loaded = compose.loadedWeekStart else { return }
            if loaded == model.currentWeekStart {
                presentPromptIfNeeded()
            } else {
                Task {
                    await compose.load(weekStart: model.currentWeekStart)
                    presentPromptIfNeeded()
                }
            }
        }
    }

    private func presentPromptIfNeeded() {
        guard !compose.isPresented, compose.shouldShowPrompt(weekStart: model.currentWeekStart) else { return }
        compose.present(.prompt)
    }

    /// Opens on the post when this week has one, on the grid when not: this week's answer, so a
    /// week loaded earlier is replaced first.
    private func openCompose() {
        guard compose.loadedWeekStart != model.currentWeekStart else {
            compose.present(compose.hasPosted ? .arrange : .pick)
            return
        }
        Task {
            await compose.load(weekStart: model.currentWeekStart)
            compose.present(compose.hasPosted ? .arrange : .pick)
        }
    }
}

/// Two columns, feed beside the open post: an iPad only. An iPhone Duo open is regular width too,
/// but there the feed reads as one centered column, like a phone with room on either side.
private struct SplitLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var splitLayout: Bool {
        get { self[SplitLayoutKey.self] }
        set { self[SplitLayoutKey.self] = newValue }
    }
}

/// Height of our bottom bar, handed to every screen under it. Safe area insets set on the
/// TabView or on a stack never reach pushed screens, so each screen reserves the room itself.
private struct BottomBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var bottomBarInset: CGFloat {
        get { self[BottomBarInsetKey.self] }
        set { self[BottomBarInsetKey.self] = newValue }
    }
}

private struct BottomBarInset: ViewModifier {
    @Environment(\.bottomBarInset) private var inset
    @State private var keyboardShown = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: keyboardShown ? 0 : inset) }
            // The keyboard covers the bar, so a composer should sit on the keyboard, not 50 pt above it.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.easeOut(duration: 0.25)) { keyboardShown = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.25)) { keyboardShown = false }
            }
    }
}

extension View {
    /// Keeps this screen's bottom edge, composers included, above the tab bar.
    func aboveBottomBar() -> some View { modifier(BottomBarInset()) }
}

private extension View {
    /// A tab page under our own bar: the system bar hidden, our height in the environment. Where
    /// the system's bars run down the side, the system bar shows and the page needs no room for ours.
    func tabPage(barHeight: CGFloat, systemBar: Bool) -> some View {
        toolbar(systemBar ? .automatic : .hidden, for: .tabBar)
            .environment(\.bottomBarInset, barHeight)
    }
}

/// Says whether the system lays its bars out down the side of the screen: an iPhone Duo closed,
/// with the clock and the camera in a strip down one edge, or open on its side.
@available(iOS 27.1, *)
private struct SideBarsReader: View {
    @Environment(\.toolbarVerticalEdge) private var edge
    let report: (Bool) -> Void

    var body: some View {
        Color.clear
            .onAppear { report(edge != nil) }
            .onChange(of: edge) { _, now in report(now != nil) }
    }
}

/// Our Phosphor icons at the size a system tab bar draws them. The artwork is 256 points square,
/// which the bar would show at full size, so each is drawn once at 26 points and kept.
@MainActor
enum TabIcon {
    private static var drawn: [Ph: UIImage] = [:]

    static func image(_ glyph: Ph) -> Image {
        if let image = drawn[glyph] { return Image(uiImage: image) }
        guard let source = UIImage(named: glyph.rawValue) else { return Image(systemName: "circle") }
        let size = CGSize(width: 26, height: 26)
        let image = UIGraphicsImageRenderer(size: size)
            .image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
            .withRenderingMode(.alwaysTemplate)
        drawn[glyph] = image
        return Image(uiImage: image)
    }
}

/// Our bottom bar: five icons on a quiet surface with a hairline above. The Post item opens the
/// posting flow instead of switching tabs, and the Profile item is your own avatar.
struct SundaeTabBar: View {
    @Binding var selected: SundayTab
    /// On the heart: what is waiting on you and what is new.
    let badge: Int
    let user: User?
    let onPost: () -> Void
    /// The tab that was already showing was tapped again.
    var onReselect: (SundayTab) -> Void = { _ in }
    @State private var bumped: SundayTab?
    /// The bar's width and where an iPhone Duo's crease crosses it, when the phone is part open.
    @State private var creased = Creased(width: 0, fold: nil)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Creased: Equatable {
        var width: CGFloat
        var fold: CGRect?
    }

    /// Held like a book, the crease runs down the middle of the bar, right where Post would be.
    /// The two left items keep the left page and the other three take the right, with the crease
    /// left empty between them. The sides of the padded bar are 8 in from its edges.
    private var pages: (left: CGFloat, right: CGFloat)? {
        guard let fold = creased.fold, fold.height > fold.width else { return nil }
        let left = fold.minX - 8 - 6
        let right = creased.width - 8 - fold.maxX - 6
        guard left >= 96, right >= 140 else { return nil }
        return (left, right)
    }

    var body: some View {
        HStack(spacing: 0) {
            if let pages {
                HStack(spacing: 0) {
                    item(.feed, Glyph.feed, "Feed")
                    item(.search, Glyph.search, "Search")
                }
                .frame(width: pages.left)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    postItem
                    item(.notifications, Glyph.notifications, "Notifications", badge: badge)
                    profileItem
                }
                .frame(width: pages.right)
            } else {
                item(.feed, Glyph.feed, "Feed")
                item(.search, Glyph.search, "Search")
                postItem
                item(.notifications, Glyph.notifications, "Notifications", badge: badge)
                profileItem
            }
        }
        // On a wide screen (the Duo open, an iPad) the five keep together in the middle instead
        // of spreading to the corners; around a crease the pages above say where they go.
        .frame(maxWidth: pages == nil ? Theme.actionsWidth + 40 : .infinity)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .background {
            // Edge to edge, under the strip an iPhone Duo keeps down one side for the clock and
            // the camera; the buttons themselves stay out of it.
            Theme.background
                .overlay(alignment: .top) { Hairline() }
                .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
        .background {
            Color.clear.onGeometryChange(for: Creased.self) { proxy in
                Creased(width: proxy.size.width, fold: Fold.frame(in: proxy))
            } action: { creased = $0 }
        }
    }

    private var postItem: some View {
        Button {
            Haptics.light()
            onPost()
        } label: {
            Icon(Glyph.post, size: 27)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share your week")
        .accessibilityIdentifier("tab-post")
    }

    private func item(_ which: SundayTab, _ glyph: Ph, _ label: String, badge: Int = 0) -> some View {
        let isSelected = selected == which
        return Button {
            if selected == which { onReselect(which) } else { selected = which }
            bump(which)
        } label: {
            Icon(glyph, weight: isSelected ? .fill : .regular, size: 27)
                .foregroundStyle(.primary)
                .scaleEffect(bumped == which ? 1.18 : 1)
                .animation(.bouncy(duration: 0.35), value: bumped)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Color.accentColor, in: Capsule())
                            .offset(x: 10, y: -6)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(label), \(badge) new" : label)
        .accessibilityIdentifier("tab-\(label.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var profileItem: some View {
        let isSelected = selected == .profile
        return Button {
            if selected == .profile { onReselect(.profile) } else { selected = .profile }
        } label: {
            Group {
                if let user {
                    AvatarView(user: user, size: 27)
                        .overlay {
                            Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2)
                        }
                } else {
                    Icon(Glyph.profile, weight: isSelected ? .fill : .regular, size: 27)
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
        .accessibilityIdentifier("tab-profile")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension SundaeTabBar {
    /// A small hop on the icon you just chose.
    fileprivate func bump(_ which: SundayTab) {
        guard !reduceMotion else { return }
        bumped = which
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            if bumped == which { bumped = nil }
        }
    }
}

/// Resolves a `Route` to its screen. Used by both the compact stack and the regular-width detail column.
struct RouteView: View {
    let route: Route

    var body: some View {
        Group {
            switch route {
            case .dump(let id, let photoID):
                DumpDetailView(dumpID: id, photoID: photoID)
            case .profile(let id):
                ProfileView(userID: id)
            case .people(let userID, let username, let list):
                PeopleListView(userID: userID, username: username, initial: list)
            }
        }
        .aboveBottomBar()
        .swipeBackEnabled()
    }
}

/// A navigation stack rooted at one route, for the detail column of a split view.
struct RouteStack: View {
    let root: Route
    /// Taps on the tab: back to `root` from anything opened from it.
    var reselects = 0
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            RouteView(route: root)
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
                .swipeBackEnabled()
        }
        .onChange(of: reselects) { _, _ in path.removeAll() }
    }
}

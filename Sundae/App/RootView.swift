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
    case feed, search, post, approvals, profile
}

/// Familiar skeleton with our own bottom bar: Feed, Search, Post, Approvals, Profile.
/// The system TabView does the paging (so every tab keeps its scroll position and navigation)
/// with its own bar hidden; the bar you see is `SundaeTabBar`.
struct SundayShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: SundayTab = .feed
    @State private var barHeight: CGFloat = 50
    /// A pinched photo, drawn over everything including the bar.
    @State private var zoom = PhotoZoom()

    private var compose: ComposeStore { model.compose }

    var body: some View {
        TabView(selection: $tab) {
            Tab(value: .feed) { FeedScreen(onPost: openCompose).tabPage(barHeight: barHeight) }
            Tab(value: .search) { SearchScreen().tabPage(barHeight: barHeight) }
            Tab(value: .approvals) { ApprovalsScreen().tabPage(barHeight: barHeight) }
            Tab(value: .profile) { ProfileScreen().tabPage(barHeight: barHeight) }
        }
        // The bar is an overlay and every page reserves its height. A safe area inset on the
        // TabView itself never reached the pages, so a screen's bottom composer sat under the bar.
        .overlay(alignment: .bottom) {
            SundaeTabBar(selected: $tab, pendingApprovals: model.pendingApprovalCount, user: model.currentUser, onPost: openCompose)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                // Stays at the bottom when the keyboard comes up, hidden behind it, instead of riding on top.
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .overlay(alignment: .top) {
            Theme.background.opacity(0.94)
                .frame(height: 0)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .overlay { PhotoZoomLayer() }
        .environment(zoom)
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
            // Coming back from the background counts as opening the app.
            if phase == .active, compose.loadedWeekStart != nil { presentPromptIfNeeded() }
        }
    }

    private func presentPromptIfNeeded() {
        guard !compose.isPresented, compose.shouldShowPrompt(weekStart: model.currentWeekStart) else { return }
        compose.present(.prompt)
    }

    private func openCompose() {
        compose.present(compose.hasPosted ? .arrange : .pick)
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
    /// A tab page under our own bar: the system bar hidden, our height in the environment.
    func tabPage(barHeight: CGFloat) -> some View {
        toolbar(.hidden, for: .tabBar)
            .environment(\.bottomBarInset, barHeight)
    }
}

/// Our bottom bar: five icons on a quiet surface with a hairline above. The Post item opens the
/// posting flow instead of switching tabs, and the Profile item is your own avatar.
struct SundaeTabBar: View {
    @Binding var selected: SundayTab
    let pendingApprovals: Int
    let user: User?
    let onPost: () -> Void
    @State private var bumped: SundayTab?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            item(.feed, Glyph.feed, "Feed")
            item(.search, Glyph.search, "Search")
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
            .accessibilityLabel("Post your week")
            .accessibilityIdentifier("tab-post")
            item(.approvals, Glyph.approvals, "Approvals", badge: pendingApprovals)
            profileItem
        }
        .padding(.horizontal, 8)
        .background {
            Theme.background
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ which: SundayTab, _ glyph: Ph, _ label: String, badge: Int = 0) -> some View {
        let isSelected = selected == which
        return Button {
            selected = which
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
        .accessibilityLabel(badge > 0 ? "\(label), \(badge) waiting" : label)
        .accessibilityIdentifier("tab-\(label.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var profileItem: some View {
        let isSelected = selected == .profile
        return Button {
            selected = .profile
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
            }
        }
        .aboveBottomBar()
        .swipeBackEnabled()
    }
}

/// A navigation stack rooted at one route, for the detail column of a split view.
struct RouteStack: View {
    let root: Route

    var body: some View {
        NavigationStack {
            RouteView(route: root)
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
                .swipeBackEnabled()
        }
    }
}

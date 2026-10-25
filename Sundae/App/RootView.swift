import SwiftUI
import PhosphorSwift

/// Decides between onboarding, the weekday screen and the Sunday shell.
/// The decision comes from `AppModel.phase`, which flips itself at midnight.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isRestoringSession {
                ProgressView()
            } else if !model.isSignedIn {
                OnboardingView()
            } else if model.isSunday {
                SundayShell()
            } else {
                WeekdayView()
            }
        }
        .animation(.default, value: model.isSunday)
        .animation(.default, value: model.isSignedIn)
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
    @State private var tab: SundayTab = .feed
    @State private var barHeight: CGFloat = 50

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
        }
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
            if compose.shouldShowPrompt(weekStart: model.currentWeekStart) {
                compose.present(.prompt)
            }
        }
    }

    private func openCompose() {
        compose.present(compose.hasPosted ? .arrange : .pick)
    }
}

private extension View {
    /// A tab page under our own bar: the system bar hidden, and room kept for ours.
    func tabPage(barHeight: CGFloat) -> some View {
        toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: barHeight) }
    }
}

/// Our bottom bar: five icons on a quiet surface with a hairline above. The Post item opens the
/// posting flow instead of switching tabs, and the Profile item is your own avatar.
struct SundaeTabBar: View {
    @Binding var selected: SundayTab
    let pendingApprovals: Int
    let user: User?
    let onPost: () -> Void

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
        } label: {
            Icon(glyph, weight: isSelected ? .fill : .regular, size: 27)
                .foregroundStyle(.primary)
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

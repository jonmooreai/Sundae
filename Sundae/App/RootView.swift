import SwiftUI

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

enum SundayTab: Hashable {
    case feed, search, post, approvals, profile
}

/// Familiar skeleton: Feed, Search, Post, Approvals, Profile.
/// `.sidebarAdaptable` turns the bottom bar into a sidebar in regular width (iPad, Duo unfolded),
/// which also keeps the tab bar away from the Duo's right-side dock.
struct SundayShell: View {
    @Environment(AppModel.self) private var model
    @State private var tab: SundayTab = .feed

    var body: some View {
        TabView(selection: $tab) {
            Tab("Feed", systemImage: Icon.feed, value: .feed) {
                FeedScreen(onPost: { tab = .post })
            }
            Tab("Search", systemImage: Icon.search, value: .search, role: .search) {
                SearchScreen()
            }
            Tab("Post", systemImage: Icon.post, value: .post) {
                ComposeScreen()
            }
            Tab("Approvals", systemImage: Icon.approvals, value: .approvals) {
                ApprovalsScreen()
            }
            .badge(model.pendingApprovalCount)
            Tab("Profile", systemImage: Icon.profile, value: .profile) {
                ProfileScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: model.requestedTab) { _, requested in
            guard let requested else { return }
            tab = requested
            model.requestedTab = nil
        }
    }
}

/// Resolves a `Route` to its screen. Used by both the compact stack and the regular-width detail column.
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .dump(let id):
            DumpDetailView(dumpID: id)
        case .profile(let id):
            ProfileView(userID: id)
        }
    }
}

/// A navigation stack rooted at one route, for the detail column of a split view.
struct RouteStack: View {
    let root: Route

    var body: some View {
        NavigationStack {
            RouteView(route: root)
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

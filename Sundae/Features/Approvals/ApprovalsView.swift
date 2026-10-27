import SwiftUI

struct ApprovalsScreen: View {
    /// Taps on the tab while it shows: back to this screen, then to its top.
    var reselects = 0
    @State private var path: [Route] = []
    @State private var scrollSignal = 0

    var body: some View {
        NavigationStack(path: $path) {
            ApprovalsView()
                .environment(\.scrollToTop, scrollSignal)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
                .aboveBottomBar()
                .swipeBackEnabled()
        }
        .onChange(of: reselects) { _, _ in
            if path.isEmpty { scrollSignal += 1 } else { path.removeAll() }
        }
    }
}

/// The one social action open every day of the week. Approve adds the photo to your week;
/// decline removes the tag everywhere and nobody is told.
struct ApprovalsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Requests whose card is showing its "added to your week" moment before it leaves.
    @State private var approved: Set<ID> = []

    private var store: ApprovalsStore { model.approvals }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                ScreenHeader(title: "Approvals", subtitle: store.requests.isEmpty ? nil : "Photos friends tagged you in") {
                    if !model.isSunday {
                        Button("Done") { dismiss() }
                            .buttonStyle(.pill(.secondary, size: .small))
                    }
                }
                .id(ScrollTop.id)
                if let message = store.errorMessage {
                    ErrorBanner(message: message).padding(.horizontal, Theme.pagePadding)
                }
                ForEach(store.requests) { request in
                    TagRequestCard(request: request, isApproved: approved.contains(request.id)) { approve in
                        respond(to: request, approve: approve)
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.94).combined(with: .opacity)))
                }
                if store.hasLoaded && store.requests.isEmpty {
                    VStack(spacing: 10) {
                        Icon(Glyph.approvals, size: 36).foregroundStyle(.secondary)
                        Text("Nothing waiting").font(Theme.display(24))
                        Text("When a friend tags you in their week, it shows up here first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .padding(.top, 40)
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollsToTopOnTabTap()
        .background(Theme.background)
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    /// Approve stamps the photo and shows the chip it will wear on your week, then the card
    /// folds away. Decline just folds away.
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
            await model.refreshPendingCount()
        }
    }
}

/// Flat: who tagged you, the photo, one line of explanation, two pills.
struct TagRequestCard: View {
    @Environment(AppModel.self) private var model
    let request: TagRequest
    var isApproved = false
    let respond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AvatarView(user: request.tagger, size: 36)
                // The name and the username together: a name can be copied, a username can't.
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(request.tagger.displayName) tagged you")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(request.tagger.handle) \u{2022} \(model.clock.rangeLabel(weekStart: request.weekStart))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.pagePadding)

            PhotoView(source: request.photo.source)
                .aspectRatio(min(max(request.photo.aspectRatio, 0.8), 1.5), contentMode: .fit)
                .overlay {
                    if isApproved {
                        ZStack {
                            Color.black.opacity(0.22)
                            ApprovedStamp()
                        }
                        .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isApproved {
                        AttributionChip(user: request.tagger)
                            .padding(6)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius + 4, style: .continuous))
                .padding(.horizontal, Theme.pagePadding)
                .accessibilityLabel(request.photo.altText ?? "Photo from \(request.tagger.firstName)'s week")

            Text(isApproved
                 ? "Added to your week."
                 : "Approve to add it to your week as \u{201C}from \(request.tagger.firstName)\u{201D}. You can remove it later.")
                .font(.footnote)
                .foregroundStyle(isApproved ? Color.accentColor : .secondary)
                .padding(.horizontal, Theme.pagePadding)

            if isApproved {
                HStack(spacing: 6) {
                    Icon(Glyph.done, weight: .bold, size: 16)
                    Text("Added to your week")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .transition(.opacity)
            } else {
                HStack(spacing: 10) {
                    Button("Decline") { respond(false) }
                        .buttonStyle(.pill(.secondary, fullWidth: true))
                    Button("Approve") { respond(true) }
                        .buttonStyle(.pill(.primary, fullWidth: true))
                }
                .padding(.horizontal, Theme.pagePadding)
            }
        }
    }
}

/// The check that lands on a photo the moment you approve it.
private struct ApprovedStamp: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Icon(Glyph.done, weight: .bold, size: 34)
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .background(Color.accentColor, in: Circle())
            .scaleEffect(shown ? 1 : 0.4)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(reduceMotion ? nil : .bouncy(duration: 0.45, extraBounce: 0.15)) { shown = true } }
            .accessibilityLabel("Approved")
    }
}

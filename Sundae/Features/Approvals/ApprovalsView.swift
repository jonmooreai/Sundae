import SwiftUI

struct ApprovalsScreen: View {
    var body: some View {
        NavigationStack {
            ApprovalsView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

/// The one social action open every day of the week. Approve adds the photo to your week;
/// decline removes the tag everywhere and nobody is told.
struct ApprovalsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

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
                if let message = store.errorMessage {
                    ErrorBanner(message: message).padding(.horizontal, Theme.pagePadding)
                }
                ForEach(store.requests) { request in
                    TagRequestCard(request: request) { approve in
                        Task {
                            await store.respond(request, approve: approve)
                            await model.refreshPendingCount()
                        }
                    }
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
        .background(Theme.background)
        .task { await store.load() }
        .refreshable { await store.load() }
    }
}

/// Flat: who tagged you, the photo, one line of explanation, two pills.
struct TagRequestCard: View {
    @Environment(AppModel.self) private var model
    let request: TagRequest
    let respond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AvatarView(user: request.tagger, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(request.tagger.username) tagged you")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(model.clock.rangeLabel(weekStart: request.weekStart))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.pagePadding)

            PhotoView(source: request.photo.source)
                .aspectRatio(min(max(request.photo.aspectRatio, 0.8), 1.5), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius + 4, style: .continuous))
                .padding(.horizontal, Theme.pagePadding)
                .accessibilityLabel(request.photo.altText ?? "Photo from \(request.tagger.firstName)'s week")

            Text("Approve to add it to your week as \u{201C}from \(request.tagger.firstName)\u{201D}. You can remove it later.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.pagePadding)

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

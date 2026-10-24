import SwiftUI

struct ApprovalsScreen: View {
    var body: some View {
        NavigationStack {
            ApprovalsView()
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

/// The one social action open every day of the week. Approve adds the photo to your week;
/// decline removes the tag everywhere and nobody is told.
struct ApprovalsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var store: ApprovalsStore { model.approvals }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if let message = store.errorMessage {
                    ErrorBanner(message: message)
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
                    ContentUnavailableView("No tags waiting", systemImage: Icon.approvals,
                                           description: Text("When a friend tags you in their week, it shows up here first."))
                        .padding(.top, 40)
                }
            }
            .padding(Theme.pagePadding)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Approvals")
        .toolbar {
            if !model.isSunday {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }
}

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

            PhotoView(source: request.photo.source)
                .aspectRatio(min(max(request.photo.aspectRatio, 0.8), 1.5), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
                .accessibilityLabel(request.photo.altText ?? "Photo from \(request.tagger.firstName)'s week")

            Text("Approve to add it to your week as \u{201C}from \(request.tagger.firstName)\u{201D}. You can remove it later.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    respond(false)
                } label: {
                    Text("Decline").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    respond(true)
                } label: {
                    Text("Approve").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .card()
    }
}

import SwiftUI

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

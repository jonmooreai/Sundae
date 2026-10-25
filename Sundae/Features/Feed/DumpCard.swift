import SwiftUI
import PhosphorSwift

/// One feed item is one dump. Same anatomy as a carousel post so the muscle memory transfers:
/// author header, paged photos, actions, caption, tagged names, likes, comments.
struct DumpCard: View {
    @Environment(AppModel.self) private var model
    let dump: Dump
    let open: (Route) -> Void
    let onLike: () -> Void

    @State private var page = 0
    @State private var reporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header.padding(.horizontal, Theme.pagePadding)

            PhotoCarousel(photos: dump.photos, index: $page) { position in
                guard dump.photos.indices.contains(position) else { return }
                open(.dump(dump.id, photo: dump.photos[position].id))
            }
            .onTapGesture(count: 2) { if !dump.likedByMe { onLike() } }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 18) {
                    Button(action: onLike) {
                        Icon(Glyph.heart, weight: dump.likedByMe ? .fill : .regular, size: 26)
                            .foregroundStyle(dump.likedByMe ? Color.accentColor : .primary)
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: dump.likedByMe)
                    }
                    .accessibilityLabel(dump.likedByMe ? "Unlike" : "Like")

                    Button { open(.dump(dump.id)) } label: {
                        Icon(Glyph.comment, size: 26)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Comments")
                    .disabled(!dump.commentsEnabled)

                    Spacer()
                    if dump.photos.count > 1 {
                        Text("\(page + 1) of \(dump.photos.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)

                if !dump.caption.isEmpty {
                    Text(dump.caption)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !dump.taggedUsers.isEmpty {
                    taggedLine
                }

                LikesLabel(dump: dump, meID: model.currentUser?.id)

                if dump.commentCount > 0 {
                    Button {
                        open(.dump(dump.id))
                    } label: {
                        Text(dump.commentCount == 1 ? "View 1 comment" : "View all \(dump.commentCount) comments")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .sheet(isPresented: $reporting) {
            ReportSheet(target: .dump, targetID: dump.id)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { open(.profile(dump.author.id)) } label: {
                HStack(spacing: 10) {
                    AvatarView(user: dump.author, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(dump.author.username).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(model.clock.rangeLabel(weekStart: dump.weekStart))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("author-\(dump.author.username)")
            Spacer()
            Menu {
                if dump.author.id != model.currentUser?.id {
                    Button { reporting = true } label: { Label { Text("Report") } icon: { Glyph.flag.regular } }
                    Button(role: .destructive) {
                        Task {
                            try? await model.api.block(userID: dump.author.id)
                            await model.feed.load(refresh: true)
                        }
                    } label: {
                        Label { Text("Block \(dump.author.firstName)") } icon: { Glyph.block.regular }
                    }
                } else {
                    Button(role: .destructive) {
                        Task {
                            try? await model.api.deleteDump(id: dump.id)
                            model.feed.remove(dumpID: dump.id)
                            model.compose.reset()
                        }
                    } label: {
                        Label { Text("Delete this week") } icon: { Glyph.trash.regular }
                    }
                }
            } label: {
                Icon(Glyph.more, weight: .bold, size: 22)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
        }
    }

    private var taggedLine: some View {
        let users = dump.taggedUsers
        return HStack(spacing: 0) {
            Text("with ").foregroundStyle(.secondary)
            ForEach(Array(users.enumerated()), id: \.element.id) { i, user in
                Button(user.firstName) { open(.profile(user.id)) }
                    .buttonStyle(.plain)
                    .fontWeight(.medium)
                if i < users.count - 1 {
                    Text(i == users.count - 2 ? " and " : ", ").foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
    }
}

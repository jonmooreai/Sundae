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
    @State private var showPeople = false
    @State private var showComments = false
    @State private var focusComposer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header.padding(.horizontal, Theme.pagePadding)

            PhotoCarousel(photos: dump.photos, index: $page, onTap: { position in
                guard dump.photos.indices.contains(position) else { return }
                open(.dump(dump.id, photo: dump.photos[position].id))
            }, onDoubleTap: {
                if !dump.likedByMe { onLike() }
            }, onTapTag: { user in
                open(.profile(user.id))
            })

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    LikeButton(liked: dump.likedByMe, celebrates: dump.likedBy.count >= 10, action: onLike)

                    Button {
                        focusComposer = true
                        showComments = true
                    } label: {
                        Icon(Glyph.comment, size: 26)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Comments")
                    .disabled(!dump.commentsEnabled)

                    LikesLabel(dump: dump, meID: model.currentUser?.id)

                    Spacer(minLength: 8)
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

                if dump.commentCount > 0 {
                    Button {
                        focusComposer = false
                        showComments = true
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
        .sheet(isPresented: $showPeople) {
            TaggedPeopleSheet(users: dump.taggedUsers) { user in
                showPeople = false
                open(.profile(user.id))
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsSheet(dump: dump, focusOnOpen: focusComposer)
                .environment(model)
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

    /// A few overlapping faces and "with Lena, Jon and 4 others". Tap for the whole list.
    private var taggedLine: some View {
        let users = dump.taggedUsers
        return Button {
            showPeople = true
        } label: {
            HStack(spacing: 8) {
                FacePile(users: Array(users.prefix(3)))
                (Text("with ").foregroundColor(.secondary) + Text(namesLine(users)).fontWeight(.medium))
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("With " + ListFormatter.localizedString(byJoining: users.map(\.firstName)))
    }

    private func namesLine(_ users: [User]) -> String {
        let names = users.map(\.firstName)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        case 3: return "\(names[0]), \(names[1]) and \(names[2])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) others"
        }
    }
}

/// Up to three faces overlapping, the first on top, each ringed in the page color.
struct FacePile: View {
    let users: [User]
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: -(size * 0.32)) {
            ForEach(Array(users.enumerated()), id: \.element.id) { i, user in
                AvatarView(user: user, size: size)
                    .overlay { Circle().strokeBorder(Theme.background, lineWidth: 2) }
                    .zIndex(Double(users.count - i))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Everyone tagged in a week, one row each. Tap a row to open the profile.
struct TaggedPeopleSheet: View {
    let users: [User]
    let open: (User) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("With").font(Theme.display(26))
                Spacer()
                IconButton(glyph: Glyph.close, label: "Close", size: 20) { dismiss() }
                    .padding(.trailing, -8)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 20)
            .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(users) { user in
                        Button {
                            open(user)
                        } label: {
                            UserRow(user: user, subtitle: user.name)
                                .padding(.horizontal, Theme.pagePadding)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

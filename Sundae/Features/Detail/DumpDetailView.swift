import SwiftUI

/// Full dump: photos, caption, tags, likes, and the one conversation per dump.
struct DumpDetailView: View {
    @Environment(AppModel.self) private var model
    let dumpID: ID
    /// The photo to show first, when the dump was opened by tapping one.
    var photoID: ID? = nil

    @State private var dump: Dump?
    @State private var comments: [Comment] = []
    @State private var page = 0
    @State private var errorMessage: String?
    @State private var reporting = false
    @State private var showFullScreen = false
    @State private var showComments = false
    @State private var focusComposer = false
    @State private var profileToOpen: ID?

    private var isOwn: Bool { dump?.author.id == model.currentUser?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: dump.map { model.clock.rangeLabel(weekStart: $0.weekStart) } ?? "", showsBack: true) {
                    if let dump {
                        Menu {
                            if isOwn {
                                Button(role: .destructive) {
                                    Task {
                                        try? await model.api.deleteDump(id: dump.id)
                                        model.feed.remove(dumpID: dump.id)
                                        model.compose.reset()
                                    }
                                } label: {
                                    Label { Text("Delete this week") } icon: { Glyph.trash.regular }
                                }
                            } else {
                                Button { reporting = true } label: { Label { Text("Report") } icon: { Glyph.flag.regular } }
                                Button(role: .destructive) {
                                    Task { try? await model.api.block(userID: dump.author.id) }
                                } label: {
                                    Label { Text("Block \(dump.author.firstName)") } icon: { Glyph.block.regular }
                                }
                            }
                        } label: {
                            Icon(Glyph.more, weight: .bold, size: 24)
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("More")
                    }
                }
                if let dump {
                    content(dump)
                } else if let errorMessage {
                    ErrorBanner(message: errorMessage).padding(Theme.pagePadding)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $reporting) {
            ReportSheet(target: .dump, targetID: dumpID)
        }
        .sheet(isPresented: $showComments, onDismiss: { Task { await reloadComments() } }) {
            if let dump {
                CommentsSheet(dump: dump, focusOnOpen: focusComposer, onCountChange: { count in
                    self.dump?.commentCount = count
                }, onOpenProfile: { user in
                    showComments = false
                    profileToOpen = user.id
                })
                .environment(model)
            }
        }
        .navigationDestination(item: $profileToOpen) { id in
            RouteView(route: .profile(id))
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            if let dump, dump.photos.indices.contains(page) {
                FullScreenPhotoView(photo: dump.photos[page], caption: dump.caption)
            }
        }
        .task(id: dumpID) { await load() }
    }

    @ViewBuilder
    private func content(_ dump: Dump) -> some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.profile(dump.author.id)) {
                HStack(spacing: 10) {
                    AvatarView(user: dump.author, size: 36)
                    Text(dump.author.displayName).font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, Theme.pagePadding)

        PhotoCarousel(photos: dump.photos, index: $page, onDoubleTap: {
            if !dump.likedByMe { Task { await toggleLike() } }
        }, tagsLinkToProfiles: true)
            .focusable()
            .onKeyPress(.leftArrow) { page = max(0, page - 1); return .handled }
            .onKeyPress(.rightArrow) { page = min(dump.photos.count - 1, page + 1); return .handled }
            // Pinching looks closer; Space opens full screen.
            .onKeyPress(.space) { showFullScreen = true; return .handled }

        PhotoCaptionLine(photos: dump.photos, page: page)
            .padding(.horizontal, Theme.pagePadding)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                LikeButton(liked: dump.likedByMe, celebrates: dump.likedBy.count >= 10) {
                    Task { await toggleLike() }
                }
                Button {
                    focusComposer = true
                    showComments = true
                } label: {
                    Icon(Glyph.comment, size: 26).foregroundStyle(.primary)
                }
                .accessibilityLabel("Comments")
                .disabled(!dump.commentsEnabled)
                LikesLabel(dump: dump, meID: model.currentUser?.id)
                Spacer(minLength: 8)
                if dump.photos.count > 1 {
                    Text("\(page + 1) of \(dump.photos.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .buttonStyle(.plain)

            if !dump.caption.isEmpty {
                Text(dump.caption).fixedSize(horizontal: false, vertical: true)
            }

            if isOwn {
                SealRow(dump: dump)
            }
        }
        .padding(.horizontal, Theme.pagePadding)

        // The last two comments as a taste; the drawer has the whole conversation.
        VStack(alignment: .leading, spacing: 12) {
            if !dump.commentsEnabled {
                Text("Comments are off for this week.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Button {
                    focusComposer = comments.isEmpty
                    showComments = true
                } label: {
                    HStack(spacing: 8) {
                        Text(dump.commentCount == 0 ? "Add a comment"
                             : dump.commentCount == 1 ? "1 comment" : "\(dump.commentCount) comments")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Icon(Glyph.chevronRight, weight: .bold, size: 13).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach(comments.suffix(2)) { comment in
                    Button {
                        focusComposer = false
                        showComments = true
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            AvatarView(user: comment.author, size: 24)
                            (Text(comment.author.username).fontWeight(.semibold) + Text("  ") + Text(comment.body))
                                .font(.subheadline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
    }

    private func reloadComments() async {
        comments = (try? await model.api.comments(dumpID: dumpID)) ?? comments
    }

    private func load() async {
        do {
            let loaded = try await model.api.dump(id: dumpID)
            if let photoID, let index = loaded.photos.firstIndex(where: { $0.id == photoID }) {
                page = index
            }
            dump = loaded
            comments = try await model.api.comments(dumpID: dumpID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleLike() async {
        guard let current = dump else { return }
        do {
            dump = try await model.api.setLike(dumpID: current.id, liked: !current.likedByMe)
            if let dump { model.feed.replace(dump) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

/// Report is available on every photo, dump, comment and profile.
struct ReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: Report.Target
    let targetID: ID

    @State private var reason: Report.Reason = .spam
    @State private var note = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            SettingsScreen(title: "Report") {
                SettingsGroup(title: "Reason") {
                    ForEach(Report.Reason.allCases) { option in
                        RadioRow(title: option.label, isSelected: reason == option) { reason = option }
                    }
                }
                SettingsGroup(title: "Anything else?", footer: "They are not told who reported them.") {
                    SettingsFieldRow(label: "Note", text: $note, prompt: "Optional", multiline: true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.textButtonTint() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task {
                            try? await model.api.report(Report(target: target, targetID: targetID, reason: reason, note: note))
                            dismiss()
                        }
                    }
                    .textButtonTint()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

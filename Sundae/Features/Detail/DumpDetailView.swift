import SwiftUI
import PhosphorSwift

/// Full dump: photos, caption, tags, likes, and the one conversation per dump.
struct DumpDetailView: View {
    @Environment(AppModel.self) private var model
    let dumpID: ID

    @State private var dump: Dump?
    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @State private var page = 0
    @State private var errorMessage: String?
    @State private var reporting = false
    @State private var isSending = false
    @State private var showFullScreen = false

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
        .fullScreenCover(isPresented: $showFullScreen) {
            if let dump, dump.photos.indices.contains(page) {
                FullScreenPhotoView(photo: dump.photos[page], caption: dump.caption)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let dump, dump.commentsEnabled {
                commentField
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

        PhotoCarousel(photos: dump.photos, index: $page)
            .focusable()
            .onKeyPress(.leftArrow) { page = max(0, page - 1); return .handled }
            .onKeyPress(.rightArrow) { page = min(dump.photos.count - 1, page + 1); return .handled }
            .onKeyPress(.space) { showFullScreen = true; return .handled }
            .onLongPressGesture { showFullScreen = true }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                Button {
                    Task { await toggleLike() }
                } label: {
                    Icon(Glyph.heart, weight: dump.likedByMe ? .fill : .regular, size: 26)
                        .foregroundStyle(dump.likedByMe ? Color.accentColor : .primary)
                }
                .accessibilityLabel(dump.likedByMe ? "Unlike" : "Like")
                Spacer()
                if dump.photos.count > 1 {
                    Text("\(page + 1) of \(dump.photos.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .buttonStyle(.plain)

            if !dump.caption.isEmpty {
                Text(dump.caption).fixedSize(horizontal: false, vertical: true)
            }

            let currentTags = dump.photos.indices.contains(page) ? dump.photos[page].visibleTags : []
            if !currentTags.isEmpty {
                HStack(spacing: 6) {
                    Text("In this photo:").foregroundStyle(.secondary)
                    ForEach(currentTags) { tag in
                        NavigationLink(value: Route.profile(tag.taggedUser.id)) {
                            Text(tag.taggedUser.firstName).fontWeight(.medium)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.subheadline)
            }

            LikesLabel(dump: dump, meID: model.currentUser?.id)
        }
        .padding(.horizontal, Theme.pagePadding)

        VStack(alignment: .leading, spacing: 14) {
            if !dump.commentsEnabled {
                Text("Comments are off for this week.").font(.footnote).foregroundStyle(.secondary)
            } else if comments.isEmpty {
                Text("No comments yet.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(comments) { comment in
                HStack(alignment: .top, spacing: 10) {
                    AvatarView(user: comment.author, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(comment.author.displayName).font(.subheadline.weight(.semibold))
                            Text(comment.createdAt, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(comment.body).font(.subheadline)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
    }

    private var commentField: some View {
        HStack(spacing: 10) {
            TextField("Add a comment", text: $newComment)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: Capsule())
                .onSubmit { Task { await send() } }
            Button {
                Task { await send() }
            } label: {
                Icon(Glyph.send, weight: .bold, size: 18)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            .opacity(newComment.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            .accessibilityLabel("Send comment")
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 10)
        .background {
            Theme.background
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func load() async {
        do {
            dump = try await model.api.dump(id: dumpID)
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

    private func send() async {
        let body = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let comment = try await model.api.addComment(dumpID: dumpID, body: body)
            comments.append(comment)
            newComment = ""
            if var updated = dump {
                updated.commentCount += 1
                dump = updated
                model.feed.replace(updated)
            }
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
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(Report.Reason.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Anything else?") {
                    TextField("Optional", text: $note, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    Text("Reports go to a review queue. The person is not told who reported them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task {
                            try? await model.api.report(Report(target: target, targetID: targetID, reason: reason, note: note))
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

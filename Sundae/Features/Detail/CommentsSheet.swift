import SwiftUI
import PhosphorSwift

/// The conversation under a week, in a drawer over the photos. Flat comments, newest at the
/// bottom, a heart on each. Your own can be edited or deleted (delete gives you a few seconds to
/// change your mind), the week's author can delete anyone's. Quick replies sit above the field.
struct CommentsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let dump: Dump
    var focusOnOpen = false
    /// Called with the new total whenever a comment is added or removed.
    var onCountChange: ((Int) -> Void)? = nil

    @State private var comments: [Comment] = []
    @State private var hasLoaded = false
    @State private var text = ""
    @State private var editing: Comment?
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var pendingDelete: Comment?
    @State private var deleteTask: Task<Void, Never>?
    @State private var reporting: Comment?
    @FocusState private var composing: Bool

    private static let quickReplies = ["❤️", "this one", "take me next time", "the light!", "frame it"]

    private var meID: ID? { model.currentUser?.id }
    private var isDumpOwner: Bool { dump.author.id == meID }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !dump.commentsEnabled {
                Spacer()
                Text("Comments are off for this week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                list
                if let pendingDelete {
                    undoBar(for: pendingDelete)
                }
                quickReplies
                composer
            }
        }
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .task { await load() }
        .onDisappear { flushPendingDelete() }
        .sheet(item: $reporting) { comment in
            ReportSheet(target: .comment, targetID: comment.id)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Comments").font(Theme.display(26))
            if !comments.isEmpty {
                Text("\(comments.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            IconButton(glyph: Glyph.close, label: "Close", size: 20) { dismiss() }
                .padding(.trailing, -8)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .animation(.snappy(duration: 0.25), value: comments.count)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                        .listRowInsets(EdgeInsets(top: 4, leading: Theme.pagePadding, bottom: 4, trailing: Theme.pagePadding))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if hasLoaded && comments.isEmpty && errorMessage == nil {
                    VStack(spacing: 6) {
                        Text("Nothing here yet.").font(Theme.display(22))
                        Text("Say something nice about their week.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                ForEach(comments) { comment in
                    let isMine = comment.author.id == meID
                    CommentRow(comment: comment, now: model.clock.now(), isMine: isMine) {
                        Task { await toggleLike(comment) }
                    }
                    .id(comment.id)
                    .listRowInsets(EdgeInsets(top: 10, leading: Theme.pagePadding, bottom: 10, trailing: Theme.pagePadding))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if isMine || isDumpOwner {
                            Button(role: .destructive) { delete(comment) } label: { Label("Delete", systemImage: "trash") }
                                .tint(Theme.cherry)
                        }
                        if isMine {
                            Button { beginEditing(comment) } label: { Label("Edit", systemImage: "pencil") }
                                .tint(Color.accentColor)
                        }
                    }
                    .contextMenu {
                        if isMine {
                            Button { beginEditing(comment) } label: { Label { Text("Edit") } icon: { Glyph.altText.regular } }
                        }
                        if isMine || isDumpOwner {
                            Button(role: .destructive) { delete(comment) } label: { Label { Text("Delete") } icon: { Glyph.trash.regular } }
                        }
                        if !isMine {
                            Button { reporting = comment } label: { Label { Text("Report") } icon: { Glyph.flag.regular } }
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Color.clear.frame(height: 8)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: comments.last?.id) { _, last in
                guard let last, composing || isSending else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private func undoBar(for comment: Comment) -> some View {
        HStack(spacing: 10) {
            Text("Comment deleted")
                .font(.subheadline)
            Spacer()
            Button("Undo") { undoDelete() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var quickReplies: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Self.quickReplies, id: \.self) { reply in
                    Button {
                        Haptics.light()
                        text = text.isEmpty ? reply : text.trimmingCharacters(in: .whitespaces) + " " + reply
                        composing = true
                    } label: {
                        Text(reply)
                    }
                    .buttonStyle(.pill(.secondary, size: .small))
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let editing {
                HStack(spacing: 6) {
                    Icon(Glyph.altText, size: 14).foregroundStyle(.secondary)
                    Text("Editing your comment").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { cancelEditing() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Editing your comment from \(relativeTime(editing.createdAt, now: model.clock.now()))")
            }
            HStack(spacing: 10) {
                if let me = model.currentUser {
                    AvatarView(user: me, size: 34)
                }
                TextField(editing == nil ? "Add a comment" : "Edit your comment", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .focused($composing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button {
                    Task { await submit() }
                } label: {
                    Icon(editing == nil ? Glyph.send : Glyph.done, weight: .bold, size: 18)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty || isSending)
                .opacity(trimmed.isEmpty ? 0.4 : 1)
                .accessibilityLabel(editing == nil ? "Send comment" : "Save comment")
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .animation(.snappy(duration: 0.25), value: editing?.id)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Actions

    private func load() async {
        do {
            comments = try await model.api.comments(dumpID: dump.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
        if focusOnOpen { composing = true }
    }

    private func submit() async {
        guard !trimmed.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            if let editing {
                let updated = try await model.api.updateComment(id: editing.id, body: trimmed)
                withAnimation(.snappy(duration: 0.3)) { replace(updated) }
                self.editing = nil
            } else {
                let comment = try await model.api.addComment(dumpID: dump.id, body: trimmed)
                withAnimation(.snappy(duration: 0.35)) { comments.append(comment) }
                publishCount()
            }
            Haptics.light()
            text = ""
            composing = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleLike(_ comment: Comment) async {
        // Flip it right away; the server's answer settles the count.
        var optimistic = comment
        optimistic.likedByMe.toggle()
        optimistic.likeCount += optimistic.likedByMe ? 1 : -1
        replace(optimistic)
        do {
            let settled = try await model.api.setCommentLike(id: comment.id, liked: optimistic.likedByMe)
            replace(settled)
        } catch {
            replace(comment)
            errorMessage = error.localizedDescription
        }
    }

    private func beginEditing(_ comment: Comment) {
        editing = comment
        text = comment.body
        composing = true
    }

    private func cancelEditing() {
        editing = nil
        text = ""
        composing = false
    }

    /// Takes the comment off the list and gives four seconds to undo before telling the server.
    private func delete(_ comment: Comment) {
        flushPendingDelete()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            comments.removeAll { $0.id == comment.id }
            pendingDelete = comment
        }
        Haptics.light()
        publishCount()
        deleteTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await commitDelete(comment)
        }
    }

    private func undoDelete() {
        deleteTask?.cancel()
        deleteTask = nil
        guard let comment = pendingDelete else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            comments.append(comment)
            comments.sort { $0.createdAt < $1.createdAt }
            pendingDelete = nil
        }
        publishCount()
    }

    private func commitDelete(_ comment: Comment) async {
        if pendingDelete?.id == comment.id {
            withAnimation(.snappy(duration: 0.3)) { pendingDelete = nil }
        }
        do {
            try await model.api.deleteComment(id: comment.id)
        } catch {
            errorMessage = error.localizedDescription
            await load()
            publishCount()
        }
    }

    /// The drawer is closing: anything still waiting on Undo is deleted for real.
    private func flushPendingDelete() {
        guard let comment = pendingDelete else { return }
        deleteTask?.cancel()
        deleteTask = nil
        pendingDelete = nil
        Task { await commitDelete(comment) }
    }

    private func replace(_ comment: Comment) {
        if let index = comments.firstIndex(where: { $0.id == comment.id }) {
            comments[index] = comment
        }
    }

    private func publishCount() {
        model.feed.setCommentCount(dumpID: dump.id, count: comments.count)
        onCountChange?(comments.count)
    }
}

/// One comment: face, name and when, the words, and a heart with its count on the right.
struct CommentRow: View {
    let comment: Comment
    let now: Date
    var isMine = false
    let onLike: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(user: comment.author, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isMine ? "you" : comment.author.username)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(relativeTime(comment.createdAt, now: now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if comment.editedAt != nil {
                        Text("· Edited")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(comment.body)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                LikeButton(liked: comment.likedByMe, size: 18, action: onLike)
                if comment.likeCount > 0 {
                    Text("\(comment.likeCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .padding(.top, 2)
            .animation(.snappy(duration: 0.25), value: comment.likeCount)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "now", "4m", "2h", "3d", "2w": short enough to sit beside a name.
func relativeTime(_ date: Date, now: Date) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(Int(seconds / 60))m"
    case ..<86_400: return "\(Int(seconds / 3600))h"
    case ..<604_800: return "\(Int(seconds / 86_400))d"
    default: return "\(Int(seconds / 604_800))w"
    }
}

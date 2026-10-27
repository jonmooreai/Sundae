import SwiftUI

/// The conversation under a week, in a drawer over the photos. Comments oldest first, each with
/// its replies under it, a heart on each. Reply answers one; @ suggests friends to mention, and a
/// mention opens that person. Your own can be edited or deleted (delete gives you a few seconds to
/// change your mind), the week's author can delete anyone's. Quick replies sit above the field.
struct CommentsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let dump: Dump
    var focusOnOpen = false
    /// Called with the new total whenever a comment is added or removed.
    var onCountChange: ((Int) -> Void)? = nil
    /// Tapping a commenter's face or name. The caller closes the drawer and opens the profile.
    var onOpenProfile: ((User) -> Void)? = nil

    @State private var comments: [Comment] = []
    @State private var hasLoaded = false
    @State private var text = ""
    @State private var editing: Comment?
    /// The comment being answered. The server files the reply under its top comment.
    @State private var replyingTo: Comment?
    /// Friends, for @ suggestions.
    @State private var taggable: [User] = []
    @State private var isSending = false
    @State private var errorMessage: String?
    /// A comment just deleted, with its replies, while Undo is still on screen.
    @State private var pendingDelete: [Comment]?
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
                if pendingDelete != nil {
                    undoBar
                }
                if mentionQuery != nil {
                    mentionSuggestions
                } else {
                    quickReplies
                }
                if let replyingTo, editing == nil {
                    replyBanner(replyingTo)
                }
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
        HStack(alignment: .center, spacing: 8) {
            Text("Comments").font(Theme.display(26))
            Spacer()
            IconButton(glyph: Glyph.close, label: "Close", size: 20) { dismiss() }
                .padding(.trailing, -8)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 18)
        .padding(.bottom, 6)
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
                ForEach(threaded) { item in
                    let comment = item.comment
                    let isMine = comment.author.id == meID
                    CommentRow(comment: comment, now: model.clock.now(), isMine: isMine, isReply: item.isReply,
                               people: people,
                               onOpenProfile: onOpenProfile.map { open in { open(comment.author) } },
                               onOpenPerson: onOpenProfile,
                               onReply: { beginReply(to: comment) }) {
                        Task { await toggleLike(comment) }
                    }
                    .id(comment.id)
                    .listRowInsets(EdgeInsets(top: item.isReply ? 4 : 10, leading: Theme.pagePadding + (item.isReply ? 42 : 0),
                                              bottom: 10, trailing: Theme.pagePadding))
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
                        Button { beginReply(to: comment) } label: { Label { Text("Reply") } icon: { Glyph.comment.regular } }
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
            .overlay {
                if hasLoaded && comments.isEmpty && errorMessage == nil {
                    EmptyState("Nothing here yet", glyph: Glyph.comment, message: "Say something nice about their week.")
                }
            }
            .onChange(of: comments.last?.id) { _, last in
                guard let last, composing || isSending else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private var undoBar: some View {
        HStack(spacing: 10) {
            Text((pendingDelete?.count ?? 1) > 1 ? "Comment and replies deleted" : "Comment deleted")
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
        .overlay(alignment: .top) { Hairline() }
    }

    /// "Replying to maya", with a way out.
    private func replyBanner(_ comment: Comment) -> some View {
        HStack(spacing: 8) {
            Text("Replying to ") .foregroundStyle(.secondary) + Text(comment.author.id == meID ? "yourself" : comment.author.username).bold()
            Spacer()
            Button {
                cancelReply()
            } label: {
                Icon(Glyph.close, weight: .bold, size: 12)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop replying")
        }
        .font(.footnote)
        .padding(.horizontal, Theme.pagePadding)
        .transition(.opacity)
    }

    /// The word being typed, when it starts with @: who to suggest.
    private var mentionQuery: String? {
        guard composing, let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              last.hasPrefix("@"), !last.contains("\n") else { return nil }
        return String(last.dropFirst()).lowercased()
    }

    /// Friends and anyone in this conversation, matching what follows the @.
    private var mentionMatches: [User] {
        guard let query = mentionQuery else { return [] }
        let everyone = people.values.filter { $0.id != meID }.sorted { $0.username < $1.username }
        guard !query.isEmpty else { return Array(everyone.prefix(8)) }
        return Array(everyone.filter { $0.username.hasPrefix(query) || $0.name.lowercased().contains(query) }.prefix(8))
    }

    private var mentionSuggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if mentionMatches.isEmpty {
                    Text("Nobody by that name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(height: 36)
                }
                ForEach(mentionMatches) { person in
                    Button {
                        insertMention(person)
                    } label: {
                        HStack(spacing: 6) {
                            AvatarView(user: person, size: 22)
                            Text(person.username)
                        }
                    }
                    .buttonStyle(.pill(.secondary, size: .small))
                    .accessibilityLabel("Mention \(person.displayName)")
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) { Hairline() }
    }

    /// Everyone a mention can name here, by username: the week's author, the people commenting,
    /// friends, and you.
    private var people: [String: User] {
        var byName: [String: User] = [:]
        for user in taggable { byName[user.username.lowercased()] = user }
        for comment in comments { byName[comment.author.username.lowercased()] = comment.author }
        byName[dump.author.username.lowercased()] = dump.author
        if let me = model.currentUser { byName[me.username.lowercased()] = me }
        return byName
    }

    /// Top comments oldest first, each followed by its replies. A reply whose comment is gone (or
    /// from someone blocked) stands on its own.
    private var threaded: [ThreadItem] {
        let ids = Set(comments.map(\.id))
        let tops = comments.filter { comment in comment.parentID.map { !ids.contains($0) } ?? true }
        var out: [ThreadItem] = []
        for top in tops {
            out.append(ThreadItem(comment: top, isReply: false))
            for reply in comments where reply.parentID == top.id {
                out.append(ThreadItem(comment: reply, isReply: true))
            }
        }
        return out
    }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                if let me = model.currentUser {
                    AvatarView(user: me, size: 34)
                }
                TextField(editing != nil ? "Edit your comment" : replyingTo != nil ? "Add a reply" : "Add a comment", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .focused($composing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                if editing != nil {
                    Button {
                        cancelEditing()
                    } label: {
                        Icon(Glyph.close, weight: .bold, size: 16)
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Theme.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel editing")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
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
        if taggable.isEmpty { taggable = (try? await model.api.taggableUsers()) ?? [] }
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
                let comment = try await model.api.addComment(dumpID: dump.id, body: trimmed, replyingTo: replyingTo?.id)
                withAnimation(.snappy(duration: 0.35)) { comments.append(comment) }
                replyingTo = nil
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
        replyingTo = nil
        editing = comment
        text = comment.body
        composing = true
    }

    /// Answers a comment, starting with an @ for its author unless it is your own.
    private func beginReply(to comment: Comment) {
        editing = nil
        withAnimation(.snappy(duration: 0.2)) { replyingTo = comment }
        let handle = "@\(comment.author.username) "
        if comment.author.id != meID, !text.contains(handle) {
            text = handle + text.trimmingCharacters(in: .whitespaces)
        }
        composing = true
    }

    private func cancelReply() {
        if let replyingTo, text.trimmingCharacters(in: .whitespaces) == "@\(replyingTo.author.username)" { text = "" }
        withAnimation(.snappy(duration: 0.2)) { replyingTo = nil }
    }

    /// Swaps the half-typed @ word for the person's whole username.
    private func insertMention(_ person: User) {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard !words.isEmpty else { return }
        words[words.count - 1] = "@\(person.username)"
        text = words.joined(separator: " ") + " "
        Haptics.light()
    }

    private func cancelEditing() {
        editing = nil
        text = ""
        composing = false
    }

    /// Takes the comment, and its replies, off the list and gives four seconds to undo before
    /// telling the server.
    private func delete(_ comment: Comment) {
        flushPendingDelete()
        let gone = comments.filter { $0.id == comment.id || $0.parentID == comment.id }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            comments.removeAll { gone.map(\.id).contains($0.id) }
            pendingDelete = gone
            if let replyingTo, gone.contains(where: { $0.id == replyingTo.id }) { self.replyingTo = nil }
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
        guard let gone = pendingDelete else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            comments.append(contentsOf: gone)
            comments.sort { $0.createdAt < $1.createdAt }
            pendingDelete = nil
        }
        publishCount()
    }

    private func commitDelete(_ comment: Comment) async {
        if pendingDelete?.first?.id == comment.id {
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
        guard let comment = pendingDelete?.first else { return }
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

/// A comment in the drawer, and whether it sits under another as a reply.
struct ThreadItem: Identifiable {
    let comment: Comment
    let isReply: Bool
    var id: ID { comment.id }
}

/// One comment: face, name and when, the words with any @mentions as links, Reply, and a heart
/// with its count on the right.
struct CommentRow: View {
    let comment: Comment
    let now: Date
    var isMine = false
    var isReply = false
    /// Who an @ can name, by lowercased username. A mention of anyone else stays plain words.
    var people: [String: User] = [:]
    var onOpenProfile: (() -> Void)? = nil
    /// Tapping an @mention.
    var onOpenPerson: ((User) -> Void)? = nil
    var onReply: (() -> Void)? = nil
    let onLike: () -> Void

    private static let mentionScheme = "sundae-mention"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { onOpenProfile?() } label: {
                AvatarView(user: comment.author, size: isReply ? 26 : 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(comment.author.displayName)'s profile")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Button { onOpenProfile?() } label: {
                        Text(isMine ? "you" : comment.author.username)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Text(relativeTime(comment.createdAt, now: now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if comment.editedAt != nil {
                        Text("· Edited")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(Self.attributed(comment.body, people: people))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == Self.mentionScheme, let person = people[url.host() ?? ""] else { return .discarded }
                        onOpenPerson?(person)
                        return .handled
                    })
                if let onReply {
                    Button("Reply", action: onReply)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .accessibilityLabel("Reply to \(comment.author.displayName)")
                }
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
        .accessibilityElement(children: .contain)
    }
}

extension CommentRow {
    /// The words, with each @ of someone known made a link to them. Usernames are letters,
    /// numbers, dots and underscores; a dot that ends a sentence is not part of one.
    static func attributed(_ body: String, people: [String: User]) -> AttributedString {
        var result = AttributedString(body)
        for match in body.matches(of: /@([A-Za-z0-9._]{1,30})/) {
            var name = String(match.output.1).lowercased()
            while name.hasSuffix("."), people[name] == nil { name.removeLast() }
            guard !name.isEmpty, people[name] != nil,
                  let end = body.index(match.range.lowerBound, offsetBy: name.count + 1, limitedBy: body.endIndex),
                  let range = Range(match.range.lowerBound..<end, in: result),
                  let link = URL(string: "\(mentionScheme)://\(name)") else { continue }
            result[range].link = link
            result[range].font = Font.subheadline.weight(.semibold)
        }
        return result
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

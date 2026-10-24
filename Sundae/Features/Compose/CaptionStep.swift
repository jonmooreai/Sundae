import SwiftUI

/// Step three: one caption for the whole week, then post.
struct CaptionStep: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [ComposeStep]
    @FocusState private var captionFocused: Bool

    private var compose: ComposeStore { model.compose }

    var body: some View {
        @Bindable var store = model.compose
        VStack(spacing: 0) {
            FlowHeader(title: "Caption", isRoot: false, onClose: { compose.dismiss() }) { EmptyView() }
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DraftThumbnailStrip(photos: compose.draft.photos)
                    .padding(.horizontal, -Theme.pagePadding)

                Text("How was your week?")
                    .font(Theme.display(34))

                VStack(alignment: .trailing, spacing: 6) {
                    TextField("Say a little about it", text: $store.draft.caption, axis: .vertical)
                        .font(.title3)
                        .lineLimit(3...10)
                        .textFieldStyle(.plain)
                        .focused($captionFocused)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                        .onChange(of: compose.draft.caption) { _, text in
                            if text.count > DumpDraft.maxCaptionLength { compose.setCaption(text) }
                        }
                        .accessibilityIdentifier("caption-field")
                    if compose.draft.caption.count > DumpDraft.maxCaptionLength - 60 {
                        Text("\(compose.draft.caption.count)/\(DumpDraft.maxCaptionLength)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                donePrompt

                Toggle("Allow comments", isOn: $store.draft.commentsEnabled)
                    .font(.subheadline)

                if let message = compose.errorMessage {
                    ErrorBanner(message: message)
                }

                Text("Your dump goes to the top of your friends' feeds and into this week on your profile. Tagged friends get a request to approve.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.pagePadding)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            FlowBottomBar(title: compose.hasPosted ? "Save changes" : "Post your week",
                          isEnabled: compose.canPost, isLoading: compose.isSaving) {
                Task { await post() }
            } leading: {
                Text(compose.draft.caption.isEmpty ? "Caption is optional" : "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if compose.draft.caption.isEmpty { captionFocused = true }
        }
    }

    /// "On Thursday you did: ..." when a weekday suggestion was marked done.
    @ViewBuilder
    private var donePrompt: some View {
        let done = model.weekday.doneThisWeek(clock: model.clock)
        if !compose.hasPosted, let first = done.first {
            let day = model.clock.weekdayName(first.day)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(day): \u{201C}\(first.suggestion.text)\u{201D}")
                    .font(.subheadline.weight(.medium))
                Text("You marked this done. Worth a mention?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
    }

    private func post() async {
        captionFocused = false
        if let dump = await compose.save(weekStart: model.currentWeekStart) {
            model.feed.insertOwn(dump)
            model.shared.postedWeekStart = model.currentWeekStart
            path.append(.posted)
        } else if compose.queuedOffline {
            path.append(.posted)
        }
    }
}

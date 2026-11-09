import SwiftUI
import WidgetKit

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
                DraftThumbnailStrip(photos: compose.draft.photos, side: 72)
                    .padding(.horizontal, -Theme.pagePadding)

                Text("How was your week?")
                    .font(Theme.display(34))

                VStack(alignment: .trailing, spacing: 6) {
                    TextField("Say a little about it", text: $store.draft.caption, axis: .vertical)
                        .font(.title3)
                        .lineLimit(5...10)
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

                // The app's own switch, the same sage as Settings.
                Button {
                    store.draft.commentsEnabled.toggle()
                    Haptics.light()
                } label: {
                    HStack {
                        Text("Allow comments")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        SundaeSwitch(isOn: compose.draft.commentsEnabled)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityRepresentation {
                    Toggle("Allow comments", isOn: $store.draft.commentsEnabled)
                }

                if let message = compose.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(Theme.pagePadding)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .centeredColumn()
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            FlowBottomBar(title: compose.hasPosted ? "Save changes" : "Post your week",
                          isEnabled: compose.canPost, isLoading: compose.isSaving) {
                Task { await post() }
            } leading: {
                EmptyView()
            }
        }
        .overlay {
            // Uploading takes a moment: the week's own photos pile up until it is in.
            if compose.isSaving {
                PostingStack(photos: compose.draft.photos.map(\.source))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: compose.isSaving)
        .onAppear {
            if compose.draft.caption.isEmpty { captionFocused = true }
        }
    }

    /// A caption written from the ideas you finished this week. Editable, often kept.
    @ViewBuilder
    private var donePrompt: some View {
        let done = model.weekday.doneThisWeek(clock: model.clock)
        if !compose.hasPosted, !done.isEmpty, let suggested = Self.caption(from: done.map { $0.suggestion }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(suggested)
                    .font(.subheadline.weight(.medium))
                HStack {
                    Text("From the ideas you did this week.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use it") { compose.setCaption(suggested) }
                        .buttonStyle(.pill(.secondary, size: .small))
                        .disabled(compose.draft.caption == suggested)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
    }

    /// "Tartine, the lookout, and a walk through a neighborhood I didn't know."
    static func caption(from suggestions: [Suggestion]) -> String? {
        let items = suggestions.prefix(4).map { suggestion -> String in
            if let place = suggestion.place { return place.name }
            return shortLabel(suggestion.text)
        }
        guard !items.isEmpty else { return nil }
        let joined = ListFormatter.localizedString(byJoining: items)
        return joined.prefix(1).uppercased() + String(joined.dropFirst()) + "."
    }

    /// The first clause of an idea, lowercased, trimmed to a few words.
    private static func shortLabel(_ text: String) -> String {
        let clause = text.split(whereSeparator: { ".,;:!?".contains($0) }).first.map(String.init) ?? text
        let words = clause.split(separator: " ").prefix(5)
        return words.joined(separator: " ").lowercased()
    }

    private func post() async {
        captionFocused = false
        if let dump = await compose.save(weekStart: model.currentWeekStart) {
            model.feed.insertOwn(dump)
            model.shared.postedWeekStart = model.currentWeekStart
            model.shared.setPostedAssetIDs(compose.postedAssetIDs, weekStart: model.currentWeekStart)
            model.scheduleReminders()
            WidgetCenter.shared.reloadAllTimelines()
            path.append(.posted)
        } else if compose.queuedOffline {
            path.append(.posted)
        }
    }
}

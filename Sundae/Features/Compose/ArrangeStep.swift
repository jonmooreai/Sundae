import SwiftUI

/// Step two: see each photo large, give it a caption, tag the friends who were there, fix the order.
struct ArrangeStep: View {
    @Environment(AppModel.self) private var model
    let library: PhotoLibrary
    @Binding var path: [ComposeStep]

    @State private var page = 0
    @State private var tagging: DraftPhoto?

    /// "Jonah", "Jonah and Lena", "Jonah, Lena and 6 others".
    private func taggedLine(_ users: [User]) -> String {
        let names = users.map(\.firstName)
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) others"
        }
    }
    @State private var altPhoto: DraftPhoto?
    @State private var showReorder = false
    @State private var confirmDelete = false

    private var compose: ComposeStore { model.compose }
    private var photos: [DraftPhoto] { compose.draft.photos }
    private var current: DraftPhoto? { photos.indices.contains(page) ? photos[page] : nil }

    /// The caption of the photo on screen. Photos from one saved idea arrive with the same one.
    private var captionBinding: Binding<String> {
        Binding(get: { current?.caption ?? "" },
                set: { text in if let current { compose.setPhotoCaption(for: current.id, text: text) } })
    }

    var body: some View {
        VStack(spacing: 0) {
            FlowHeader(title: "Arrange and tag", isRoot: path.isEmpty, onClose: { compose.dismiss() }) {
                if compose.hasPosted {
                    Menu {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label { Text("Delete this week") } icon: { Glyph.trash.regular }
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
            if photos.isEmpty {
                empty
            } else {
                content
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !photos.isEmpty {
                FlowBottomBar(title: "Next") {
                    path.append(.caption)
                } leading: {
                    Button {
                        showReorder = true
                    } label: {
                        HStack(spacing: 6) {
                            Icon(Glyph.reorder, size: 18)
                            Text("Reorder")
                        }
                    }
                    .buttonStyle(.pill(.quiet, size: .small))
                    .disabled(photos.count < 2)
                }
            }
        }
        .sheet(item: $tagging) { photo in
            TagPickerSheet(photo: photo, users: compose.taggable) { users in
                compose.setTags(for: photo.id, users: users)
            }
        }
        .sheet(item: $altPhoto) { photo in
            AltTextSheet(photo: photo) { text in compose.setAltText(for: photo.id, text: text) }
        }
        .sheet(isPresented: $showReorder) {
            ReorderSheet()
        }
        .confirmationDialog("Delete this week's dump?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    if let id = await compose.delete() { model.feed.remove(dumpID: id) }
                    compose.dismiss()
                }
            }
        } message: {
            Text("Your photos and any tags on them are removed. Friends keep the photos they posted.")
        }
        .onChange(of: photos.count) { _, count in
            page = min(page, max(0, count - 1))
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 14) {
            TabView(selection: $page) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    PhotoView(source: photo.source)
                        .aspectRatio(min(max(CGFloat(photo.width) / CGFloat(max(photo.height, 1)), 0.8), 1.25), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            // A few faces and a short line, never one chip per person.
                            if !photo.taggedUsers.isEmpty {
                                HStack(spacing: 7) {
                                    FacePile(users: Array(photo.taggedUsers.prefix(3)), size: 20)
                                    Text(taggedLine(photo.taggedUsers))
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .padding(.leading, 5)
                                .padding(.trailing, 10)
                                .padding(.vertical, 5)
                                .background(.regularMaterial, in: Capsule())
                                .padding(12)
                                .frame(maxWidth: 300, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, Theme.pagePadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(index)
                        .accessibilityLabel(photo.altText.isEmpty ? "Photo \(index + 1) of \(photos.count)" : photo.altText)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(0.92, contentMode: .fit)
            .padding(.top, 4)

            HStack {
                Text("\(page + 1) of \(photos.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if let current, let taken = current.takenAt {
                    Text(taken.formatted(.dateTime.weekday(.wide)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.pagePadding)

            TextField("Add a caption (optional)", text: captionBinding, axis: .vertical)
                .lineLimit(1...3)
                .font(.subheadline)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                .padding(.horizontal, Theme.pagePadding)
                .id(current?.id)
                .accessibilityLabel("Caption for photo \(page + 1)")

            HStack(spacing: 10) {
                action(current?.taggedUsers.isEmpty == false ? "Tagged \(current?.taggedUsers.count ?? 0)" : "Tag friends", Glyph.tag) {
                    if let current { tagging = current }
                }
                .accessibilityIdentifier("tag-friends")
                action(current?.altText.isEmpty == false ? "Alt text added" : "Alt text", Glyph.altText) {
                    if let current { altPhoto = current }
                }
                Button {
                    if let current { withAnimation { compose.remove(current.id) } }
                } label: {
                    Icon(Glyph.trash, size: 20)
                        .frame(width: 20)
                }
                .buttonStyle(.pill(.secondary, size: .small))
                .accessibilityLabel("Remove photo")
            }
            .padding(.horizontal, Theme.pagePadding)

            thumbnails

            Text("Tap a photo's Tag friends to add the people who were there.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
    }

    private func action(_ title: String, _ glyph: Ph, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 6) {
                Icon(glyph, size: 18)
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pill(.secondary, size: .small, fullWidth: true))
    }

    private var thumbnails: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    PhotoView(source: photo.source)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(index == page ? Color.accentColor : .clear, lineWidth: 2.5)
                        }
                        .onTapGesture { withAnimation(.snappy) { page = index } }
                        .accessibilityLabel("Photo \(index + 1)")
                }
                if compose.draft.canAddMore {
                    Button {
                        addMore()
                    } label: {
                        Icon(Glyph.plus, weight: .bold, size: 20)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, height: 60)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add more photos")
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .scrollIndicators(.hidden)
        .frame(height: 64)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            PhotoStackIcon(size: 64)
            Text("No photos yet")
                .font(.title3.weight(.semibold))
            PrimaryButton(title: "Add photos") { addMore() }
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Back to the picker when it is already in the chain, otherwise forward to it.
    private func addMore() {
        if compose.entry == .pick {
            path.removeAll()
        } else if let index = path.lastIndex(of: .pick) {
            path.removeSubrange((index + 1)...)
        } else {
            path.append(.pick)
        }
    }
}

import PhotosUI
import UniformTypeIdentifiers
import SwiftUI

/// Step two: see each photo large, edit it, give it a caption, tag the friends who were there,
/// and fix the order by dragging in the strip.
struct ArrangeStep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
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
    @State private var confirmDelete = false
    @State private var showsPhotosPicker = false
    @State private var showsCamera = false
    @State private var editing: DraftPhoto?
    /// The photo being dragged in the strip, shown faint where it will land.
    @State private var dragging: ID?

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
            FlowHeader(title: "Arrange and tag", isRoot: path.isEmpty, onClose: { compose.dismiss() }) { moreMenu }
            if photos.isEmpty {
                empty
            } else {
                content
            }
        }
        .centeredColumn()
        .background(Theme.background)
        .sideBarChrome(close: path.isEmpty ? { compose.dismiss() } : nil) { moreMenu }
        .sideBarPrimaryAction("Next", isEnabled: !photos.isEmpty) { path.append(.caption) }
        .safeAreaInset(edge: .bottom) {
            if !photos.isEmpty {
                FlowBottomBar(title: "Next") {
                    path.append(.caption)
                } leading: {
                    EmptyView()
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
        .fullScreenCover(item: $editing) { photo in
            PhotoEditorView(photo: photo, load: { await compose.editableData(for: photo) }) { edits, rendered in
                compose.applyEdits(to: photo.id, edits: edits, rendered: rendered)
            }
        }
        // A photo whose file says it was made with AI: a gentle card slides up with it, and the
        // choice stays theirs. Swiped away, it stays in.
        .sheet(isPresented: Binding(get: { !compose.madeWithAINudge.isEmpty },
                                    set: { if !$0 { compose.answerMadeWithAINudge(keep: true) } })) {
            MadeWithAINudgeCard(photos: compose.draft.photos.filter { compose.madeWithAINudge.contains($0.id) }) { keep in
                withAnimation { compose.answerMadeWithAINudge(keep: keep) }
            }
            .presentationDetents([.height(360), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.background)
            .presentationCornerRadius(28)
        }
        .confirmationDialog("Delete this week's post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    if let id = await compose.delete() { model.feed.remove(dumpID: id) }
                    compose.dismiss()
                }
            }
        } message: {
            Text("Your photos and any tags on them are removed. Friends keep the photos they posted.")
        }
        // A drag let go anywhere but the strip still ends.
        .onDrop(of: [.text], delegate: EndDrag(dragging: $dragging))
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
                        .aspectRatio(Self.shape(of: photo), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        // On the photo itself, so the Edit button over it stays its own button.
                        .accessibilityElement()
                        .accessibilityLabel(photo.altText.isEmpty ? "Photo \(index + 1) of \(photos.count)" : photo.altText)
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
                        .overlay(alignment: .topLeading) {
                            if photo.madeWithAI {
                                MadeWithAINote().padding(12)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            HStack(spacing: 6) {
                            if Self.canEdit(photo) {
                                Button { editing = photo } label: {
                                    HStack(spacing: 5) {
                                        Icon(Glyph.edit, size: 15)
                                        Text(photo.edits == nil ? "Edit" : "Edited")
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(.regularMaterial, in: Capsule())
                                    .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit photo")
                                .accessibilityIdentifier("edit-photo")
                            }
                            }
                            .padding(12)
                        }
                        .padding(.horizontal, Theme.pagePadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(index)
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

            Spacer(minLength: 0)
        }
    }

    /// Delete, once the week is posted. In the header on a phone, on the side strip on an iPhone Duo.
    @ViewBuilder
    private var moreMenu: some View {
        if compose.hasPosted {
            ChromeMenu {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label { Text("Delete this week") } icon: { Glyph.trash.regular }
                }
            }
        }
    }

    /// A demo placeholder has no pixels to edit; everything else does.
    private static func canEdit(_ photo: DraftPhoto) -> Bool {
        if case .placeholder = photo.original?.source ?? photo.source { return false }
        return true
    }

    /// The photo's own width to height, so the frame is exactly its shape and nothing is cut off.
    private static func shape(of photo: DraftPhoto) -> CGFloat {
        guard photo.width > 0, photo.height > 0 else { return 1 }
        return CGFloat(photo.width) / CGFloat(photo.height)
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

    /// The strip: the photo on screen at full strength, the rest a little quieter. Hold one and
    /// drag: a ghost of it follows the finger, the others slide aside as it passes, and the faint
    /// space left in the strip is where it lands.
    private var thumbnails: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    PhotoView(source: photo.source)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .opacity(dragging == photo.id ? 0.3 : (dragging == nil && index != page ? 0.6 : 1))
                        // The ghost under the finger keeps the thumbnail's rounded corners.
                        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture {
                            dragging = nil
                            withAnimation(.snappy) { page = index }
                        }
                        .onDrag {
                            dragging = photo.id
                            Haptics.light()
                            return NSItemProvider(object: photo.id as NSString)
                        } preview: {
                            PhotoView(source: photo.source)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .onDrop(of: [.text], delegate: StripDrop(target: photo.id, dragging: $dragging) { moved, target in
                            withAnimation(.snappy(duration: 0.25)) { compose.movePhoto(moved, to: target) }
                            if let at = compose.draft.photos.firstIndex(where: { $0.id == moved }) { page = at }
                            Haptics.light()
                        })
                        .accessibilityLabel("Photo \(index + 1)")
                        .accessibilityAction(named: "Move earlier") { move(photo.id, by: -1) }
                        .accessibilityAction(named: "Move later") { move(photo.id, by: 1) }
                }
                if compose.draft.canAddMore {
                    Menu {
                        addChoices
                    } label: {
                        Icon(Glyph.plus, weight: .bold, size: 20)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, height: 60)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityLabel("Add more photos")
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .animation(.snappy(duration: 0.25), value: photos.map(\.id))
        }
        .scrollIndicators(.hidden)
        .frame(height: 68)
        .photoSources(compose: compose, showsPicker: $showsPhotosPicker, showsCamera: $showsCamera)
    }

    /// One place earlier or later, for VoiceOver, where dragging is hard.
    private func move(_ id: ID, by step: Int) {
        guard let from = photos.firstIndex(where: { $0.id == id }), photos.indices.contains(from + step) else { return }
        compose.movePhoto(id, to: photos[from + step].id)
        page = from + step
    }

    private var empty: some View {
        VStack(spacing: 16) {
            PhotoStackIcon(size: 64)
            Text("No photos yet")
                .font(.title3.weight(.semibold))
            PrimaryButton(title: "Add this week's photos") { addMore() }
                .padding(.horizontal, 40)
            VStack(spacing: 4) {
                Button("Choose from Photos") { showsPhotosPicker = true }
                    .buttonStyle(.pill(.quiet))
                if CameraCapture.isAvailable {
                    Button("Take a photo") { showsCamera = true }
                        .buttonStyle(.pill(.quiet))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .photoSources(compose: compose, showsPicker: $showsPhotosPicker, showsCamera: $showsCamera)
    }

    /// Where more photos can come from: the week's grid, any album, or the camera.
    @ViewBuilder
    private var addChoices: some View {
        Button { addMore() } label: { Label { Text("This week's photos") } icon: { Glyph.calendar.regular } }
        Button { showsPhotosPicker = true } label: { Label { Text("Choose from Photos") } icon: { Glyph.photos.regular } }
        if CameraCapture.isAvailable {
            Button { showsCamera = true } label: { Label { Text("Take a photo") } icon: { Glyph.camera.regular } }
        }
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

/// A photo in the strip, as one being dragged passes over it: the dragged one takes its place
/// there and then, so the strip shows where it will land. A move, so no plus badge.
private struct StripDrop: DropDelegate {
    let target: ID
    @Binding var dragging: ID?
    let move: @MainActor (ID, ID) -> Void

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let moved = dragging, moved != target else { return }
            move(moved, target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { dragging = nil }
        return true
    }
}

/// Anywhere else on the screen: a drag let go outside the strip ends, the photo where it last was.
private struct EndDrag: DropDelegate {
    @Binding var dragging: ID?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { dragging = nil }
        return true
    }
}

/// The card that slides up when a photo made with AI joins the post: the photo itself, a
/// gentle word, and the choice.
private struct MadeWithAINudgeCard: View {
    let photos: [DraftPhoto]
    let answer: (_ keep: Bool) -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: -14) {
                ForEach(Array(photos.prefix(3).enumerated()), id: \.element.id) { index, photo in
                    PhotoView(source: photo.source)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.background, lineWidth: 3)
                        }
                        .rotationEffect(.degrees(photos.count > 1 ? Double(index - 1) * 5 : 0))
                        .zIndex(Double(index))
                }
                if photos.count > 3 {
                    Text("+\(photos.count - 3)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 22)
                }
            }
            .padding(.top, 18)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(photos.count == 1 ? "This one looks made with AI" : "These look made with AI")
                    .font(Theme.display(22))
                    .multilineTextAlignment(.center)
                Text("Sundae is for your real week, the things you actually saw and did. Friends will see a small Made with AI note on it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Keep") { answer(true) }
                    .buttonStyle(.pill(.secondary, fullWidth: true))
                Button(photos.count == 1 ? "Take it out" : "Take them out") { answer(false) }
                    .buttonStyle(.pill(.primary, fullWidth: true))
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 12)
        .frame(maxWidth: Theme.actionsWidth + 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

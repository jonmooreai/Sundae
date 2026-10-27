import SwiftUI

/// Horizontally paged photos with a page indicator. Tag chips appear on tap, not by default,
/// so photos stay clean. The aspect ratio follows the first photo, clamped so a feed of mixed
/// portrait and landscape shots stays scannable.
struct PhotoCarousel: View {
    let photos: [Photo]
    @Binding var index: Int
    var cornerRadius: CGFloat = 0
    /// Called with the photo's position when a photo is tapped. Without it a tap toggles the tag chips.
    var onTap: ((Int) -> Void)? = nil
    /// Called on a double tap, which also pops a heart over the photo.
    var onDoubleTap: (() -> Void)? = nil
    /// What a tapped person chip does. Inside a navigation stack with Route destinations,
    /// `tagsLinkToProfiles` pushes the profile instead.
    var onTapTag: ((User) -> Void)? = nil
    var tagsLinkToProfiles = false
    /// A long press gives the photo the viewer's cherry, or takes it back: the photo and whether
    /// it is cherried now. Without it there are no cherries to give.
    var onCherry: ((Photo, Bool) -> Void)? = nil

    @State private var showTags = false
    @State private var burst = 0
    @State private var cherryBurst = 0
    /// The photo whose cherries are listed, who gave them.
    @State private var cherriesOf: Photo?
    @State private var screenFrame = ScreenFrame()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PhotoZoom.self) private var zoom: PhotoZoom?

    private var aspect: CGFloat {
        min(max(photos.first?.aspectRatio ?? 1, 0.8), 1.5)
    }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                ZStack(alignment: .bottomLeading) {
                    PhotoView(source: photo.source)
                    if !photo.visibleTags.isEmpty {
                        // The badge stays put; the people stack up above it, clear of the page dots.
                        VStack(alignment: .leading, spacing: 6) {
                            if showTags {
                                TagChips(tags: photo.visibleTags, linksToProfiles: tagsLinkToProfiles, onTap: onTapTag)
                            }
                            Button(action: toggleTags) { TagBadge(isOpen: showTags) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(showTags ? "Hide tagged friends" : "Show tagged friends")
                        }
                        .padding(10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if photo.cherryCount > 0 {
                        Button { cherriesOf = photo } label: {
                            CherryPile(count: photo.cherryCount)
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .accessibilityLabel(photo.cherryCount == 1 ? "1 cherry" : "\(photo.cherryCount) cherries")
                        .accessibilityHint("Shows who sent them")
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .bouncy(duration: 0.35), value: photo.cherryCount)
                .contentShape(Rectangle())
                .pinchToZoom(photo.source, frame: { screenFrame.rect }, cornerRadius: cornerRadius,
                             zoom: zoom, reduceMotion: reduceMotion)
                // Declared first so two quick taps read as one double tap, not two singles.
                .onTapGesture(count: 2) { doubleTap() }
                .onTapGesture { singleTap() }
                .onLongPressGesture(minimumDuration: 0.4) { cherry(photo) }
                .tag(offset)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: photo, position: offset))
                .accessibilityAddTraits(onTap == nil ? AccessibilityTraits() : .isButton)
                .accessibilityAction { if let onTap { onTap(offset) } else { toggleTags() } }
                .accessibilityAction(named: "Show tagged friends") { toggleTags() }
                .accessibilityAction(named: photo.cherriedByMe ? "Take back your cherry" : "Give a cherry") { cherry(photo) }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in screenFrame.rect = rect }
        .overlay {
            if burst > 0 {
                HeartBurst().id(burst).transition(.opacity)
            }
            if cherryBurst > 0 {
                CherryBurst().id(cherryBurst).transition(.opacity)
            }
        }
        .sheet(item: $cherriesOf) { photo in
            CherriesSheet(photo: photo)
        }
        .transaction { t in if reduceMotion { t.animation = nil } }
    }

    private func singleTap() {
        if let onTap { onTap(index) } else { toggleTags() }
    }

    private func doubleTap() {
        guard let onDoubleTap else { singleTap(); return }
        onDoubleTap()
        burst += 1
        let shown = burst
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard burst == shown else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { burst = 0 }
        }
    }

    /// A long press: the viewer's cherry, given with a pop and a squeak, or quietly taken back.
    private func cherry(_ photo: Photo) {
        guard let onCherry else { return }
        let giving = !photo.cherriedByMe
        onCherry(photo, giving)
        guard giving else {
            Haptics.light()
            return
        }
        Haptics.success()
        CherrySound.play()
        cherryBurst += 1
        let shown = cherryBurst
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard cherryBurst == shown else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { cherryBurst = 0 }
        }
    }

    private func toggleTags() {
        withAnimation(reduceMotion ? nil : .bouncy(duration: 0.35)) { showTags.toggle() }
    }

    private func accessibilityLabel(for photo: Photo, position: Int) -> String {
        var parts: [String] = ["Photo \(position + 1) of \(photos.count)"]
        if let caption = photo.caption, !caption.isEmpty { parts.append(caption) }
        if let alt = photo.altText, !alt.isEmpty { parts.append(alt) }
        let names = photo.visibleTags.map(\.taggedUser.displayName)
        if !names.isEmpty { parts.append("with " + ListFormatter.localizedString(byJoining: names)) }
        return parts.joined(separator: ". ")
    }
}

/// The caption of the photo being looked at, under the photos. It changes as they are swiped,
/// and takes no room when a photo has none.
struct PhotoCaptionLine: View {
    let photos: [Photo]
    let page: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let caption = photos.indices.contains(page) ? (photos[page].caption ?? "") : ""
        Group {
            if !caption.isEmpty {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(caption)
                    .transition(.opacity)
                    // Read with the photo itself, so VoiceOver does not say it twice.
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: caption)
    }
}

/// The big heart that pops over a photo on a double tap.
private struct HeartBurst: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Icon(Glyph.heart, weight: .fill, size: 96)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
            .scaleEffect(shown ? 1 : 0.5)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(reduceMotion ? nil : .bouncy(duration: 0.4)) { shown = true } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The felt cherry that drops onto a photo when you give it one.
private struct CherryBurst: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image("Cherry")
            .resizable()
            .scaledToFit()
            .frame(width: 112)
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .rotationEffect(.degrees(shown ? -8 : 14))
            .scaleEffect(shown ? 1 : 0.4)
            .offset(y: shown ? 0 : -40)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(reduceMotion ? nil : .bouncy(duration: 0.45, extraBounce: 0.15)) { shown = true } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Up to three little cherries in a heap, and how many there are, in a photo's corner.
struct CherryPile: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: -10) {
                ForEach(0..<min(count, 3), id: \.self) { index in
                    Image("Cherry")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees([-14, 8, -4][index]))
                        .offset(y: index == 1 ? -2 : 0)
                }
            }
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.55), in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Who gave a photo a cherry, oldest first.
struct CherriesSheet: View {
    let photo: Photo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cherries").font(Theme.display(26))
                Spacer()
                IconButton(glyph: Glyph.close, label: "Close", size: 20) { dismiss() }
                    .padding(.trailing, -8)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(photo.cherriedBy) { person in
                        UserRow(user: person, title: person.displayName, subtitle: person.handle)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            Text("Long-press a photo to give it a cherry. Long-press again to take it back.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 12)
        }
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }
}

/// The people in a photo, one chip each, stacked above the badge and left aligned. They rise
/// into place one after another from the badge upward, and fade out the same way.
struct TagChips: View {
    let tags: [Tag]
    var linksToProfiles = false
    var onTap: ((User) -> Void)? = nil

    var body: some View {
        ForEach(Array(tags.enumerated()), id: \.element.id) { position, tag in
            // The last chip sits next to the badge; the first is at the top of the fan.
            let rank = tags.count - 1 - position
            chip(tag)
                .transition(.asymmetric(
                    insertion: .modifier(active: FanStep(angle: 0, lift: 12, opacity: 0),
                                         identity: FanStep(angle: 0, lift: 0, opacity: 1))
                        .animation(.easeOut(duration: 0.3).delay(Double(rank) * 0.05)),
                    removal: .modifier(active: FanStep(angle: 0, lift: 8, opacity: 0),
                                       identity: FanStep(angle: 0, lift: 0, opacity: 1))
                        .animation(.easeIn(duration: 0.12))))
        }
    }

    @ViewBuilder
    private func chip(_ tag: Tag) -> some View {
        if linksToProfiles {
            NavigationLink(value: Route.profile(tag.taggedUser.id)) { TagChip(tag: tag) }
                .buttonStyle(.plain)
        } else if let onTap {
            Button { onTap(tag.taggedUser) } label: { TagChip(tag: tag) }
                .buttonStyle(.plain)
        } else {
            TagChip(tag: tag)
        }
    }
}

/// One step of the fan: a chip pivots up from its bottom-left corner into place.
private struct FanStep: ViewModifier {
    let angle: Double
    let lift: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle), anchor: .bottomLeading)
            .offset(y: lift)
            .opacity(opacity)
    }
}

/// One person: their face and first name on a frosted capsule.
struct TagChip: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 6) {
            AvatarView(user: tag.taggedUser, size: 18)
            Text(tag.taggedUser.firstName)
            if tag.status == .pending {
                Text("pending").foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.leading, 4)
        .padding(.trailing, 9)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .accessibilityLabel(tag.taggedUser.displayName + (tag.status == .pending ? ", pending" : ""))
    }
}

/// A small floating tag in the corner of a photo that has people in it. Tap it to see who.
struct TagBadge: View {
    var size: CGFloat = 26
    var isOpen = false

    var body: some View {
        Icon(Glyph.tag, weight: isOpen ? .fill : .bold, size: size * 0.52)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.black.opacity(0.55), in: Circle())
            .accessibilityLabel("Tagged friends")
    }
}

/// "from Maya" attribution on a tagged photo in a profile row.
struct AttributionChip: View {
    let user: User

    var body: some View {
        Text("from \(user.firstName)")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding(6)
    }
}

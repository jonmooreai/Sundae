import SwiftUI

/// Horizontally paged photos with a page indicator. Tag chips appear on tap, not by default,
/// so photos stay clean. Every photo shows whole, never cut off: the frame takes the shape of the
/// tallest photo (no taller than 3:4, no wider than 3:2, so the feed stays scannable), and any
/// photo of another shape sits inside it with black bars.
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

    @State private var showTags = false
    /// Captions float over the photos until a tap puts them away; another tap brings them back.
    @State private var captionsHidden = false
    @State private var burst = 0
    @State private var screenFrame = ScreenFrame()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(PhotoZoom.self) private var zoom: PhotoZoom?

    /// The shape of the tallest photo, within limits. On a phone turned on its side the frame is
    /// wide (16:10 or wider), so a post is never twice the height of the screen.
    private var aspect: CGFloat {
        let tallest = photos.map(\.aspectRatio).min() ?? 1
        if verticalSizeClass == .compact { return max(1.6, min(tallest, 1.8)) }
        return min(max(tallest, 0.75), 1.5)
    }

    private var hasCaptions: Bool { photos.contains { !($0.caption ?? "").isEmpty } }

    /// Soft corners where a post floats in a column with room on either side (regular width: the
    /// Duo open, an iPad); square on a phone, where the photos run edge to edge.
    static func radius(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .regular ? 14 : 0
    }

    /// A little above the page dots, or near the foot when there is only one photo and no dots.
    private var captionLift: CGFloat { photos.count > 1 ? 36 : 14 }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                page(photo, at: offset)
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
        }
        .transaction { t in if reduceMotion { t.animation = nil } }
    }

    /// One page: the photo with its gestures and what VoiceOver hears.
    private func page(_ photo: Photo, at offset: Int) -> some View {
        face(photo)
            .contentShape(Rectangle())
            .pinchToZoom(photo.source, frame: { screenFrame.rect }, cornerRadius: cornerRadius,
                         zoom: zoom, reduceMotion: reduceMotion)
            // Declared first so two quick taps read as one double tap, not two singles.
            .onTapGesture(count: 2) { doubleTap() }
            .onTapGesture { singleTap() }
            .tag(offset)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: photo, position: offset))
            .accessibilityAddTraits(onTap == nil ? AccessibilityTraits() : .isButton)
            .accessibilityAction { if let onTap { onTap(offset) } else { toggleTags() } }
            .accessibilityAction(named: "Show tagged friends") { toggleTags() }
    }

    /// The photo, its caption and its tags.
    private func face(_ photo: Photo) -> some View {
        ZStack(alignment: .bottomLeading) {
            PhotoView(source: photo.source, contentMode: .fit)
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
        .overlay(alignment: .bottom) {
            if let caption = photo.caption, !caption.isEmpty, !captionsHidden {
                FloatingCaption(text: caption)
                    .padding(.horizontal, 16)
                    .padding(.bottom, captionLift)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .offset(y: 18)))
            }
        }
    }

    /// With captions, a tap puts them away or brings them back. Without, it opens the post (in
    /// the feed) or shows who is tagged.
    private func singleTap() {
        if hasCaptions {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.3)) { captionsHidden.toggle() }
        } else if let onTap {
            onTap(index)
        } else {
            toggleTags()
        }
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

/// A photo's caption floating over it: white on soft black, hugging its words up to a width and
/// wrapping past it. A pill when it fits on one line, a rounded card when it wraps. Read with
/// the photo itself, so VoiceOver does not say it twice.
struct FloatingCaption: View {
    let text: String
    static let maxWidth: CGFloat = 300
    private static let fill = Color.black.opacity(0.55)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            label
                .lineLimit(1)
                .fixedSize()
                .background(Self.fill, in: Capsule())
            label
                .fixedSize(horizontal: false, vertical: true)
                .background(Self.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: Self.maxWidth)
        .accessibilityHidden(true)
    }

    private var label: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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

import SwiftUI
import PhosphorSwift

/// Horizontally paged photos with a page indicator. Tag chips appear on tap, not by default,
/// so photos stay clean. The aspect ratio follows the first photo, clamped so a feed of mixed
/// portrait and landscape shots stays scannable.
struct PhotoCarousel: View {
    let photos: [Photo]
    @Binding var index: Int
    var cornerRadius: CGFloat = 0

    @State private var showTags = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var aspect: CGFloat {
        min(max(photos.first?.aspectRatio ?? 1, 0.8), 1.5)
    }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                ZStack(alignment: .bottomLeading) {
                    PhotoView(source: photo.source)
                    if showTags, !photo.visibleTags.isEmpty {
                        TagChipRow(tags: photo.visibleTags)
                            .padding(10)
                            .transition(.opacity)
                    }
                }
                .tag(offset)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: photo, position: offset))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { showTags.toggle() }
        }
        .transaction { t in if reduceMotion { t.animation = nil } }
    }

    private func accessibilityLabel(for photo: Photo, position: Int) -> String {
        var parts: [String] = ["Photo \(position + 1) of \(photos.count)"]
        if let alt = photo.altText, !alt.isEmpty { parts.append(alt) }
        let names = photo.visibleTags.map(\.taggedUser.displayName)
        if !names.isEmpty { parts.append("with " + ListFormatter.localizedString(byJoining: names)) }
        return parts.joined(separator: ". ")
    }
}

struct TagChipRow: View {
    let tags: [Tag]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags) { tag in
                HStack(spacing: 4) {
                    Icon(Glyph.tag, size: 12)
                    Text(tag.taggedUser.firstName)
                    if tag.status == .pending {
                        Text("pending").foregroundStyle(.secondary)
                    }
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
            }
        }
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

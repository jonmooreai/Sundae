import SwiftUI

/// One photo, edge to edge, with its caption and tags. Space or a long press opens it;
/// a swipe down or the close button dismisses.
struct FullScreenPhotoView: View {
    let photo: Photo
    let caption: String

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                PhotoView(source: photo.source)
                    .aspectRatio(photo.aspectRatio, contentMode: .fit)
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in scale = min(max(value.magnification, 1), 4) }
                            .onEnded { _ in withAnimation(.snappy) { scale = 1 } }
                    )
                    .accessibilityLabel(photo.altText ?? "Photo")
                VStack(alignment: .leading, spacing: 6) {
                    if !caption.isEmpty {
                        Text(caption).font(.subheadline).foregroundStyle(.white)
                    }
                    if !photo.visibleTags.isEmpty {
                        Text("with " + ListFormatter.localizedString(byJoining: photo.visibleTags.map(\.taggedUser.firstName)))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                Spacer(minLength: 0)
            }
            Button {
                dismiss()
            } label: {
                Icon(Glyph.close, weight: .bold, size: 18)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Close")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .statusBarHidden()
    }
}

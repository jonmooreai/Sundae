import SwiftUI
import PhosphorSwift

/// The app's mark: the felt cherry from the app icon. A picture, not a drawing, so it keeps its
/// wool texture; the image is square with the cherry centered, so any size frames it the same.
struct CherryMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image("Cherry")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Tap the cherry and it wobbles. Nothing happens otherwise; that is the point.
private struct WobbleOnTap: ViewModifier {
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: taps) { view, angle in
                view.rotationEffect(.degrees(angle), anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-12, duration: 0.10)
                    CubicKeyframe(9, duration: 0.12)
                    CubicKeyframe(-5, duration: 0.10)
                    CubicKeyframe(2, duration: 0.08)
                    CubicKeyframe(0, duration: 0.10)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !reduceMotion else { return }
                Haptics.light()
                taps += 1
            }
    }
}

extension View {
    func wobbleOnTap() -> some View { modifier(WobbleOnTap()) }
}

/// Three fanned, rounded photo cards. Used where the app asks for photos.
struct PhotoStackIcon: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            card.rotationEffect(.degrees(-10)).offset(x: -size * 0.16, y: size * 0.04)
            card.rotationEffect(.degrees(8)).offset(x: size * 0.16, y: size * 0.02)
            card.overlay {
                Icon(Glyph.photos, size: size * 0.36)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size * 1.5, height: size * 1.2)
        .accessibilityHidden(true)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
            .fill(Theme.surfaceRaised)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .frame(width: size * 0.78, height: size * 0.98)
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }
}

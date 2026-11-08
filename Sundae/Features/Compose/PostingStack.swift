import SwiftUI

/// While a week goes up: its own photos, one by one, landing on a little pile like Polaroids,
/// each in a white frame at its own slight angle with a soft shadow. When the pile is done it
/// starts again until the post is in. With Reduce Motion the pile simply sits there.
struct PostingStack: View {
    let photos: [PhotoSource]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    /// Enough to make a pile, few enough to keep it quick.
    private var shown: [PhotoSource] { Array(photos.prefix(8)) }
    private static let gap = 0.55
    private static let land = 0.5
    private static let hold = 1.4
    private var cycle: Double { Double(max(shown.count, 1)) * Self.gap + Self.land + Self.hold }

    var body: some View {
        VStack(spacing: 36) {
            if reduceMotion {
                pile(time: Double(shown.count) * Self.gap + Self.land)
            } else {
                TimelineView(.animation) { context in
                    pile(time: context.date.timeIntervalSince(started).truncatingRemainder(dividingBy: cycle))
                }
            }
            VStack(spacing: 6) {
                Text("Sending your week\u{2026}")
                    .font(Theme.display(24))
                Text(photos.count == 1 ? "Your photo is on its way to your friends." : "Your \(photos.count) photos are on their way to your friends.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sending your week")
    }

    /// The pile `time` seconds into a round: each photo drops in after the one before.
    private func pile(time: Double) -> some View {
        let fade = time > cycle - 0.35 ? max(0, (cycle - time) / 0.35) : 1
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, photo in
                let landed = Self.progress(time - Double(index) * Self.gap)
                Polaroid(source: photo)
                    .rotationEffect(.degrees(Self.angle(index) + 10 * (1 - landed)))
                    .offset(x: Self.drift(index), y: -CGFloat(index) * 1.5 - CGFloat(40 * (1 - landed)))
                    .scaleEffect(CGFloat(1 + 0.18 * (1 - landed)))
                    .opacity(min(1, landed * 2.5))
            }
        }
        .frame(width: 250, height: 280)
        .opacity(fade)
    }

    /// 0 before its turn, easing to 1 as it lands, with a touch of settle at the end.
    private static func progress(_ elapsed: Double) -> Double {
        let p = min(1, max(0, elapsed / land))
        return 1 - pow(1 - p, 3)
    }

    /// A slight, different lean for each, never the same twice in a row.
    private static func angle(_ index: Int) -> Double {
        [-5, 4, -2, 6, -4, 3, -6, 2][index % 8]
    }

    private static func drift(_ index: Int) -> CGFloat {
        [-6, 8, -3, 5, -8, 4, 0, -5][index % 8]
    }
}

/// One photo in a white frame, deeper at the foot, with a soft shadow under it.
private struct Polaroid: View {
    let source: PhotoSource

    var body: some View {
        PhotoView(source: source)
            .frame(width: 196, height: 196)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 38, trailing: 10))
            .background(Color.white, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
    }
}

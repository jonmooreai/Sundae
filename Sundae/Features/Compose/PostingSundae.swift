import SwiftUI

/// While a week goes up: a sundae builds itself, scoop by scoop, sprinkles, then the cherry, and
/// starts again until the post is in. With Reduce Motion it simply stands there, finished.
struct PostingSundae: View {
    var photoCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    private static let cycle: Double = 3.4
    private static let lines = ["Scooping up your week\u{2026}", "Adding the sprinkles\u{2026}", "A cherry on top\u{2026}"]

    var body: some View {
        VStack(spacing: 28) {
            if reduceMotion {
                SundaeBuild(time: 2.6)
                Text("Sending your week\u{2026}")
                    .font(Theme.display(24))
            } else {
                TimelineView(.animation) { context in
                    let elapsed = context.date.timeIntervalSince(started)
                    let time = elapsed.truncatingRemainder(dividingBy: Self.cycle)
                    let round = Int(elapsed / Self.cycle)
                    VStack(spacing: 28) {
                        SundaeBuild(time: time)
                        Text(Self.lines[round % Self.lines.count])
                            .font(Theme.display(24))
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: round)
                    }
                }
            }
            Text(photoCount == 1 ? "Sending your photo to your friends." : "Sending your \(photoCount) photos to your friends.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Posting your week")
    }
}

/// One moment of the sundae going together, `time` seconds into the build.
private struct SundaeBuild: View {
    let time: Double

    private let vanilla = Color(red: 0.98, green: 0.93, blue: 0.80)
    private let strawberry = Color(red: 0.96, green: 0.70, blue: 0.73)
    private let mint = Color(red: 0.73, green: 0.85, blue: 0.71)
    private let glass = Color(red: 0.90, green: 0.80, blue: 0.68)
    private let sprinkleColors: [Color] = [Theme.cherry, Color(red: 0.93, green: 0.76, blue: 0.40),
                                           Color(red: 0.62, green: 0.74, blue: 0.86), Color(red: 0.73, green: 0.85, blue: 0.71)]

    /// 0 before `start`, rising to 1 over `length`, overshooting a touch as it lands.
    private func drop(_ start: Double, _ length: Double = 0.45) -> Double {
        let p = min(1, max(0, (time - start) / length))
        guard p > 0 else { return 0 }
        let c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
    }

    /// Everything fades together at the end of a round, before the next begins.
    private var fade: Double { time > 3.05 ? max(0, 1 - (time - 3.05) / 0.3) : 1 }

    var body: some View {
        ZStack {
            scoop(vanilla, x: -26, y: 18, at: 0.25)
            scoop(strawberry, x: 26, y: 18, at: 0.75)
            scoop(mint, x: 0, y: -24, at: 1.25)
            bowl
            sprinkles
            cherry
        }
        .frame(width: 200, height: 220)
        .opacity(fade)
    }

    private func scoop(_ color: Color, x: CGFloat, y: CGFloat, at start: Double) -> some View {
        let landed = drop(start)
        return Circle()
            .fill(color)
            .overlay(alignment: .topLeading) {
                // A little light on the scoop.
                Circle().fill(.white.opacity(0.45)).frame(width: 14, height: 14).offset(x: 14, y: 12)
            }
            .frame(width: 66, height: 66)
            .scaleEffect(x: 1, y: landed > 0.95 ? 1 : CGFloat(0.94 + 0.06 * landed), anchor: .bottom)
            .offset(x: x, y: y - CGFloat(150 * (1 - landed)))
            .opacity(min(1, landed * 3))
    }

    private var bowl: some View {
        VStack(spacing: 0) {
            UnevenRoundedRectangle(bottomLeadingRadius: 46, bottomTrailingRadius: 46, style: .continuous)
                .fill(glass)
                .frame(width: 132, height: 52)
            Capsule().fill(glass).frame(width: 18, height: 22)
            Capsule().fill(glass).frame(width: 64, height: 10)
        }
        .offset(y: 72)
    }

    private var sprinkles: some View {
        let shown = min(1, max(0, (time - 1.8) / 0.25))
        let spots: [(CGFloat, CGFloat, Double)] = [(-34, 4, 20), (-14, -2, -35), (18, 6, 50), (36, 0, -15),
                                                   (-10, -44, 60), (10, -36, -50), (-2, -52, 10), (22, -20, 75)]
        return ZStack {
            ForEach(Array(spots.enumerated()), id: \.offset) { index, spot in
                Capsule()
                    .fill(sprinkleColors[index % sprinkleColors.count])
                    .frame(width: 4, height: 11)
                    .rotationEffect(.degrees(spot.2))
                    .offset(x: spot.0, y: spot.1)
                    .scaleEffect(CGFloat(shown))
            }
        }
        .opacity(shown)
    }

    private var cherry: some View {
        let landed = drop(2.1, 0.5)
        return CherryMark(size: 40)
            .offset(y: CGFloat(-70 - 160 * (1 - landed)))
            .opacity(min(1, landed * 3))
    }
}

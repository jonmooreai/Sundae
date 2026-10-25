import SwiftUI
import PhosphorSwift

/// The app's mark: a line-drawn sundae with a red cherry. Drawn in code so it scales to any
/// size and follows the text color in light and dark mode.
struct SundaeMark: View {
    var size: CGFloat = 32
    var lineWidth: CGFloat = 1.6
    /// 0 is a sundae. 1 is a puddle with a cherry on top. Late Sunday nights drift between.
    var melt: Double = 0
    /// A small candle on birthdays.
    var candle = false

    private let cherry = Theme.cherry

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 100
            let m = min(max(melt, 0), 1)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let style = StrokeStyle(lineWidth: lineWidth * max(1, s), lineCap: .round, lineJoin: .round)
            let line = GraphicsContext.Shading.color(.primary)
            let fill = GraphicsContext.Shading.color(Theme.background)

            // The puddle comes first so everything else sits on it.
            if m > 0 {
                let width = 30 + 50 * m
                let puddle = Path(ellipseIn: CGRect(x: (50 - width / 2) * s, y: (93 - 3 * m) * s, width: width * s, height: (5 + 6 * m) * s))
                context.fill(puddle, with: fill)
                context.stroke(puddle, with: line, style: style)
            }

            var cup = Path()
            cup.move(to: p(24, 50 + 8 * m))
            cup.addLine(to: p(76, 50 + 8 * m))
            cup.addLine(to: p(64 + 4 * m, 82 + 4 * m))
            cup.addQuadCurve(to: p(36 - 4 * m, 82 + 4 * m), control: p(50, 92 + 2 * m))
            cup.closeSubpath()
            context.fill(cup, with: fill)
            context.stroke(cup, with: line, style: style)

            var base = Path()
            base.move(to: p(50, 86 + 4 * m))
            base.addLine(to: p(50, 94))
            base.move(to: p(37, 95))
            base.addLine(to: p(63, 95))
            context.stroke(base, with: line, style: style)

            // Scoops sag and spread as they melt.
            for center in [(36.0, 44.0), (64.0, 44.0), (50.0, 32.0)] {
                let r: CGFloat = 15
                let sag = (center.1 == 32 ? 14.0 : 8.0) * m
                let rect = CGRect(x: (center.0 - r - 3 * m) * s, y: (center.1 - r + sag) * s,
                                  width: 2 * (r + 3 * m) * s, height: 2 * (r - 5 * m) * s)
                let scoop = Path(ellipseIn: rect)
                context.fill(scoop, with: fill)
                context.stroke(scoop, with: line, style: style)
            }

            let cherryY = 7 + 16 * m
            let cherryPath = Path(ellipseIn: CGRect(x: 45 * s, y: cherryY * s, width: 10 * s, height: 10 * s))
            context.fill(cherryPath, with: .color(cherry))
            var stem = Path()
            stem.move(to: p(50, cherryY))
            stem.addQuadCurve(to: p(57, cherryY - 6), control: p(51, cherryY - 5))
            context.stroke(stem, with: line, style: style)

            if candle {
                var wick = Path()
                wick.move(to: p(66, 30))
                wick.addLine(to: p(66, 12))
                context.stroke(wick, with: line, style: StrokeStyle(lineWidth: lineWidth * 1.6 * max(1, s), lineCap: .round))
                let flame = Path(ellipseIn: CGRect(x: 63 * s, y: 2 * s, width: 6 * s, height: 9 * s))
                context.fill(flame, with: .color(Color(red: 0.98, green: 0.72, blue: 0.25)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The mark as the day decides: melting through late Sunday night, a candle on your birthday.
/// Checks once a minute, so the drift is slow enough to doubt.
struct LivingSundaeMark: View {
    var size: CGFloat = 32
    let clock: SundayClock

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            SundaeMark(size: size,
                       melt: Self.melt(at: now, clock: clock),
                       candle: MomentMemory.isBirthday(now, calendar: clock.calendar))
        }
    }

    /// From nine on a Sunday evening the sundae softens; by midnight it is a puddle.
    static func melt(at date: Date, clock: SundayClock) -> Double {
        guard clock.isSunday(date) else { return 0 }
        let minutes = Double(clock.calendar.component(.hour, from: date) * 60 + clock.calendar.component(.minute, from: date))
        let start = 21.0 * 60
        guard minutes >= start else { return 0 }
        return min(1, (minutes - start) / (3 * 60 - 5))
    }
}

/// Tap the sundae and it wobbles, cherry and all. Nothing happens otherwise; that is the point.
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

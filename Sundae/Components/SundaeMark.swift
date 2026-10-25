import SwiftUI
import PhosphorSwift

/// The app's mark: a line-drawn sundae with a red cherry. Drawn in code so it scales to any
/// size and follows the text color in light and dark mode.
struct SundaeMark: View {
    var size: CGFloat = 32
    var lineWidth: CGFloat = 1.6

    private let cherry = Theme.cherry

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 100
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let style = StrokeStyle(lineWidth: lineWidth * max(1, s), lineCap: .round, lineJoin: .round)
            let line = GraphicsContext.Shading.color(.primary)
            let fill = GraphicsContext.Shading.color(Theme.background)

            var cup = Path()
            cup.move(to: p(24, 50))
            cup.addLine(to: p(76, 50))
            cup.addLine(to: p(64, 82))
            cup.addQuadCurve(to: p(36, 82), control: p(50, 92))
            cup.closeSubpath()
            context.fill(cup, with: fill)
            context.stroke(cup, with: line, style: style)

            var base = Path()
            base.move(to: p(50, 86))
            base.addLine(to: p(50, 94))
            base.move(to: p(37, 95))
            base.addLine(to: p(63, 95))
            context.stroke(base, with: line, style: style)

            for center in [(36.0, 44.0), (64.0, 44.0), (50.0, 32.0)] {
                let r: CGFloat = 15
                let rect = CGRect(x: (center.0 - r) * s, y: (center.1 - r) * s, width: 2 * r * s, height: 2 * r * s)
                let scoop = Path(ellipseIn: rect)
                context.fill(scoop, with: fill)
                context.stroke(scoop, with: line, style: style)
            }

            let cherryPath = Path(ellipseIn: CGRect(x: 45 * s, y: 7 * s, width: 10 * s, height: 10 * s))
            context.fill(cherryPath, with: .color(cherry))
            var stem = Path()
            stem.move(to: p(50, 7))
            stem.addQuadCurve(to: p(57, 1), control: p(51, 2))
            context.stroke(stem, with: line, style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
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

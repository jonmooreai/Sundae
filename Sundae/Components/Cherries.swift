import SwiftUI

/// One cherry with its stem. Pale when that Sunday was missed.
struct CherryDot: View {
    var pale = false
    var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 14
            let color = pale ? Theme.hairline : Theme.cherry
            let body = Path(ellipseIn: CGRect(x: 2 * s, y: 5 * s, width: 9 * s, height: 9 * s))
            context.fill(body, with: .color(color))
            var stem = Path()
            stem.move(to: CGPoint(x: 6.5 * s, y: 5 * s))
            stem.addQuadCurve(to: CGPoint(x: 11 * s, y: 0.5 * s), control: CGPoint(x: 7 * s, y: 1.5 * s))
            context.stroke(stem, with: .color(pale ? Theme.hairline : Color.primary.opacity(0.7)),
                           style: StrokeStyle(lineWidth: max(1, 1.1 * s), lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A view that starts low and faint, then settles into place after `delay`.
struct RiseIn: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(delay)) { shown = true }
            }
    }
}

/// Faint confetti in the grain of the paper. Only on the user's birthday, never announced.
struct BirthdayPaper: ViewModifier {
    let calendar: Calendar
    @State private var isBirthday = false

    private let colors: [Color] = [Theme.cherry, Color.accentColor, Color(red: 0.93, green: 0.76, blue: 0.40), Color(red: 0.62, green: 0.74, blue: 0.86)]

    func body(content: Content) -> some View {
        content
            .overlay {
                if isBirthday {
                    GeometryReader { geo in
                        ForEach(0..<46, id: \.self) { i in
                            let x = SeedColor.hue(i * 7 + 3) * geo.size.width
                            let y = SeedColor.hue(i * 13 + 5) * geo.size.height
                            Capsule()
                                .fill(colors[i % colors.count])
                                .frame(width: 3, height: 9)
                                .rotationEffect(.degrees(SeedColor.hue(i) * 180))
                                .position(x: x, y: y)
                        }
                    }
                    .opacity(0.16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear { isBirthday = MomentMemory.isBirthday(Date(), calendar: calendar) }
    }
}

extension View {
    func birthdayPaper(calendar: Calendar) -> some View { modifier(BirthdayPaper(calendar: calendar)) }
}

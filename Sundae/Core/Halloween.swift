import SwiftUI

/// Sundae's one costume of the year: the Sunday nearest Halloween dresses up. A jack-o'-lantern
/// for the cherry, candy corn in the paper, a ghost or two, and a hello in the feed. Never
/// announced ahead, gone by Monday. Read from the app's clock, so "Pretend it's Sunday" in Halloween
/// week shows it.
enum Halloween {
    /// The Sunday from October 28 to November 3: whichever falls closest to the 31st.
    static func isHalloweenSunday(_ date: Date, calendar: Calendar) -> Bool {
        guard calendar.component(.weekday, from: date) == 1 else { return false }
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return (month == 10 && day >= 28) || (month == 11 && day <= 3)
    }

    /// Candy corn, and a little twilight.
    static let colors: [Color] = [
        Color(red: 0.95, green: 0.52, blue: 0.13),
        Color(red: 0.98, green: 0.80, blue: 0.25),
        Color(red: 0.99, green: 0.96, blue: 0.89),
        Color(red: 0.49, green: 0.33, blue: 0.62),
    ]
}

/// The cherry in costume: a little carved pumpkin with a cherry's stem.
struct PumpkinCherry: View {
    var size: CGFloat = 30

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 30
            let orange = Color(red: 0.95, green: 0.52, blue: 0.13)
            let rib = Color(red: 0.80, green: 0.38, blue: 0.08)
            let carved = Color(red: 0.23, green: 0.13, blue: 0.07)
            let pumpkin = CGRect(x: 1.5 * s, y: 8 * s, width: 27 * s, height: 20.5 * s)
            context.fill(Path(ellipseIn: pumpkin), with: .color(orange))
            for inset in [5.5, 10.0] {
                let band = pumpkin.insetBy(dx: inset * s, dy: 0.4 * s)
                context.stroke(Path(ellipseIn: band), with: .color(rib.opacity(0.7)), lineWidth: 1.1 * s)
            }

            var stem = Path()
            stem.move(to: CGPoint(x: 15 * s, y: 9 * s))
            stem.addQuadCurve(to: CGPoint(x: 19.5 * s, y: 1.5 * s), control: CGPoint(x: 15 * s, y: 3 * s))
            context.stroke(stem, with: .color(Color(red: 0.36, green: 0.52, blue: 0.30)),
                           style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))

            for x in [8.5, 17.5] {
                var eye = Path()
                eye.move(to: CGPoint(x: x * s, y: 17.5 * s))
                eye.addLine(to: CGPoint(x: (x + 4) * s, y: 17.5 * s))
                eye.addLine(to: CGPoint(x: (x + 2) * s, y: 13.5 * s))
                eye.closeSubpath()
                context.fill(eye, with: .color(carved))
            }

            var mouth = Path()
            mouth.move(to: CGPoint(x: 8 * s, y: 20.5 * s))
            for (x, y) in [(10.5, 23), (13, 21.3), (15, 23.6), (17, 21.3), (19.5, 23), (22, 20.5)] {
                mouth.addLine(to: CGPoint(x: x * s, y: y * s))
            }
            mouth.addQuadCurve(to: CGPoint(x: 8 * s, y: 20.5 * s), control: CGPoint(x: 15 * s, y: 28 * s))
            context.fill(mouth, with: .color(carved))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Jack-o'-lantern")
    }
}

/// One candy corn: yellow at the base, orange in the middle, white at the tip.
private struct CandyCorn: View {
    var body: some View {
        Canvas { context, canvas in
            let w = canvas.width
            let h = canvas.height
            var kernel = Path()
            kernel.move(to: CGPoint(x: w / 2, y: 0))
            kernel.addLine(to: CGPoint(x: w, y: h))
            kernel.addLine(to: CGPoint(x: 0, y: h))
            kernel.closeSubpath()
            context.clip(to: kernel)
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Halloween.colors[2]))
            context.fill(Path(CGRect(x: 0, y: h * 0.32, width: w, height: h)), with: .color(Halloween.colors[0]))
            context.fill(Path(CGRect(x: 0, y: h * 0.68, width: w, height: h)), with: .color(Halloween.colors[1]))
        }
    }
}

/// Candy corn scattered in the paper and a few ghosts drifting, faint, on Halloween Sunday only.
private struct HalloweenNight: ViewModifier {
    let date: Date
    let calendar: Calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    func body(content: Content) -> some View {
        content.overlay {
            if Halloween.isHalloweenSunday(date, calendar: calendar) {
                GeometryReader { geo in
                    ForEach(0..<36, id: \.self) { i in
                        CandyCorn()
                            .frame(width: 7, height: 9)
                            .rotationEffect(.degrees(SeedColor.hue(i * 5 + 1) * 360))
                            .position(x: SeedColor.hue(i * 11 + 7) * geo.size.width,
                                      y: SeedColor.hue(i * 17 + 2) * geo.size.height)
                    }
                    .opacity(0.28)
                    ForEach(0..<4, id: \.self) { i in
                        Icon(Glyph.ghost, weight: .fill, size: 22 + CGFloat(i % 2) * 6)
                            .foregroundStyle(Color.primary.opacity(0.07))
                            .offset(y: drift ? -6 : 6)
                            .position(x: SeedColor.hue(i * 23 + 9) * geo.size.width,
                                      y: SeedColor.hue(i * 29 + 4) * geo.size.height)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { drift = true }
                }
            }
        }
    }
}

extension View {
    /// Halloween in the paper, when the app's clock says it is Halloween Sunday.
    func halloweenNight(date: Date, calendar: Calendar) -> some View {
        modifier(HalloweenNight(date: date, calendar: calendar))
    }
}

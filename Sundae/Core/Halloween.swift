import SwiftUI

/// Sundae's one costume of the year: the Sunday nearest Halloween dresses up. A jack-o'-lantern
/// for the cherry and a hello at the top of the feed. Never announced ahead, gone by Monday. Read
/// from the app's clock, so "Pretend it's Sunday" in Halloween week shows it.
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

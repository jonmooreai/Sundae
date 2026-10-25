import SwiftUI

/// Consecutive Sundays posted. A missed week goes pale instead of ending the run; two misses
/// in a row do end it. Nobody is punished for one Sunday away.
struct Streak: Equatable {
    /// Sundays posted in the run.
    let count: Int
    /// Oldest first. True is a posted week, false a single missed one kept in the run.
    let marks: [Bool]

    static let none = Streak(count: 0, marks: [])

    /// `weeks` newest first, as a profile lists them. The current week only counts once posted.
    static func compute(weeks: [ProfileWeek], currentWeekStart: Date) -> Streak {
        var marks: [Bool] = []
        var count = 0
        var misses = 0
        for week in weeks {
            let posted = week.dump != nil
            if week.weekStart == currentWeekStart, !posted { continue }
            if posted {
                marks.append(true)
                count += 1
                misses = 0
            } else {
                misses += 1
                if misses >= 2 {
                    marks.removeLast()
                    break
                }
                marks.append(false)
            }
        }
        while marks.last == false { marks.removeLast() }
        return Streak(count: count, marks: marks.reversed())
    }
}

/// A row of cherries, one per week in the run, and the count in words.
struct StreakCherries: View {
    let streak: Streak

    var body: some View {
        if streak.count >= 2 {
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    ForEach(Array(streak.marks.suffix(12).enumerated()), id: \.offset) { index, posted in
                        CherryDot(pale: !posted)
                            .modifier(RiseIn(delay: 0.1 + Double(index) * 0.04))
                    }
                }
                Text("\(streak.count) Sundays")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(streak.count) Sundays in a row")
        }
    }
}

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

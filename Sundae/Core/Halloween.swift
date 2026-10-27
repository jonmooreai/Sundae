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
}

/// The cherry in costume: a felt jack-o'-lantern. A picture, not a drawing, like the cherry, so it
/// keeps its wool; it is a little taller than wide, so it sits centered in its square.
struct JackOLantern: View {
    var size: CGFloat = 30

    var body: some View {
        Image("JackOLantern")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Jack-o'-lantern")
    }
}

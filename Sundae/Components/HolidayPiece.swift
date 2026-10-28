import SwiftUI

/// The cherry in costume: the holiday's felt piece. A picture, not a drawing, like the cherry, so
/// it keeps its wool; whatever its shape, it sits centered in its square.
struct HolidayPiece: View {
    let holiday: HolidaySunday
    var size: CGFloat = 30

    var body: some View {
        Image(holiday.image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(holiday.pieceName)
    }
}

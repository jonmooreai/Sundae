import SwiftUI

/// Sundae's costumes: three Sundays a year dress up, the ones nearest Valentine's Day, Halloween
/// and Christmas. A felt piece stands in for the cherry and a hello sits at the top of the feed.
/// Never announced ahead, gone by Monday. Read from the app's clock, so "Pretend it's Sunday" in
/// the right week shows it.
enum HolidaySunday: CaseIterable {
    case valentines, halloween, winter

    /// The holiday whose Sunday `date` is: the Sunday within three days of the day itself.
    static func on(_ date: Date, calendar: Calendar) -> HolidaySunday? {
        guard calendar.component(.weekday, from: date) == 1 else { return nil }
        let today = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: date)
        return allCases.first { holiday in
            guard let day = calendar.date(from: DateComponents(year: year, month: holiday.month, day: holiday.day)),
                  let apart = calendar.dateComponents([.day], from: day, to: today).day else { return false }
            return abs(apart) <= 3
        }
    }

    private var month: Int {
        switch self {
        case .valentines: 2
        case .halloween: 10
        case .winter: 12
        }
    }

    private var day: Int {
        switch self {
        case .valentines: 14
        case .halloween: 31
        case .winter: 25
        }
    }

    /// What the admin preview calls it.
    var name: String {
        switch self {
        case .valentines: "Valentine's Day"
        case .halloween: "Halloween"
        case .winter: "Christmas"
        }
    }

    /// The felt piece in the asset catalog.
    var image: String {
        switch self {
        case .valentines: "FeltHeart"
        case .halloween: "JackOLantern"
        case .winter: "Snowman"
        }
    }

    var pieceName: String {
        switch self {
        case .valentines: "Felt heart"
        case .halloween: "Jack-o'-lantern"
        case .winter: "Snowman"
        }
    }

    /// Said on the posting screen and at the top of the feed.
    var greeting: String {
        switch self {
        case .valentines: "Happy Valentine's Sunday."
        case .halloween: "Happy Halloween Sunday."
        case .winter: "Happy holidays."
        }
    }

    /// The line under the greeting at the top of the feed.
    var note: String {
        switch self {
        case .valentines: "Cards, flowers and the people you love: the sweet bits of your week belong here."
        case .halloween: "Costumes, candy hauls and carved pumpkins: the spooky bits of your week belong here."
        case .winter: "Snow days, cookies and lights on the tree: the cozy bits of your week belong here."
        }
    }
}

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

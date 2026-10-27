import SwiftUI

/// The Phosphor icons the app uses (phosphoricons.com, MIT license, see THIRD_PARTY_NOTICES.md),
/// copied from PhosphorSwift 2.1.0 into Assets.xcassets/Icons in regular, bold and fill. Only
/// these ship: the package's 9,108 icon files were processed on every build, which made each one
/// minutes slower and the app bigger. To add one, copy its three imagesets from that release and
/// add a case; a test checks every case has all three.
enum Ph: String, CaseIterable, Sendable {
    case arrowUp = "arrow-up"
    case arrowsDownUp = "arrows-down-up"
    case bell
    case bookmarkSimple = "bookmark-simple"
    case calendarBlank = "calendar-blank"
    case caretLeft = "caret-left"
    case caretRight = "caret-right"
    case chatCircle = "chat-circle"
    case check
    case checkCircle = "check-circle"
    case dotsThree = "dots-three"
    case export
    case flag
    case gearSix = "gear-six"
    case ghost
    case handPalm = "hand-palm"
    case heart
    case house
    case images
    case lockSimple = "lock-simple"
    case magnifyingGlass = "magnifying-glass"
    case mapPin = "map-pin"
    case moon
    case plus
    case plusSquare = "plus-square"
    case shuffle
    case sun
    case tag
    case textAa = "text-aa"
    case trash
    case user
    case userCircle = "user-circle"
    case userPlus = "user-plus"
    case x

    var regular: Image { Self.icon(rawValue) }
    var bold: Image { Self.icon("\(rawValue)-bold") }
    var fill: Image { Self.icon("\(rawValue)-fill") }

    private static func icon(_ name: String) -> Image {
        Image(name).interpolation(.medium).resizable()
    }
}

/// Phosphor Icons, the one icon set. Semantic names live here so no screen picks a glyph itself.
/// Regular weight in chrome, fill when selected, bold for small emphatic marks.
enum Glyph {
    static var feed: Ph { .house }
    static var search: Ph { .magnifyingGlass }
    static var post: Ph { .plusSquare }
    static var approvals: Ph { .checkCircle }
    static var profile: Ph { .userCircle }
    static var settings: Ph { .gearSix }
    static var shuffle: Ph { .shuffle }
    static var done: Ph { .check }
    static var saved: Ph { .bookmarkSimple }
    static var heart: Ph { .heart }
    static var comment: Ph { .chatCircle }
    static var tag: Ph { .tag }
    static var more: Ph { .dotsThree }
    static var close: Ph { .x }
    static var back: Ph { .caretLeft }
    static var trash: Ph { .trash }
    static var lock: Ph { .lockSimple }
    static var photos: Ph { .images }
    static var reorder: Ph { .arrowsDownUp }
    static var person: Ph { .user }
    static var personAdd: Ph { .userPlus }
    static var share: Ph { .export }
    static var calendar: Ph { .calendarBlank }
    static var sun: Ph { .sun }
    static var flag: Ph { .flag }
    static var block: Ph { .handPalm }
    static var chevronRight: Ph { .caretRight }
    static var altText: Ph { .textAa }
    static var plus: Ph { .plus }
    static var send: Ph { .arrowUp }
    static var pin: Ph { .mapPin }
    static var bell: Ph { .bell }
    static var moon: Ph { .moon }
    static var ghost: Ph { .ghost }
}

enum IconWeight {
    case regular, bold, fill
}

/// One Phosphor glyph at a size, tinted by the current foreground style.
struct Icon: View {
    let glyph: Ph
    var weight: IconWeight = .regular
    var size: CGFloat = 22

    init(_ glyph: Ph, weight: IconWeight = .regular, size: CGFloat = 22) {
        self.glyph = glyph
        self.weight = weight
        self.size = size
    }

    var body: some View {
        image
            .resizable()
            .renderingMode(.template)
            .frame(width: size, height: size)
    }

    private var image: Image {
        switch weight {
        case .regular: glyph.regular
        case .bold: glyph.bold
        case .fill: glyph.fill
        }
    }
}

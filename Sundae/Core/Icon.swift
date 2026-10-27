import PhosphorSwift
import SwiftUI

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

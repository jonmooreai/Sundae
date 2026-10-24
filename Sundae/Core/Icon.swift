import PhosphorSwift
import SwiftUI

/// Phosphor Icons, the one icon set. Semantic names live here so no screen picks a glyph itself.
/// Regular weight in chrome, fill when selected, bold for small emphatic marks.
enum Glyph {
    static let feed: Ph = .house
    static let search: Ph = .magnifyingGlass
    static let post: Ph = .plusSquare
    static let approvals: Ph = .checkCircle
    static let profile: Ph = .userCircle
    static let settings: Ph = .gearSix
    static let shuffle: Ph = .shuffle
    static let done: Ph = .check
    static let heart: Ph = .heart
    static let comment: Ph = .chatCircle
    static let tag: Ph = .tag
    static let more: Ph = .dotsThree
    static let close: Ph = .x
    static let back: Ph = .caretLeft
    static let trash: Ph = .trash
    static let lock: Ph = .lockSimple
    static let photos: Ph = .images
    static let reorder: Ph = .arrowsDownUp
    static let person: Ph = .user
    static let personAdd: Ph = .userPlus
    static let share: Ph = .export
    static let calendar: Ph = .calendarBlank
    static let sun: Ph = .sun
    static let flag: Ph = .flag
    static let block: Ph = .handPalm
    static let chevronRight: Ph = .caretRight
    static let altText: Ph = .textAa
    static let plus: Ph = .plus
    static let send: Ph = .arrowUp
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

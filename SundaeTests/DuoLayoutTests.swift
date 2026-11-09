import Foundation
import Testing
@testable import Sundae

/// How the app lays itself out around an iPhone Duo: even grids across the fold, panes on either
/// side of the crease, and soft corners where a post floats beside the side strip.
struct DuoLayoutTests {
    @Test func photoGridsKeepThreeOnAPhoneAndAnEvenCountAcrossTheOpenDuo() {
        #expect(FoldGrid.columnCount(width: 393) == 3, "an iPhone")
        #expect(FoldGrid.columnCount(width: 466) == 3, "the Duo closed")
        #expect(FoldGrid.columnCount(width: 669) == 4, "the Duo open: five fit, four divide cleanly at the crease")
        #expect(FoldGrid.columnCount(width: 1024) == 8, "an iPad: eight fit")
        #expect(FoldGrid.columnCount(width: 0) == 3, "before the width is known")
        #expect(FoldGrid.columnCount(width: 200) == 1, "very narrow")
    }

    @Test func aPostFloatsWithSoftCornersBesideTheSideStrip() {
        #expect(PhotoCarousel.radius(.compact) == 0, "edge to edge on a phone")
        #expect(PhotoCarousel.radius(.regular) == 14, "a column on a big screen")
        #expect(PhotoCarousel.radius(.compact, sideBars: true) == 14, "the Duo closed: bars down one side, so the post floats")
    }

    @Test func theCreaseSplitsPanesAndFlatScreensStack() {
        // Held like a book: the crease runs top to bottom through the middle of a 669 wide screen.
        let book = FoldAwareLayout<EmptyView, EmptyView>.arrangement(
            size: CGSize(width: 669, height: 951), fold: CGRect(x: 324, y: 0, width: 20, height: 951),
            share: 0.56, spacing: 24, short: false, big: true)
        #expect(book == .columns(left: 312, right: 313))
        // Set down like a laptop: the crease runs across.
        let laptop = FoldAwareLayout<EmptyView, EmptyView>.arrangement(
            size: CGSize(width: 951, height: 669), fold: CGRect(x: 0, y: 324, width: 951, height: 20),
            share: 0.56, spacing: 24, short: false, big: true)
        #expect(laptop == .rows(top: 312, bottom: 313))
        // Flat and open: one centered column, the two together in the middle.
        #expect(FoldAwareLayout<EmptyView, EmptyView>.arrangement(
            size: CGSize(width: 669, height: 951), fold: nil, share: 0.56, spacing: 24, short: false, big: true) == .grouped)
        // The Duo closed: a phone, stacked.
        #expect(FoldAwareLayout<EmptyView, EmptyView>.arrangement(
            size: CGSize(width: 466, height: 678), fold: nil, share: 0.56, spacing: 24, short: false, big: false) == .stacked)
    }
}

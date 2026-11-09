import SwiftUI

/// Column counts for photo grids that lay out across an iPhone Duo's inner display.
///
/// Apple's guidance for the folding display: prefer an even number of columns, so when the
/// device is part open the crease falls between two columns instead of down the middle of one.
/// Phones keep their three; the open Duo (and an iPad) gets as many as fit at the usual size,
/// rounded to even.
enum FoldGrid {
    /// How many columns for a grid `width` points across, each at least `minimum` wide.
    static func columnCount(width: CGFloat, minimum: CGFloat = 125, spacing: CGFloat = 2) -> Int {
        guard width > 0 else { return 3 }
        let fit = max(1, Int((width + spacing) / (minimum + spacing)))
        // Three on a phone, as always. Wider, an even count that the crease can sit between.
        if fit <= 3 { return fit }
        return fit % 2 == 0 ? fit : fit - 1
    }

    static func columns(width: CGFloat, minimum: CGFloat = 125, spacing: CGFloat = 2) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount(width: width, minimum: minimum, spacing: spacing))
    }
}

/// A photo grid that keeps an even number of columns on a wide display, and reads its own width
/// so it needs nothing from the screen around it.
struct FoldAwareGrid<Content: View>: View {
    var minimum: CGFloat = 125
    var spacing: CGFloat = 2
    @ViewBuilder let content: () -> Content
    @State private var width: CGFloat = 0

    var body: some View {
        LazyVGrid(columns: FoldGrid.columns(width: width, minimum: minimum, spacing: spacing), spacing: spacing) {
            content()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

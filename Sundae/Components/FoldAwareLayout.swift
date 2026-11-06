import SwiftUI

/// Two panes, laid out around the iPhone Duo's fold and otherwise by the shape of the screen.
///
/// Flat, or on any other iPhone, it goes by shape: one pane above the other when the screen is
/// taller than wide, the primary taking the room and the secondary its own height, as the screens
/// always have; side by side when wider than tall, so a phone on its side is not a squeeze.
///
/// Partly folded, the fold itself decides (SwiftUI's division region, iOS 27.1). Held like a
/// book, the fold runs top to bottom: the primary takes the left page and the secondary the right.
/// Set down like a laptop, the fold runs across: the primary takes the top half and the
/// secondary the bottom, where the fingers are. Either way nothing to tap sits in the crease.
struct FoldAwareLayout<Primary: View, Secondary: View>: View {
    /// How much of the width the primary pane gets side by side, with no fold to say.
    var primaryShare: CGFloat = 0.6
    var spacing: CGFloat = 24
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var secondary: () -> Secondary

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            switch Self.arrangement(size: size, fold: Self.fold(in: proxy), share: primaryShare, spacing: spacing) {
            case .stacked:
                VStack(spacing: spacing) {
                    primary().frame(maxWidth: .infinity, maxHeight: .infinity)
                    secondary().frame(maxWidth: .infinity)
                }
                .frame(width: size.width, height: size.height)
            case .rows(let top, let bottom):
                VStack(spacing: 0) {
                    primary().frame(maxWidth: .infinity).frame(height: top)
                    Spacer(minLength: 0)
                    secondary().frame(maxWidth: .infinity).frame(height: bottom)
                }
                .frame(width: size.width, height: size.height)
            case .columns(let left, let right):
                HStack(spacing: 0) {
                    primary().frame(width: left).frame(maxHeight: .infinity)
                    Spacer(minLength: 0)
                    secondary().frame(width: right).frame(maxHeight: .infinity)
                }
                .frame(width: size.width, height: size.height)
            }
        }
    }

    enum Arrangement: Equatable {
        /// Taller than wide and flat: the primary takes the room, the secondary its own height.
        case stacked
        /// A fold across the screen: the primary above it, the secondary below.
        case rows(top: CGFloat, bottom: CGFloat)
        /// A fold down the screen, or a flat screen wider than tall: the primary on the left.
        case columns(left: CGFloat, right: CGFloat)
    }

    /// The fold's frame in the layout's own space, when the device is partly folded.
    static func fold(in proxy: GeometryProxy) -> CGRect? { Fold.frame(in: proxy) }

    static func arrangement(size: CGSize, fold: CGRect?, share: CGFloat, spacing: CGFloat) -> Arrangement {
        if let fold, fold.width > 0, fold.height > 0 {
            let margin = spacing / 2
            if fold.height >= fold.width {
                // A book: the crease runs top to bottom.
                let left = max(0, fold.minX - margin)
                let right = max(0, size.width - fold.maxX - margin)
                if left >= 120, right >= 120 { return .columns(left: left, right: right) }
            } else {
                // A laptop: the crease runs across.
                let top = max(0, fold.minY - margin)
                let bottom = max(0, size.height - fold.maxY - margin)
                if top >= 120, bottom >= 100 { return .rows(top: top, bottom: bottom) }
            }
        }
        if size.width > size.height {
            let left = (size.width - spacing) * share
            return .columns(left: left, right: size.width - spacing - left)
        }
        return .stacked
    }
}

/// Where the iPhone Duo's fold crosses a view, when the device is partly folded: SwiftUI's
/// division region (iOS 27.1). Nil flat, on any other iPhone, and on iOS before 27.1.
enum Fold {
    static func frame(in proxy: GeometryProxy) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        guard let region = proxy.reservedRegions(kind: .division).first else { return nil }
        let frame = region.frame(in: CoordinateSpace.local)
        return frame.width > 0 && frame.height > 0 ? frame : nil
    }
}

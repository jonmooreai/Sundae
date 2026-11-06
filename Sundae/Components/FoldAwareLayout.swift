import SwiftUI

/// Two panes, laid out around the iPhone Duo's fold, or beside each other on a phone on its side.
///
/// Flat, one pane above the other, the primary taking the room and the secondary its own height,
/// as the screens always have: on any phone upright, and on an iPhone Duo open, wide or not, where
/// the screen reads as one centered column. Side by side only when there is little height (a
/// phone turned on its side, compact height), so the buttons are not squeezed off the bottom.
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            switch Self.arrangement(size: size, fold: Self.fold(in: proxy), share: primaryShare, spacing: spacing,
                                    short: verticalSizeClass == .compact,
                                    big: verticalSizeClass == .regular && horizontalSizeClass == .regular) {
            case .stacked:
                VStack(spacing: spacing) {
                    primary().frame(maxWidth: .infinity, maxHeight: .infinity)
                    secondary().frame(maxWidth: .infinity)
                }
                .frame(width: size.width, height: size.height)
            case .grouped:
                VStack(spacing: spacing * 1.5) {
                    primary().frame(maxWidth: .infinity)
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
        /// Taller than wide and flat: the primary takes the room, the secondary its own height,
        /// at the foot where a thumb reaches it.
        case stacked
        /// Taller still (the Duo open, an iPad): the two sit together in the middle of the screen,
        /// since a button at the foot of a tall screen is a long way from the words it goes with.
        case grouped
        /// A fold across the screen: the primary above it, the secondary below.
        case rows(top: CGFloat, bottom: CGFloat)
        /// A fold down the screen, or a short screen wider than tall: the primary on the left.
        case columns(left: CGFloat, right: CGFloat)
    }

    /// The fold's frame in the layout's own space, when the device is partly folded.
    static func fold(in proxy: GeometryProxy) -> CGRect? { Fold.frame(in: proxy) }

    /// `short` is compact height (a phone on its side); `big` is regular in both directions (the
    /// Duo open, an iPad), where the panes sit together in the middle rather than at the foot.
    static func arrangement(size: CGSize, fold: CGRect?, share: CGFloat, spacing: CGFloat, short: Bool, big: Bool) -> Arrangement {
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
        if short, size.width > size.height {
            let left = (size.width - spacing) * share
            return .columns(left: left, right: size.width - spacing - left)
        }
        return big ? .grouped : .stacked
    }
}

/// Where the iPhone Duo's fold crosses a view, when the device is partly folded: SwiftUI's
/// division region (iOS 27.1). Nil flat, on any other iPhone, and on iOS before 27.1.
enum Fold {
    static func frame(in proxy: GeometryProxy) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        // The region's frame is already in the proxy's own space, mirrored for right to left.
        guard let frame = proxy.reservedRegions(kind: .division).first?.frame else { return nil }
        return frame.width > 0 && frame.height > 0 ? frame : nil
    }
}

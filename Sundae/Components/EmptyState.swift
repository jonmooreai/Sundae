import SwiftUI

/// What a screen shows while it has nothing to show: an icon, a title, a line or two and perhaps
/// a button, in the middle of the space it is given, across and down. Always on the screen's own
/// background, never in a card or a list row.
struct EmptyState<Actions: View>: View {
    var glyph: Ph?
    var title: String?
    var message: String?
    var actions: Actions?

    init(_ title: String? = nil, glyph: Ph? = nil, message: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.glyph = glyph
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            if let glyph {
                Icon(glyph, size: 36).foregroundStyle(.secondary)
            }
            if let title {
                Text(title).font(Theme.display(24))
            }
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
            if let actions {
                actions.padding(.top, 6)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 360)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Actions == EmptyView {
    init(_ title: String? = nil, glyph: Ph? = nil, message: String? = nil) {
        self.title = title
        self.glyph = glyph
        self.message = message
        self.actions = nil
    }
}

/// A spinner in the middle of the space it is given, for a screen still loading.
struct LoadingState: View {
    var body: some View {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// For the content of a scroll view that has a header above an empty state: while `fills`,
    /// the content is stretched to the scroll view's visible height, so the `EmptyState` at its
    /// end takes what is left under the header and sits in the middle of it. Taller content
    /// scrolls as usual.
    func fillsVisibleHeight(_ fills: Bool) -> some View {
        modifier(FillsVisibleHeight(fills: fills))
    }
}

private struct FillsVisibleHeight: ViewModifier {
    let fills: Bool
    @State private var visible: CGFloat = 0

    func body(content: Content) -> some View {
        let height: CGFloat? = fills && visible > 0 ? visible : nil
        content
            .frame(minHeight: height, idealHeight: height, alignment: .top)
            .background {
                // The scroll view's height less its safe areas, read without changing the layout.
                Color.clear
                    .containerRelativeFrame(.vertical)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visible = $0 }
            }
    }
}

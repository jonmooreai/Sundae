import SwiftUI

// Tapping the tab you are on takes you back to its first screen; tapping it there scrolls that
// screen to the top. Each tab counts the taps and hands its first screen this count, which the
// screen scrolls on.

extension EnvironmentValues {
    /// Goes up each time the tab asks its first screen to scroll back to the top.
    @Entry var scrollToTop: Int = 0
}

/// Marks the top of a screen's scrolling content.
struct ScrollTop: View {
    static let id = "scroll-top"

    var body: some View {
        Color.clear
            .frame(height: 0)
            .id(Self.id)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Scrolls back to `ScrollTop` whenever the tab asks. Goes on the scroll view itself.
    func scrollsToTopOnTabTap() -> some View {
        modifier(ScrollsToTop())
    }
}

private struct ScrollsToTop: ViewModifier {
    @Environment(\.scrollToTop) private var signal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: signal) { _, _ in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.4)) {
                    proxy.scrollTo(ScrollTop.id, anchor: .top)
                }
            }
        }
    }
}

import SwiftUI

// On an iPhone Duo closed, and open on its side, the system lays its bars down one edge of the
// screen instead of across the top and bottom: the Dynamic Island, the clock, then the
// toolbar's buttons (Back or Close first, then Done), then the tab bar, in that order. Apple
// asks apps to follow that rather than draw their own bars across the top, so Sundae puts its
// navigation and actions into the system toolbar there and keeps its serif titles in the page.
// Everywhere else the screens draw their own chrome, as they always have.

extension EnvironmentValues {
    /// True while the system's bars run down the side of the screen. Set once at the window by
    /// `SideBarsProvider`; false on iOS before 27.1, where no screen lays bars out that way.
    @Entry var sideBars: Bool = false
}

extension View {
    /// Reads where the system lays its bars out and hands it down as `sideBars`. Put it on the
    /// window's content, once.
    func providesSideBars() -> some View {
        modifier(SideBarsProvider())
    }
}

private struct SideBarsProvider: ViewModifier {
    @State private var sideBars = false

    func body(content: Content) -> some View {
        content
            .environment(\.sideBars, sideBars)
            .background {
                if #available(iOS 27.1, *) {
                    SideBarsReader { sideBars = $0 }
                }
            }
    }
}

/// Says whether the toolbar is vertical, and tells the provider whenever that changes: the Duo
/// opening, closing or turning.
@available(iOS 27.1, *)
private struct SideBarsReader: View {
    @Environment(\.toolbarVerticalEdge) private var edge
    let report: (Bool) -> Void

    var body: some View {
        Color.clear
            .onAppear { report(edge != nil) }
            .onChange(of: edge) { _, now in report(now != nil) }
    }
}

// MARK: - Chrome that moves to the side

/// A header's icon button: round and plain in the page, and in the Duo's side strip a toolbar
/// item with a title the strip and its overflow menu can use. One view, right in both places.
struct ChromeButton: View {
    let glyph: Ph
    let title: String
    var size: CGFloat = 24
    let action: () -> Void
    @Environment(\.sideBars) private var sideBars

    var body: some View {
        if sideBars {
            Button(action: action) {
                Label { Text(title) } icon: { Icon(glyph, size: 20) }
            }
            .accessibilityLabel(title)
        } else {
            IconButton(glyph: glyph, label: title, size: size, action: action)
        }
    }
}

/// A header's More menu, the same way: the ellipsis in the page, a labelled toolbar menu in the strip.
struct ChromeMenu<Items: View>: View {
    var title = "More"
    @ViewBuilder let items: () -> Items
    @Environment(\.sideBars) private var sideBars

    var body: some View {
        Menu {
            items()
        } label: {
            if sideBars {
                Label { Text(title) } icon: { Icon(Glyph.more, weight: .bold, size: 20) }
            } else {
                Icon(Glyph.more, weight: .bold, size: 24)
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityLabel(title)
    }
}

/// Back or Close for a screen: drawn in the page's header on a phone, and on the Duo's side strip
/// through the system toolbar, where Apple puts primary navigation at the top of the strip.
struct SideBarNavigation: ToolbarContent {
    enum Kind { case back, close }
    let kind: Kind
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: kind == .back ? .navigation : .cancellationAction) {
            Button(action: action) {
                Label {
                    Text(kind == .back ? "Back" : "Close")
                } icon: {
                    Icon(kind == .back ? Glyph.back : Glyph.close, size: 20)
                }
            }
            .accessibilityIdentifier(kind == .back ? "Back" : "Close")
        }
    }
}

/// Moves a screen's own header chrome onto the system's side bars where those exist, and leaves
/// the page to draw it otherwise. The page passes the same views it would draw itself.
///
/// The toolbar is shown only while the bars are vertical: on every other phone it stays hidden,
/// so nothing changes there.
struct SideBarChrome<Trailing: View>: ViewModifier {
    @Environment(\.sideBars) private var sideBars
    let showsBack: Bool
    let onBack: (() -> Void)?
    let close: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    func body(content: Content) -> some View {
        content
            .toolbar(sideBars ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if sideBars {
                    if showsBack, let onBack {
                        SideBarNavigation(kind: .back, action: onBack)
                    }
                    if let close {
                        SideBarNavigation(kind: .close, action: close)
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        trailing()
                    }
                }
            }
    }
}

extension View {
    /// Puts Back (or Close) and the trailing chrome into the system's side bars on an iPhone Duo,
    /// and hides the system navigation bar everywhere else so the page's own header shows.
    func sideBarChrome<Trailing: View>(showsBack: Bool = false, onBack: (() -> Void)? = nil,
                                       close: (() -> Void)? = nil,
                                       @ViewBuilder trailing: @escaping () -> Trailing) -> some View {
        modifier(SideBarChrome(showsBack: showsBack, onBack: onBack, close: close, trailing: trailing))
    }

    /// The same, with nothing on the trailing side.
    func sideBarChrome(showsBack: Bool = false, onBack: (() -> Void)? = nil, close: (() -> Void)? = nil) -> some View {
        modifier(SideBarChrome(showsBack: showsBack, onBack: onBack, close: close, trailing: { EmptyView() }))
    }
}

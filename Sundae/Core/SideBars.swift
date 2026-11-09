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

extension View {
    /// A row that scrolls sideways stops at the Duo's side strip instead of running on under it:
    /// a scroll view lets its content into the safe area along the axis it scrolls, which on
    /// every other phone is the screen's edge, and beside the strip is the clock and the tabs.
    /// Everywhere else nothing is clipped.
    func insideSideBars() -> some View {
        modifier(InsideSideBarsIfNeeded())
    }
}

private struct InsideSideBarsIfNeeded: ViewModifier {
    @Environment(\.sideBars) private var sideBars
    func body(content: Content) -> some View {
        if sideBars { content.clipped() } else { content }
    }
}

/// A header's icon button: round and plain in the page, and in the Duo's side strip a toolbar
/// item with a title the strip and its overflow menu can use. One view, right in both places.
/// Strip glyphs are drawn at a fixed 20 points (`TabIcon`), the size the strip gives a symbol;
/// a resizable icon there came out half again as big as the tabs beside it.
struct ChromeButton: View {
    let glyph: Ph
    let title: String
    var size: CGFloat = 24
    let action: () -> Void
    @Environment(\.sideBars) private var sideBars

    var body: some View {
        if sideBars {
            Button(action: action) {
                Label { Text(title) } icon: { TabIcon.image(glyph, size: 20) }
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
                Label { Text(title) } icon: { TabIcon.image(Glyph.more, weight: .bold, size: 20) }
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

/// Close for a screen that is presented rather than pushed: drawn in the page's header on a
/// phone, and on the Duo's side strip through the system toolbar. Back needs no item of its own:
/// a pushed screen gets the system's Back at the top of the strip, where Apple puts it.
struct SideBarNavigation: ToolbarContent {
    enum Kind { case close }
    let kind: Kind
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: action) {
                Label { Text("Close") } icon: { TabIcon.image(Glyph.close, size: 20) }
            }
            .accessibilityIdentifier("Close")
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
    let close: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    func body(content: Content) -> some View {
        content
            .toolbar(sideBars ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if sideBars {
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

/// The screen's one primary action (Next, Post your week), on the Duo's side strip as the
/// prominent action under Back. Declared from the screen's root, like the rest of its chrome.
private struct SideBarPrimaryAction: ViewModifier {
    @Environment(\.sideBars) private var sideBars
    let title: String
    let symbol: String
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            if sideBars {
                ToolbarItem(placement: .confirmationAction) {
                    // A title and a symbol, as Apple asks for the strip: the strip shows the
                    // symbol, and the overflow menu the words.
                    Button(action: action) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Label(title, systemImage: symbol)
                        }
                    }
                    .disabled(!isEnabled || isLoading)
                    .accessibilityIdentifier("flow-primary")
                }
            }
        }
    }
}

extension View {
    /// The screen's primary action on the Duo's side strip, with the symbol the strip shows for
    /// it. Off the Duo it adds nothing; the screen's own bottom bar shows the button.
    func sideBarPrimaryAction(_ title: String, symbol: String = "arrow.right", isEnabled: Bool = true,
                              isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        modifier(SideBarPrimaryAction(title: title, symbol: symbol, isEnabled: isEnabled, isLoading: isLoading, action: action))
    }

    /// Puts Close and the trailing chrome into the system's side bars on an iPhone Duo (a pushed
    /// screen gets the system's own Back there), and hides the system navigation bar everywhere
    /// else so the page's own header shows.
    func sideBarChrome<Trailing: View>(close: (() -> Void)? = nil,
                                       @ViewBuilder trailing: @escaping () -> Trailing) -> some View {
        modifier(SideBarChrome(close: close, trailing: trailing))
    }

    /// The same, with nothing on the trailing side.
    func sideBarChrome(close: (() -> Void)? = nil) -> some View {
        modifier(SideBarChrome(close: close, trailing: { EmptyView() }))
    }
}

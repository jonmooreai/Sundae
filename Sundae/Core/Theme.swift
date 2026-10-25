import SwiftUI
import UIKit
import PhosphorSwift

/// Cream paper, warm grays, a sage accent, serif display type, pill buttons. Photos carry
/// the color; the chrome stays quiet in either theme. Nothing here is a stock iOS control.
enum Theme {
    static let radius: CGFloat = 16
    static let smallRadius: CGFloat = 10
    static let chipRadius: CGFloat = 12
    /// Size of a photo card in a profile week row.
    static let rowHeight: CGFloat = 196
    /// Corner radius of a photo card in a profile week row.
    static let rowRadius: CGFloat = 16
    /// Gap between photo cards in a week row.
    static let gap: CGFloat = 8
    static let pagePadding: CGFloat = 16

    /// Cream paper by day, warm charcoal at night. Same cream as the app icon.
    static var background: Color { warm((251, 248, 243), (25, 23, 20)) }
    /// Surface for fields and quiet containers.
    static var surface: Color { warm((242, 237, 228), (36, 33, 31)) }
    static var surfaceRaised: Color { warm((255, 253, 249), (43, 40, 38)) }
    /// Fill for secondary buttons.
    static var fill: Color { warm((236, 229, 217), (48, 44, 41)) }
    static var hairline: Color { warm((227, 220, 207), (59, 54, 49)) }
    /// The cherry on the sundae, and the color of a like. The only red in the app.
    static let cherry = Color(red: 0.86, green: 0.26, blue: 0.30)

    private static func warm(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
        })
    }

    /// Display type for titles and the weekday screen.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Buttons

/// Capsule buttons: filled accent for the one primary action, neutral fill for the rest.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, destructive }
    enum Size { case regular, small }

    var kind: Kind = .primary
    var size: Size = .regular
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(kind: kind, size: size, fullWidth: fullWidth, configuration: configuration)
    }

    private struct PillLabel: View {
        let kind: Kind
        let size: Size
        let fullWidth: Bool
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            configuration.label
                .font(size == .small ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .center)
                .padding(.horizontal, size == .small ? 16 : 22)
                .frame(height: size == .small ? 36 : 50, alignment: .center)
                .background(background, in: Capsule())
                .foregroundStyle(foreground)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
        }

        private var background: Color {
            switch kind {
            case .primary: Color.accentColor
            case .secondary: Theme.fill
            case .quiet: .clear
            case .destructive: Theme.fill
            }
        }

        /// White on every pill at night; by day the quiet kind steps back to gray.
        private var foreground: Color {
            switch kind {
            case .primary: .white
            case .secondary: colorScheme == .dark ? .white : .primary
            case .quiet: colorScheme == .dark ? .white : .secondary
            case .destructive: Theme.cherry
            }
        }
    }
}

/// Text-only buttons in forms and toolbars: the accent by day, white at night.
private struct TextButtonTint: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.tint(colorScheme == .dark ? Color.white : Color.accentColor)
    }
}

extension View {
    func textButtonTint() -> some View { modifier(TextButtonTint()) }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var primary: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var secondary: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var quiet: PillButtonStyle { PillButtonStyle(kind: .quiet) }
    static func pill(_ kind: PillButtonStyle.Kind, size: PillButtonStyle.Size = .regular, fullWidth: Bool = false) -> PillButtonStyle {
        PillButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

/// A round icon button for chrome: back, close, more, settings.
struct IconButton: View {
    let glyph: Ph
    var label: String
    var size: CGFloat = 22
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(glyph, size: size)
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(filled ? Theme.fill : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Headers

/// The top of a root screen: a serif title, an optional line under it, and chrome on the right.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var showsBack = false
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if showsBack {
                IconButton(glyph: Glyph.back, label: "Back", size: 24) { dismiss() }
                    .padding(.leading, -8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.display(28))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

/// A search field that looks like ours: neutral fill, magnifier, clear button.
struct SearchField: View {
    @Binding var text: String
    var placeholder = "Search"

    var body: some View {
        HStack(spacing: 8) {
            Icon(Glyph.search, size: 18)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Icon(Glyph.close, weight: .bold, size: 14)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Two or three choices in one capsule, like a filter row.
struct ChipPicker<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { option, title in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option }
                } label: {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(selection == option ? Theme.background : .clear, in: Capsule())
                        .foregroundStyle(selection == option ? .primary : .secondary)
                        .shadow(color: .black.opacity(selection == option ? 0.06 : 0), radius: 4, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surface, in: Capsule())
    }
}

extension View {
    /// Soft container: neutral surface and rounded corners, no border.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// Stable pastel for avatars without a photo, derived from a seed.
enum SeedColor {
    static func hue(_ seed: Int) -> Double {
        let golden = 0.618033988749895
        return (Double(seed) * golden).truncatingRemainder(dividingBy: 1)
    }
    static func color(_ seed: Int, saturation: Double = 0.42, brightness: Double = 0.86) -> Color {
        Color(hue: hue(seed), saturation: saturation, brightness: brightness)
    }
    static func gradient(_ seed: Int) -> LinearGradient {
        LinearGradient(
            colors: [color(seed), color(seed + 7, saturation: 0.5, brightness: 0.72)],
            startPoint: seed % 2 == 0 ? .topLeading : .top,
            endPoint: seed % 2 == 0 ? .bottomTrailing : .bottom
        )
    }
}

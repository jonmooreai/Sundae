import SwiftUI

/// One accent, generous whitespace, rounded corners, minimal borders.
/// Photos carry the color; the chrome stays quiet in both themes.
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

    static var background: Color { Color(uiColor: .systemBackground) }
    static var surface: Color { Color(uiColor: .secondarySystemBackground) }
    static var surfaceRaised: Color { Color(uiColor: .tertiarySystemBackground) }
    static var hairline: Color { Color(uiColor: .separator).opacity(0.5) }

    /// Display type for the weekday screen. The screen people see most gets the best typography.
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

extension View {
    /// Soft card: surface color and rounded corners, no border.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// Stable pastel for avatars and placeholder photos, derived from a seed.
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

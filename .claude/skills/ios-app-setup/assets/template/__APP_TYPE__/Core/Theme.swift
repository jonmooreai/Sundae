import SwiftUI
import UIKit

/// Every color is a token with a light and a dark value; light is the design's starting point.
/// Separation comes from whitespace and soft fills, not borders: no thick border on one side of a
/// container, and hairlines at most. Change the values here, not at the call sites.
enum Theme {
    static let radius: CGFloat = 16
    static let pagePadding: CGFloat = 16

    /// Warm off-white by day, warm charcoal at night.
    static var background: Color { dynamic(light: (251, 248, 243), dark: (25, 23, 20)) }
    /// Fields and quiet containers.
    static var surface: Color { dynamic(light: (242, 237, 228), dark: (43, 40, 38)) }
    /// Errors and anything that can't be undone.
    static var danger: Color { dynamic(light: (196, 52, 58), dark: (240, 110, 112)) }

    /// Display type for titles.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
        })
    }
}

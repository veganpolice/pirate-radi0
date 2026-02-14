import SwiftUI

enum PirateTheme {
    // MARK: - Core Palette
    static let void = Color(red: 0.05, green: 0.05, blue: 0.05)         // #0D0D0D
    static let signal = Color(red: 0, green: 1, blue: 0.88)              // #00FFE0 — cyan
    static let broadcast = Color(red: 1, green: 0, blue: 1)              // #FF00FF — magenta
    static let flare = Color(red: 1, green: 0.72, blue: 0)               // #FFB800 — amber
    static let snow = Color.white.opacity(0.12)                           // dividers, secondary

    // MARK: - Semantic Colors
    // signal  = primary / active / connected / listener
    // broadcast = DJ / authority / power
    // flare   = alerts / warmth / attention / notifications

    // MARK: - Text Styles
    static let displayFont = "Menlo-Bold"
    static let bodyFont = "Menlo"

    static func display(_ size: CGFloat) -> Font {
        .custom(displayFont, size: size)
    }

    static func body(_ size: CGFloat) -> Font {
        .custom(bodyFont, size: size)
    }
}

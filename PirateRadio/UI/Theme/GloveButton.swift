import SwiftUI

/// A large, glove-friendly button style with neon border and press-to-fill animation.
/// Minimum 60pt touch target for ski glove usability.
struct GloveButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PirateTheme.body(16))
            .foregroundStyle(configuration.isPressed ? PirateTheme.void : color)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? color : color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(color, lineWidth: 1.5)
            )
            .shadow(color: color.opacity(configuration.isPressed ? 0.6 : 0.3), radius: configuration.isPressed ? 12 : 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isPressed)
    }
}

/// A neon glow modifier for text and views.
struct NeonGlow: ViewModifier {
    let color: Color
    let intensity: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.9 * intensity), radius: 2 * intensity)
            .shadow(color: color.opacity(0.4 * intensity), radius: 8 * intensity)
            .shadow(color: color.opacity(0.15 * intensity), radius: 20 * intensity)
    }
}

extension View {
    func neonGlow(_ color: Color, intensity: CGFloat = 1.0) -> some View {
        modifier(NeonGlow(color: color, intensity: intensity))
    }
}

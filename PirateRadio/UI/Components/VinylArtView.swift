import SwiftUI

/// Album art with breathing scale animation and neon glow oscillation.
struct VinylArtView: View {
    let url: URL?
    let isPlaying: Bool
    var size: CGFloat = 200

    @State private var breathScale: CGFloat = 1.0
    @State private var glowIntensity: CGFloat = 0.3

    var body: some View {
        CachedAsyncImage(url: url)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(breathScale)
        .neonGlow(PirateTheme.signal, intensity: glowIntensity)
        .shadow(color: PirateTheme.signal.opacity(0.2), radius: 16)
        .drawingGroup()
        .onAppear { startAnimations() }
        .onChange(of: isPlaying) { _, _ in
            startAnimations()
        }
    }

    private func startAnimations() {
        if isPlaying {
            // Breathing: 1.0 → 1.02 over 2s, continuous
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathScale = 1.02
            }
            // Glow oscillation: slow 4s cycle to reduce shadow recalculation
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.4
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                breathScale = 1.0
                glowIntensity = 0.1
            }
        }
    }
}

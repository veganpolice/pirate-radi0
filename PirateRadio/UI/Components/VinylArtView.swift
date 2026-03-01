import SwiftUI

/// Album art with breathing scale animation and neon glow oscillation.
struct VinylArtView: View {
    let url: URL?
    let isPlaying: Bool
    var size: CGFloat = 200

    @State private var breathScale: CGFloat = 1.0
    @State private var glowIntensity: CGFloat = 0.3

    var body: some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder
                            .overlay {
                                ProgressView()
                                    .tint(PirateTheme.signal)
                            }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(breathScale)
        .neonGlow(PirateTheme.signal, intensity: glowIntensity)
        .shadow(color: PirateTheme.signal.opacity(0.2), radius: 16)
        .onAppear { startAnimations() }
        .onChange(of: isPlaying) { _, _ in
            startAnimations()
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(PirateTheme.signal.opacity(0.05))
            .overlay {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: size * 0.24))
                    .foregroundStyle(PirateTheme.signal.opacity(0.3))
            }
    }

    private func startAnimations() {
        if isPlaying {
            // Breathing: 1.0 → 1.02 over 2s, continuous
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathScale = 1.02
            }
            // Glow oscillation: 0.2 → 0.5 over 0.8s
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                glowIntensity = 0.5
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                breathScale = 1.0
                glowIntensity = 0.1
            }
        }
    }
}

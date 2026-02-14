import SwiftUI

/// Login screen with pirate radio aesthetic.
/// Large glove-friendly "Connect Spotify" button with neon styling.
struct SpotifyAuthView: View {
    @Environment(SpotifyAuthManager.self) private var authManager

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Logo / Title
                VStack(spacing: 12) {
                    Text("PIRATE")
                        .font(PirateTheme.display(48))
                        .foregroundStyle(PirateTheme.signal)
                        .neonGlow(PirateTheme.signal, intensity: 0.8)

                    Text("RADIO")
                        .font(PirateTheme.display(48))
                        .foregroundStyle(PirateTheme.broadcast)
                        .neonGlow(PirateTheme.broadcast, intensity: 0.8)

                    Text("synced listening for the slopes")
                        .font(PirateTheme.body(14))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                // Error message
                if let error = authManager.error {
                    Text(error.errorDescription ?? "Something went wrong")
                        .font(PirateTheme.body(13))
                        .foregroundStyle(PirateTheme.flare)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Connect button
                Button {
                    Task { await authManager.signIn() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Connect Spotify")
                    }
                }
                .buttonStyle(GloveButtonStyle(color: PirateTheme.signal))

                Text("Requires Spotify Premium")
                    .font(PirateTheme.body(12))
                    .foregroundStyle(.white.opacity(0.3))

                Spacer()
                    .frame(height: 60)
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    SpotifyAuthView()
        .environment(SpotifyAuthManager())
}

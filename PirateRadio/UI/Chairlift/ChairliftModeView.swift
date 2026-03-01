import SwiftUI

/// Simplified chairlift mode overlay for Now Playing.
/// Hides crew strip, enlarges art, simplifies controls.
struct ChairliftModeView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var volume: Double = 0.5

    var body: some View {
        ZStack {
            // Slightly darker background
            Color.black.opacity(0.3).ignoresSafeArea()

            VStack(spacing: 24) {
                // Chairlift badge
                HStack(spacing: 8) {
                    Text("\u{1F6A1}")
                        .font(.system(size: 16))
                    Text("CHAIRLIFT MODE")
                        .font(PirateTheme.display(14))
                        .foregroundStyle(PirateTheme.signal)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(PirateTheme.signal.opacity(0.1))
                )
                .overlay(Capsule().strokeBorder(PirateTheme.signal.opacity(0.3), lineWidth: 0.5))
                .padding(.top, 16)

                Spacer()

                // Large album art
                if let track = sessionStore.session?.currentTrack {
                    VinylArtView(
                        url: track.albumArtURL,
                        isPlaying: sessionStore.session?.isPlaying ?? false,
                        size: UIScreen.main.bounds.width * 0.75
                    )

                    // Track info
                    VStack(spacing: 6) {
                        Text(track.name)
                            .font(PirateTheme.display(22))
                            .foregroundStyle(PirateTheme.signal)
                            .neonGlow(PirateTheme.signal, intensity: 0.4)
                            .lineLimit(1)

                        Text(track.artist)
                            .font(PirateTheme.body(16))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 16)
                }

                Spacer()

                // Simplified controls: just play/pause + skip (large targets)
                HStack(spacing: 48) {
                    // Play / Pause
                    Button {
                        Task {
                            if sessionStore.session?.isPlaying == true {
                                await sessionStore.pause()
                            } else {
                                await sessionStore.resume()
                            }
                        }
                    } label: {
                        Image(systemName: sessionStore.session?.isPlaying == true ? "pause.fill" : "play.fill")
                            .font(.system(size: 36))
                    }
                    .frame(width: 80, height: 80)
                    .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))

                    // Skip
                    Button {
                        if PirateRadioApp.demoMode {
                            sessionStore.demoSkipToNext()
                        } else {
                            Task { await sessionStore.skipToNext() }
                        }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 28))
                    }
                    .frame(width: 80, height: 80)
                    .foregroundStyle(PirateTheme.broadcast)
                }

                // Volume
                FrequencyDial(value: $volume, color: PirateTheme.signal)
                    .frame(width: 100, height: 100)
                    .padding(.bottom, 32)
            }
        }
    }
}

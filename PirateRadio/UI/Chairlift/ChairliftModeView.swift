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

                // Simplified controls: just skip (large target)
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
                .buttonStyle(GloveButtonStyle(color: PirateTheme.signal))

                // Volume (cosmetic — Spotify SDK doesn't expose volume)
                VolumeKnob(value: $volume, color: PirateTheme.signal)
                    .frame(width: 100, height: 100)
                    .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Volume Knob (cosmetic rotary dial)

/// A simple rotary knob for volume display in chairlift mode.
struct VolumeKnob: View {
    @Binding var value: Double
    let color: Color

    private let startAngle: Double = -135
    private let endAngle: Double = 135

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2

            ZStack {
                Circle()
                    .strokeBorder(color.opacity(0.3), lineWidth: 2)

                let angle = Angle.degrees(startAngle + value * (endAngle - startAngle))

                Path { path in
                    let cos = Foundation.cos(angle.radians)
                    let sin = Foundation.sin(angle.radians)
                    path.move(to: CGPoint(x: radius + radius * 0.2 * cos, y: radius + radius * 0.2 * sin))
                    path.addLine(to: CGPoint(x: radius + radius * 0.65 * cos, y: radius + radius * 0.65 * sin))
                }
                .stroke(color, lineWidth: 3)
                .shadow(color: color.opacity(0.8), radius: 4)

                Circle()
                    .fill(PirateTheme.void)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay(Circle().strokeBorder(color.opacity(0.5), lineWidth: 1))

                Text(String(format: "%.0f", value * 100))
                    .font(PirateTheme.display(size * 0.12))
                    .foregroundStyle(color)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let center = CGPoint(x: size / 2, y: size / 2)
                        let angle = atan2(drag.location.y - center.y, drag.location.x - center.x)
                        let degrees = angle * 180 / .pi
                        let normalized = (degrees - startAngle) / (endAngle - startAngle)
                        value = max(0, min(1, normalized))
                    }
            )
            .neonGlow(color, intensity: 0.3)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

import SwiftUI

/// A beat-synced visualizer that pulses at the track's BPM.
///
/// Computes beat phase from the NTP-anchored playback position, so all devices
/// in a session show identical animation — visual proof of sync.
///
/// Uses `TimelineView` + `Canvas` (same pattern as `CRTStaticOverlay`).
struct BeatVisualizer: View {
    @Environment(SessionStore.self) private var store

    /// Number of concentric rings to track (ring pool).
    private let maxRings = 4

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let phase = currentBeatPhase(at: timeline.date)
                let isPlaying = store.session?.isPlaying == true
                let hasBPM = store.currentBPM != nil && (store.currentBPM ?? 0) > 0

                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let maxRadius = min(size.width, size.height) / 2

                    if isPlaying && hasBPM {
                        drawBeatRings(
                            context: &context,
                            center: center,
                            maxRadius: maxRadius,
                            phase: phase
                        )
                    } else {
                        // Idle: subtle ambient glow
                        drawIdleGlow(
                            context: &context,
                            center: center,
                            maxRadius: maxRadius
                        )
                    }

                    // Album art placeholder circle in center
                    drawCenterDisc(
                        context: &context,
                        center: center,
                        radius: maxRadius * 0.3
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                // Album art in center
                centerAlbumArt
            }

            // Sync status indicator
            syncStatusLabel
        }
    }

    // MARK: - Beat Phase Computation

    private func currentBeatPhase(at date: Date) -> Double {
        guard let bpm = store.currentBPM,
              store.session?.isPlaying == true,
              bpm > 0 else { return 0 }

        let positionSeconds = store.currentPlaybackPosition(at: date)
        let beatsElapsed = positionSeconds * (bpm / 60.0)
        return beatsElapsed.truncatingRemainder(dividingBy: 1.0)
    }

    // MARK: - Ring Drawing

    private func drawBeatRings(
        context: inout GraphicsContext,
        center: CGPoint,
        maxRadius: CGFloat,
        phase: Double
    ) {
        let ringColor = store.isDJ ? PirateTheme.broadcast : PirateTheme.signal
        let bpm = store.currentBPM ?? 120
        // Anti-strobe: reduce intensity for fast BPM (>180)
        let intensityScale = bpm > 180 ? 120.0 / bpm : 1.0
        let visibleRings = bpm > 180 ? 2 : maxRings

        // Each ring spawns at phase 0 and expands outward over one beat cycle.
        // We show multiple rings offset in phase to create a continuous ripple effect.
        for i in 0..<visibleRings {
            let ringPhase = (phase + Double(i) / Double(visibleRings))
                .truncatingRemainder(dividingBy: 1.0)

            // Ring expands from 35% to 100% of max radius
            let ringRadius = maxRadius * (0.35 + ringPhase * 0.65)

            // Opacity: bright at spawn, fades as it expands
            let opacity = max(0, 1.0 - ringPhase) * 0.6 * intensityScale

            // Line width: thicker at spawn, thinner as it fades
            let lineWidth = 2.0 + (1.0 - ringPhase) * 2.0

            let ringPath = Path(ellipseIn: CGRect(
                x: center.x - ringRadius,
                y: center.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            ))

            context.stroke(
                ringPath,
                with: .color(ringColor.opacity(opacity)),
                lineWidth: lineWidth
            )
        }

        // Beat flash: bright pulse at phase 0.0-0.1 (the "hit")
        let attackIntensity = phase < 0.1
            ? (1.0 - phase / 0.1)  // Sharp decay from 1.0 to 0.0
            : (phase > 0.9 ? (phase - 0.9) / 0.1 * 0.3 : 0)  // Subtle anticipation

        if attackIntensity > 0.01 {
            let glowRadius = maxRadius * 0.4
            let glowRect = CGRect(
                x: center.x - glowRadius,
                y: center.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )

            // Radial glow
            let gradient = Gradient(colors: [
                ringColor.opacity(attackIntensity * 0.4),
                ringColor.opacity(0),
            ])

            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - maxRadius * 0.6,
                    y: center.y - maxRadius * 0.6,
                    width: maxRadius * 1.2,
                    height: maxRadius * 1.2
                )),
                with: .radialGradient(
                    gradient,
                    center: center,
                    startRadius: glowRect.width * 0.3,
                    endRadius: maxRadius * 0.6
                )
            )
        }
    }

    private func drawIdleGlow(
        context: inout GraphicsContext,
        center: CGPoint,
        maxRadius: CGFloat
    ) {
        let ringColor = (store.isDJ ? PirateTheme.broadcast : PirateTheme.signal)
        let ringPath = Path(ellipseIn: CGRect(
            x: center.x - maxRadius * 0.35,
            y: center.y - maxRadius * 0.35,
            width: maxRadius * 0.7,
            height: maxRadius * 0.7
        ))
        context.stroke(
            ringPath,
            with: .color(ringColor.opacity(0.15)),
            lineWidth: 1.5
        )
    }

    private func drawCenterDisc(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat
    ) {
        let disc = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.fill(disc, with: .color(PirateTheme.void))
        context.stroke(
            disc,
            with: .color((store.isDJ ? PirateTheme.broadcast : PirateTheme.signal).opacity(0.3)),
            lineWidth: 1
        )
    }

    // MARK: - Album Art Overlay

    private var centerAlbumArt: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let artSize = size * 0.28

            Group {
                if let track = store.session?.currentTrack,
                   let url = track.albumArtURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        albumArtPlaceholder
                    }
                } else {
                    albumArtPlaceholder
                }
            }
            .frame(width: artSize, height: artSize)
            .clipShape(Circle())
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private var albumArtPlaceholder: some View {
        Circle()
            .fill(PirateTheme.void)
            .overlay {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20))
                    .foregroundStyle(PirateTheme.signal.opacity(0.3))
            }
    }

    // MARK: - Sync Status

    private var syncStatusLabel: some View {
        Group {
            switch store.syncStatus {
            case .synced:
                Text("IN SYNC")
                    .foregroundStyle(PirateTheme.signal)
            case .drifting:
                Text("SYNCING...")
                    .foregroundStyle(PirateTheme.flare)
            case .correcting:
                Text("SYNCING...")
                    .foregroundStyle(PirateTheme.flare)
            case .lost:
                Text("SIGNAL LOST")
                    .foregroundStyle(PirateTheme.flare.opacity(0.6))
            }
        }
        .font(PirateTheme.body(10))
        .opacity(store.session?.isPlaying == true ? 1 : 0)
    }
}

#Preview {
    ZStack {
        PirateTheme.void.ignoresSafeArea()
        BeatVisualizer()
            .frame(width: 240, height: 260)
    }
    .environment(SessionStore.demo())
}

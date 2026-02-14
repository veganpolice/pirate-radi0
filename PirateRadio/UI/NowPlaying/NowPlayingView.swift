import SwiftUI

/// The main now-playing screen shown during an active session.
/// Beat visualizer as hero element, track info below, crew strip, controls at bottom.
struct NowPlayingView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var volume: Double = 0.5
    @State private var showQueue = false

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            VStack(spacing: 0) {
                // Beat visualizer (replaces album art)
                BeatVisualizer()
                    .frame(height: 240)
                    .padding(.top, 16)

                // Track info below visualizer
                trackInfo
                    .padding(.top, 12)

                Spacer()

                // Crew strip
                crewStrip
                    .padding(.vertical, 16)

                // Controls
                if sessionStore.isDJ {
                    djControls
                } else {
                    listenerControls
                }

                // Volume dial
                FrequencyDial(value: $volume, color: PirateTheme.signal)
                    .frame(width: 120, height: 120)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        VStack(spacing: 4) {
            if let track = sessionStore.session?.currentTrack {
                Text(track.name)
                    .font(PirateTheme.display(20))
                    .foregroundStyle(PirateTheme.signal)
                    .neonGlow(PirateTheme.signal, intensity: 0.5)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(track.artist)
                    .font(PirateTheme.body(14))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Crew Strip

    private var crewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if let session = sessionStore.session {
                    ForEach(session.members) { member in
                        VStack(spacing: 4) {
                            Circle()
                                .strokeBorder(
                                    member.id == session.djUserID ? PirateTheme.broadcast : PirateTheme.signal,
                                    lineWidth: 2
                                )
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Text(String(member.displayName.prefix(1)).uppercased())
                                        .font(PirateTheme.display(16))
                                        .foregroundStyle(
                                            member.id == session.djUserID ? PirateTheme.broadcast : PirateTheme.signal
                                        )
                                }

                            Text(member.displayName)
                                .font(PirateTheme.body(10))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - DJ Controls

    private var djControls: some View {
        HStack(spacing: 24) {
            // Previous / Seek back
            Button {
                Task { await sessionStore.seek(to: 0) }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .frame(minWidth: 60, minHeight: 60)

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
                    .font(.largeTitle)
            }
            .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))

            // Skip
            Button {
                // TODO: Skip to next in queue
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .frame(minWidth: 60, minHeight: 60)

            // Queue
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title2)
            }
            .frame(minWidth: 60, minHeight: 60)
        }
        .foregroundStyle(PirateTheme.broadcast)
        .padding(.vertical, 8)
    }

    // MARK: - Listener Controls

    private var listenerControls: some View {
        HStack(spacing: 16) {
            // Sync status
            ConnectionStatusBadge(state: sessionStore.connectionState)

            Spacer()

            // Request song
            Button { showQueue = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Request Song")
                }
            }
            .buttonStyle(GloveButtonStyle(color: PirateTheme.signal))
        }
        .padding(.vertical, 8)
    }
}

import SwiftUI

/// The main now-playing screen shown during an active session.
/// Asymmetric layout: album art upper-left, track title overlapping in neon,
/// crew list as horizontal strip, DJ controls at bottom.
struct NowPlayingView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var volume: Double = 0.5
    @State private var showQueue = false

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            VStack(spacing: 0) {
                // Album art + track info
                trackHeader

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

    // MARK: - Track Header

    private var trackHeader: some View {
        HStack(alignment: .top, spacing: 0) {
            // Album art
            if let track = sessionStore.session?.currentTrack,
               let url = track.albumArtURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(PirateTheme.signal.opacity(0.1))
                }
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .neonGlow(PirateTheme.signal, intensity: 0.3)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(PirateTheme.signal.opacity(0.05))
                    .frame(width: 200, height: 200)
                    .overlay {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 48))
                            .foregroundStyle(PirateTheme.signal.opacity(0.3))
                    }
            }

            Spacer()
        }
        .overlay(alignment: .bottomTrailing) {
            // Track title overlapping art
            if let track = sessionStore.session?.currentTrack {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(track.name)
                        .font(PirateTheme.display(20))
                        .foregroundStyle(PirateTheme.signal)
                        .neonGlow(PirateTheme.signal, intensity: 0.5)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)

                    Text(track.artist)
                        .font(PirateTheme.body(14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 16)
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

import SwiftUI

/// The main now-playing screen shown during an active session.
/// Beat visualizer as hero element, track info below, crew strip, controls at bottom.
struct NowPlayingView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var volume: Double = 0.5
    @State private var showQueue = false
    @State private var showTrackSearch = false

    private var hasContent: Bool {
        sessionStore.session?.currentTrack != nil || !(sessionStore.session?.queue.isEmpty ?? true)
    }

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            if hasContent {
                playerView
            } else {
                emptyBroadcastView
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
        .sheet(isPresented: $showTrackSearch) {
            TrackSearchView()
        }
        .task {
            // Auto-play first queued track if nothing is playing
            if sessionStore.session?.currentTrack == nil,
               let firstTrack = sessionStore.session?.queue.first {
                await sessionStore.play(track: firstTrack)
            }
        }
    }

    // MARK: - Player View (has tracks)

    private var playerView: some View {
        VStack(spacing: 0) {
            // Beat visualizer (replaces album art)
            BeatVisualizer()
                .frame(height: 240)
                .padding(.top, 16)

            // Track info below visualizer
            trackInfo
                .padding(.top, 12)

            // Up next queue preview
            upNextPreview
                .padding(.top, 16)

            Spacer()

            // Pirate fleet
            if let session = sessionStore.session {
                NeonPirateScene(
                    members: session.members,
                    djUserID: session.djUserID
                )
                .padding(.horizontal, 8)
            }

            // Crew strip
            crewStrip
                .padding(.vertical, 8)

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

    // MARK: - Empty Broadcast View (no tracks yet)

    private var emptyBroadcastView: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("ON AIR")
                .font(PirateTheme.display(24))
                .foregroundStyle(PirateTheme.broadcast)
                .neonGlow(PirateTheme.broadcast, intensity: 0.8)

            // Join code
            if let session = sessionStore.session {
                VStack(spacing: 8) {
                    Text("share this frequency")
                        .font(PirateTheme.body(14))
                        .foregroundStyle(.white.opacity(0.5))

                    HStack(spacing: 16) {
                        ForEach(Array(session.joinCode.enumerated()), id: \.offset) { _, char in
                            Text(String(char))
                                .font(PirateTheme.display(48))
                                .foregroundStyle(PirateTheme.broadcast)
                                .frame(width: 56, height: 72)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(PirateTheme.broadcast.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(PirateTheme.broadcast, lineWidth: 1.5)
                                )
                                .neonGlow(PirateTheme.broadcast, intensity: 0.5)
                        }
                    }

                    // Member count
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                        Text("\(session.members.count) crew member\(session.members.count == 1 ? "" : "s")")
                    }
                    .font(PirateTheme.body(14))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
                }
            }

            // Pick first track
            Button {
                showTrackSearch = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                    Text("Pick a Track")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))

            // Share button
            if let session = sessionStore.session {
                ShareLink(
                    item: "Join my Pirate Radio session! Code: \(session.joinCode)",
                    subject: Text("Pirate Radio"),
                    message: Text("Tune in to my session with code \(session.joinCode)")
                ) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Code")
                    }
                }
                .buttonStyle(GloveButtonStyle(color: PirateTheme.signal))
            }

            Spacer()

            ConnectionStatusBadge(state: sessionStore.connectionState)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
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

    // MARK: - Up Next Preview

    private var upNextPreview: some View {
        let queue = Array((sessionStore.session?.queue ?? []).prefix(3))
        return Group {
            if !queue.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("UP NEXT")
                            .font(PirateTheme.body(11))
                            .foregroundStyle(PirateTheme.signal.opacity(0.4))

                        Spacer()

                        if (sessionStore.session?.queue.count ?? 0) > 3 {
                            Button { showQueue = true } label: {
                                Text("See All")
                                    .font(PirateTheme.body(11))
                                    .foregroundStyle(PirateTheme.signal.opacity(0.6))
                            }
                        }
                    }

                    ForEach(queue) { track in
                        HStack(spacing: 10) {
                            AsyncImage(url: track.albumArtURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(0.08))
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.name)
                                    .font(PirateTheme.body(13))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(PirateTheme.body(11))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(track.durationFormatted)
                                .font(PirateTheme.body(11))
                                .foregroundStyle(.white.opacity(0.2))
                        }
                    }
                }
                .padding(.horizontal, 4)
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

            // Add track
            Button { showTrackSearch = true } label: {
                Image(systemName: "plus")
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

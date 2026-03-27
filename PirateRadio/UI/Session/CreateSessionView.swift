import SwiftUI

/// Session creation flow: pick DJ mode → show join code → pick a track to start.
struct CreateSessionView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(SpotifyAuthManager.self) private var authManager

    @State private var selectedMode: DJMode = .solo
    @State private var showCode = false
    @State private var showQueue = false
    @State private var topTracks: [Track] = []
    @State private var isLoadingTracks = false
    @State private var spotifyClient: SpotifyClient?

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            if showCode, let session = sessionStore.session {
                codeDisplay(session)
            } else {
                modeSelection
            }
        }
        .onAppear {
            if sessionStore.session != nil {
                showCode = true
            }
            if !PirateRadioApp.demoMode {
                spotifyClient = SpotifyClient(authManager: authManager)
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
    }

    // MARK: - Mode Selection

    private var modeSelection: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("START BROADCASTING")
                .font(PirateTheme.display(22))
                .foregroundStyle(PirateTheme.broadcast)
                .neonGlow(PirateTheme.broadcast, intensity: 0.5)

            DJModePicker(selectedMode: $selectedMode)
                .padding(.horizontal, 24)

            Button {
                createSession()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Go Live")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func createSession() {
        if PirateRadioApp.demoMode {
            let _ = MockData.demoSession(djMode: selectedMode)
            sessionStore.changeDJMode(selectedMode)
            withAnimation(.spring(duration: 0.5)) {
                showCode = true
            }
        } else {
            Task {
                await sessionStore.createSession()
                await loadTopTracks()
            }
            showCode = true
        }
    }

    private func loadTopTracks() async {
        isLoadingTracks = true
        do {
            topTracks = try await spotifyClient?.getTopTracks(limit: 10) ?? []
        } catch {
            print("[CreateSession] Failed to load top tracks: \(error)")
        }
        isLoadingTracks = false
    }

    // MARK: - Code Display

    private func codeDisplay(_ session: Session) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                Text("ON AIR")
                    .font(PirateTheme.display(24))
                    .foregroundStyle(PirateTheme.broadcast)
                    .neonGlow(PirateTheme.broadcast, intensity: 0.8)
                    .padding(.top, 24)

                // Join code
                HStack(spacing: 12) {
                    ForEach(Array(session.joinCode.enumerated()), id: \.offset) { _, char in
                        Text(String(char))
                            .font(PirateTheme.display(40))
                            .foregroundStyle(PirateTheme.broadcast)
                            .frame(width: 50, height: 62)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(PirateTheme.broadcast.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(PirateTheme.broadcast, lineWidth: 1.5)
                            )
                            .neonGlow(PirateTheme.broadcast, intensity: 0.4)
                    }
                }

                // Share + member count row
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                        Text("\(session.members.count) crew")
                    }
                    .font(PirateTheme.body(13))
                    .foregroundStyle(.white.opacity(0.5))

                    Spacer()

                    ShareLink(
                        item: "Join my Pirate Radio session! Code: \(session.joinCode)",
                        subject: Text("Pirate Radio"),
                        message: Text("Tune in with code \(session.joinCode)")
                    ) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(PirateTheme.body(13))
                        .foregroundStyle(PirateTheme.signal)
                    }
                }

                // Divider
                Rectangle()
                    .fill(PirateTheme.signal.opacity(0.15))
                    .frame(height: 0.5)

                // Top tracks section
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR TOP TRACKS")
                        .font(PirateTheme.body(11))
                        .foregroundStyle(PirateTheme.signal.opacity(0.6))

                    if isLoadingTracks {
                        ProgressView()
                            .tint(PirateTheme.signal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else if topTracks.isEmpty {
                        Button {
                            showQueue = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                Text("Search for a track")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))
                    } else {
                        ForEach(topTracks) { track in
                            Button {
                                Task { await sessionStore.play(track: track) }
                            } label: {
                                trackRow(track)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Search fallback
                if !topTracks.isEmpty {
                    Button {
                        showQueue = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("Search for more")
                        }
                        .font(PirateTheme.body(13))
                        .foregroundStyle(PirateTheme.signal.opacity(0.6))
                    }
                    .padding(.top, 4)
                }

                // Connection status
                ConnectionStatusBadge(state: sessionStore.connectionState)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .task {
            if topTracks.isEmpty && !isLoadingTracks {
                await loadTopTracks()
            }
        }
    }

    // MARK: - Track Row

    private func trackRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            // Album art
            if let url = track.albumArtURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(PirateTheme.signal.opacity(0.1))
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(PirateTheme.body(14))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(track.artist)
                    .font(PirateTheme.body(12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(PirateTheme.broadcast)
        }
        .padding(.vertical, 4)
    }
}

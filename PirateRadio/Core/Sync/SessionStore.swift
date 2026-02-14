import Foundation

/// Single source of truth for the current session state.
/// ViewModels project slices of this store; the SyncEngine writes to it.
@Observable
@MainActor
final class SessionStore {
    // MARK: - State

    private(set) var session: Session?
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var syncStatus: SyncEngine.SyncStatus = .synced
    private(set) var isLoading = false
    private(set) var error: PirateRadioError?

    // Beat visualizer state
    private(set) var currentBPM: Double?
    private(set) var currentAnchor: NTPAnchoredPosition?
    private(set) var clockOffsetMs: Int64 = 0

    // MARK: - Dependencies

    private var syncEngine: SyncEngine?
    private let authManager: SpotifyAuthManager
    private let baseURL: URL

    // MARK: - Init

    init(authManager: SpotifyAuthManager, baseURL: URL = URL(string: "https://pirate-radio-sync.fly.dev")!) {
        self.authManager = authManager
        self.baseURL = baseURL
    }

    // MARK: - Demo Mode

    static func demo() -> SessionStore {
        let auth = SpotifyAuthManager()
        auth.enableDemoMode()
        let store = SessionStore(authManager: auth)
        store.connectionState = .connected
        store.currentBPM = 120.0
        store.currentAnchor = NTPAnchoredPosition(
            trackID: "7GhIk7Il098yCjg4BQjzvb",
            positionAtAnchor: 0,
            ntpAnchor: UInt64(Date().timeIntervalSince1970 * 1000),
            playbackRate: 1.0
        )
        store.session = Session(
            id: "demo-session",
            joinCode: "1073",
            creatorID: "demo-user-1",
            djUserID: "demo-user-1",
            members: [
                Session.Member(id: "demo-user-1", displayName: "DJ Powder", isConnected: true),
                Session.Member(id: "demo-user-2", displayName: "Shredder", isConnected: true),
                Session.Member(id: "demo-user-3", displayName: "Avalanche", isConnected: true),
            ],
            queue: [
                Track(id: "4PTG3Z6ehGkBFwjybzWkR8", name: "Bohemian Rhapsody", artist: "Queen", albumName: "A Night at the Opera", albumArtURL: URL(string: "https://i.scdn.co/image/ab67616d0000b273ce4f1737bc8a646c8c4bd25a"), durationMs: 354_947),
                Track(id: "3n3Ppam7vgaVa1iaRUc9Lp", name: "Mr. Brightside", artist: "The Killers", albumName: "Hot Fuss", albumArtURL: URL(string: "https://i.scdn.co/image/ab67616d0000b273ccdddd46119a4ff53eaf1f5a"), durationMs: 222_200),
            ],
            currentTrack: Track(
                id: "7GhIk7Il098yCjg4BQjzvb",
                name: "Never Gonna Give You Up",
                artist: "Rick Astley",
                albumName: "Whenever You Need Somebody",
                albumArtURL: URL(string: "https://i.scdn.co/image/ab67616d0000b27315b2e54b00ef29ab852a09a0"),
                durationMs: 213_573
            ),
            isPlaying: true,
            epoch: 1
        )
        return store
    }

    // MARK: - Actions

    func createSession() async {
        isLoading = true
        error = nil

        do {
            let backendToken = try await getBackendToken()
            let session = try await createSessionOnBackend(token: backendToken)
            self.session = session

            try await connectToSession(sessionID: session.id, token: backendToken)
        } catch {
            self.error = .sessionCreationFailed(underlying: error)
        }

        isLoading = false
    }

    func joinSession(code: String) async {
        isLoading = true
        error = nil

        do {
            let backendToken = try await getBackendToken()
            let sessionInfo = try await joinSessionOnBackend(code: code, token: backendToken)

            self.session = Session(
                id: sessionInfo.id,
                joinCode: sessionInfo.joinCode,
                creatorID: "",
                djUserID: sessionInfo.djUserId,
                members: [],
                queue: [],
                currentTrack: nil,
                isPlaying: false,
                epoch: 0
            )

            try await connectToSession(sessionID: sessionInfo.id, token: backendToken)
        } catch {
            self.error = .sessionNotFound
        }

        isLoading = false
    }

    func leaveSession() async {
        await syncEngine?.stop()
        syncEngine = nil
        session = nil
        connectionState = .disconnected
    }

    // MARK: - DJ Actions

    var isDJ: Bool {
        guard let session, let userID = authManager.userID else { return false }
        return session.djUserID == userID
    }

    func play(track: Track) async {
        guard isDJ else { return }
        do {
            try await syncEngine?.djPlay(track: track)
        } catch {
            self.error = .playbackFailed(underlying: error)
        }
    }

    func pause() async {
        guard isDJ else { return }
        try? await syncEngine?.djPause()
    }

    func resume() async {
        guard isDJ else { return }
        try? await syncEngine?.djResume()
    }

    func seek(to positionMs: Int) async {
        guard isDJ else { return }
        try? await syncEngine?.djSeek(to: positionMs)
    }

    // MARK: - Beat Visualizer

    /// Computes current playback position in seconds from the NTP-anchored system.
    /// Used by BeatVisualizer to derive beat phase each frame.
    func currentPlaybackPosition(at date: Date) -> Double {
        guard let anchor = currentAnchor else { return 0 }
        let ntpNow = UInt64(date.timeIntervalSince1970 * 1000) + UInt64(max(0, clockOffsetMs))
        return anchor.positionAt(ntpTime: ntpNow)
    }

    private var spotifyClient: SpotifyClient? {
        SpotifyClient(authManager: authManager)
    }

    private func fetchBPMForTrack(_ trackID: String) async {
        // Check if current track already has BPM cached
        if let bpm = session?.currentTrack?.bpm, bpm > 0 {
            currentBPM = bpm
            return
        }

        guard let client = spotifyClient else { return }
        do {
            let features = try await client.fetchAudioFeatures(trackID: trackID)
            currentBPM = features.tempo
            session?.currentTrack?.bpm = features.tempo
        } catch {
            currentBPM = nil
        }
    }

    // MARK: - Private

    private func connectToSession(sessionID: String, token: String) async throws {
        let transport = WebSocketTransport(baseURL: baseURL)
        let clock = KronosClock()
        let player = SpotifyPlayer()

        let engine = SyncEngine(musicSource: player, transport: transport, clock: clock)

        // Bridge SyncEngine updates to @Observable state
        await engine.setOnSessionUpdate { [weak self] update in
            Task { @MainActor in
                self?.handleUpdate(update)
            }
        }

        try await engine.start(sessionID: sessionID, token: token)
        self.syncEngine = engine
    }

    private func handleUpdate(_ update: SyncEngine.SessionUpdate) {
        switch update {
        case .connectionStateChanged(let state):
            connectionState = state
        case .syncStatus(let status):
            syncStatus = status
        case .playbackStateChanged(let isPlaying, _):
            session?.isPlaying = isPlaying
        case .memberJoined(let userID, let name):
            session?.members.append(Session.Member(id: userID, displayName: name, isConnected: true))
        case .memberLeft(let userID):
            session?.members.removeAll { $0.id == userID }
        case .queueUpdated:
            break // Queue updates handled separately
        case .anchorUpdated(let anchor, let offsetMs):
            currentAnchor = anchor
            clockOffsetMs = offsetMs
        case .trackChanged(let track):
            session?.currentTrack = track
            if let track {
                Task { await fetchBPMForTrack(track.id) }
            } else {
                currentBPM = nil
            }
        }
    }

    private func getBackendToken() async throws -> String {
        guard let userID = authManager.userID else {
            throw PirateRadioError.notAuthenticated
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("auth"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["spotifyUserId": userID, "displayName": authManager.displayName ?? userID]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        return response.token
    }

    private func createSessionOnBackend(token: String) async throws -> Session {
        var request = URLRequest(url: baseURL.appendingPathComponent("sessions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(CreateSessionResponse.self, from: data)

        return Session(
            id: response.id,
            joinCode: response.joinCode,
            creatorID: response.creatorId,
            djUserID: response.djUserId,
            members: [],
            queue: [],
            currentTrack: nil,
            isPlaying: false,
            epoch: 0
        )
    }

    private func joinSessionOnBackend(code: String, token: String) async throws -> JoinSessionResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("sessions/join"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["code": code]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PirateRadioError.sessionNotFound
        }

        return try JSONDecoder().decode(JoinSessionResponse.self, from: data)
    }
}

// MARK: - SyncEngine extension for callback setter

extension SyncEngine {
    func setOnSessionUpdate(_ handler: @escaping (SessionUpdate) -> Void) {
        self.onSessionUpdate = handler
    }
}

// MARK: - API Response Models

private struct AuthResponse: Codable {
    let token: String
}

private struct CreateSessionResponse: Codable {
    let id: String
    let joinCode: String
    let creatorId: String
    let djUserId: String
}

private struct JoinSessionResponse: Codable {
    let id: String
    let joinCode: String
    let djUserId: String
    let memberCount: Int
}

import Foundation

/// Single source of truth for the current session state.
/// In the public station model, there is no DJ — anyone can skip or add to queue.
@Observable
@MainActor
final class SessionStore {
    // MARK: - State

    private(set) var session: Session?
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var syncStatus: SyncEngine.SyncStatus = .synced
    private(set) var isLoading = false
    private(set) var error: PirateRadioError?

    // MARK: - BPM (stub — not yet wired to Spotify audio analysis)

    var currentBPM: Double? { nil }

    // Playback anchor from the last stateSync — used to compute current position
    private(set) var playbackAnchor: NTPAnchoredPosition?
    private var clock: (any ClockProvider)?

    /// Current playback position in seconds, computed from the NTP-anchored position.
    var currentPlaybackPosition: Double {
        guard let anchor = playbackAnchor, let clock else { return 0 }
        return anchor.positionAt(ntpTime: clock.now())
    }

    // MARK: - Dial Home State

    private(set) var stations: [Station] = []
    private(set) var isAutoTuning = false
    private var tuneTask: Task<Void, Never>?
    private var spotifyWakeTask: Task<Void, Never>?
    private var tuneGeneration: UUID = UUID()

    // MARK: - Token Cache

    private var cachedToken: String?
    private var tokenExpiry: Date?

    // MARK: - Dependencies

    private var syncEngine: SyncEngine?
    private let authManager: SpotifyAuthManager
    private let baseURL: URL
    var toastManager: ToastManager?

    // MARK: - Init

    init(authManager: SpotifyAuthManager, baseURL: URL = URL(string: "https://pirate-radio-sync.fly.dev")!) {
        self.authManager = authManager
        self.baseURL = baseURL
    }

    // MARK: - Station Actions

    func leaveSession() async {
        await syncEngine?.stop()
        syncEngine = nil
        clock = nil
        playbackAnchor = nil
        session = nil
        connectionState = .disconnected
        BackgroundAudioKeepAlive.shared.stop()
    }

    /// Fetch all stations from the server.
    func fetchStations() async {
        do {
            let token = try await getBackendToken()
            var request = URLRequest(url: baseURL.appendingPathComponent("stations"))
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }

            let decoded = try JSONDecoder().decode(StationsResponse.self, from: data)
            stations = decoded.stations
        } catch {
            print("[SessionStore] fetchStations error: \(error)")
        }
    }

    /// Auto-tune to the last-listened station (or first station) on app launch.
    func autoTune() async {
        guard !isAutoTuning, session == nil else { return }
        isAutoTuning = true
        defer { isAutoTuning = false }

        await fetchStations()
        guard !stations.isEmpty else { return }

        let lastStationId = UserDefaults.standard.string(forKey: "lastTunedStationId")
        guard let target = stations.first(where: { $0.id == lastStationId }) ?? stations.first else { return }

        await tuneToStationById(target.id)
        if error == nil {
            UserDefaults.standard.set(target.id, forKey: "lastTunedStationId")
        }
    }

    /// Tune to a specific station from the dial. Cancel-and-replace for rapid switching.
    func tuneToStation(_ station: Station) {
        guard session?.id != station.id else { return }
        tuneTask?.cancel()
        let generation = UUID()
        tuneGeneration = generation
        tuneTask = Task {
            if session != nil {
                await leaveSession()
            }
            guard !Task.isCancelled, tuneGeneration == generation else { return }
            await tuneToStationById(station.id)
            guard tuneGeneration == generation else {
                await leaveSession()
                return
            }
            if error == nil {
                UserDefaults.standard.set(station.id, forKey: "lastTunedStationId")
            }
        }
    }

    /// Connect directly to a station by its ID.
    func tuneToStationById(_ stationId: String) async {
        isLoading = true
        error = nil

        do {
            let backendToken = try await getBackendToken()

            // Create a minimal session — stateSync will fill in the details
            self.session = Session(
                id: stationId,
                members: [],
                queue: [],
                currentTrack: nil,
                isPlaying: false,
                epoch: 0
            )

            try await connectToStation(stationID: stationId, token: backendToken)
        } catch {
            self.error = .sessionNotFound
            self.session = nil
        }

        isLoading = false
    }

    // MARK: - Playback Actions (available to all)

    func addToQueue(track: Track) async {
        await syncEngine?.sendAddToQueue(track: track)
    }

    func skipToNext() async {
        await syncEngine?.sendSkip()
    }

    func toggleMute() async {
        await syncEngine?.toggleLocalMute()
    }

    // MARK: - Private

    private func connectToStation(stationID: String, token: String) async throws {
        let transport = WebSocketTransport(baseURL: baseURL)
        let clock = KronosClock()
        self.clock = clock
        let player = SpotifyPlayer(appRemote: authManager.appRemote)

        let engine = SyncEngine(musicSource: player, transport: transport, clock: clock)

        await engine.setOnSessionUpdate { [weak self] update in
            Task { @MainActor in
                self?.handleUpdate(update)
            }
        }

        try await engine.start(sessionID: stationID, token: token)
        self.syncEngine = engine

        // Start background audio keep-alive so iOS doesn't suspend the app
        // when the screen is off. Spotify plays audio in its own process,
        // so without this our sync engine would be killed.
        BackgroundAudioKeepAlive.shared.start()
    }

    // internal for testability
    func handleUpdate(_ update: SyncEngine.SessionUpdate) {
        switch update {
        case .connectionStateChanged(let state):
            connectionState = state
            if case .failed(let reason) = state {
                print("[SessionStore] Connection failed: \(reason)")
                syncEngine = nil
                session = nil
                error = .sessionNotFound
                BackgroundAudioKeepAlive.shared.stop()
            }
        case .syncStatus(let status):
            syncStatus = status
        case .playbackStateChanged(let isPlaying, _):
            session?.isPlaying = isPlaying
        case .memberJoined(let userID, let name):
            if let idx = session?.members.firstIndex(where: { $0.id == userID }) {
                if !name.isEmpty {
                    session?.members[idx].displayName = name
                }
                session?.members[idx].isConnected = true
            } else {
                let color = AvatarColor.allCases.filter { c in
                    session?.members.contains { $0.avatarColor == c } != true
                }.randomElement() ?? .cyan
                session?.members.append(Session.Member(
                    id: userID, displayName: name.isEmpty ? userID : name,
                    isConnected: true, avatarColor: color
                ))
            }
        case .memberLeft(let userID):
            session?.members.removeAll { $0.id == userID }
        case .queueUpdated(let tracks):
            session?.queue = tracks
        case .trackChanged:
            break
        case .stateSynced(let snapshot):
            handleStateSync(snapshot)
        }
    }

    // internal for testability
    func handleStateSync(_ snapshot: SessionSnapshot) {
        print("[SessionStore] Received stateSync: members=\(snapshot.members.count), track=\(snapshot.trackID ?? "none")")

        // Update station name if provided
        if !snapshot.stationName.isEmpty {
            session?.stationName = snapshot.stationName
        }

        // Replace member list with server-authoritative data
        if !snapshot.members.isEmpty {
            var updatedMembers: [Session.Member] = []
            let usedColors = Set(session?.members.map { $0.avatarColor } ?? [])
            var availableColors = AvatarColor.allCases.filter { !usedColors.contains($0) }

            for sm in snapshot.members {
                if let existing = session?.members.first(where: { $0.id == sm.userId }) {
                    var member = existing
                    member.displayName = sm.displayName
                    member.isConnected = true
                    updatedMembers.append(member)
                } else {
                    let color = availableColors.isEmpty ? AvatarColor.allCases.randomElement()! : availableColors.removeFirst()
                    updatedMembers.append(Session.Member(
                        id: sm.userId, displayName: sm.displayName,
                        isConnected: true, avatarColor: color
                    ))
                }
            }
            session?.members = updatedMembers
        }

        // Update playback state
        session?.isPlaying = snapshot.playbackRate > 0
        session?.epoch = snapshot.epoch

        // Store anchor so UI can compute current playback position
        if let trackID = snapshot.trackID {
            playbackAnchor = NTPAnchoredPosition(
                trackID: trackID,
                positionAtAnchor: snapshot.positionAtAnchor,
                ntpAnchor: snapshot.ntpAnchor,
                playbackRate: snapshot.playbackRate
            )
        }

        // Update current track
        if let track = snapshot.currentTrack {
            session?.currentTrack = track
        } else if snapshot.trackID == nil {
            session?.currentTrack = nil
        }

        // Update queue
        session?.queue = snapshot.queue

        // Show toast when station ran out of music
        if snapshot.playbackRate == 0, snapshot.queue.isEmpty, snapshot.currentTrack == nil {
            toastManager?.show(.queueEmpty, message: "Station ran out of music — add a song!")
        }

        // Wake Spotify if music is playing but not connected
        if snapshot.playbackRate > 0 && snapshot.trackID != nil {
            if !authManager.isConnectedToSpotifyApp {
                print("[SessionStore] stateSync shows active playback — waking Spotify")
                spotifyWakeTask?.cancel()
                spotifyWakeTask = Task {
                    await ensureSpotifyConnected(trackID: snapshot.trackID)
                    guard !Task.isCancelled else { return }
                    if authManager.isConnectedToSpotifyApp {
                        print("[SessionStore] Spotify connected — retrying catch-up playback")
                        await syncEngine?.retryCatchUpPlayback()
                    }
                }
            }
        }
    }

    private func ensureSpotifyConnected(trackID: String? = nil) async {
        let uri = trackID.map { "spotify:track:\($0)" } ?? ""
        authManager.wakeSpotifyAndConnect(playURI: uri)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if authManager.isConnectedToSpotifyApp { break }
        }
    }

    private func getBackendToken() async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(3600) {
            return token
        }

        if authManager.userID == nil || authManager.displayName == nil {
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(300))
                if authManager.userID != nil && authManager.displayName != nil { break }
            }
        }
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

        cachedToken = response.token
        tokenExpiry = Date().addingTimeInterval(24 * 3600)
        return response.token
    }
}

// MARK: - Demo Mode

extension SessionStore {
    static func demo() -> SessionStore {
        let auth = SpotifyAuthManager()
        auth.enableDemoMode()
        let store = SessionStore(authManager: auth)
        store.session = MockData.demoSession()
        store.connectionState = .connected
        return store
    }

    // MARK: - Demo Actions

    func toggleVote(trackID: String, isUpvote: Bool) {
        guard var queue = session?.queue,
              let idx = queue.firstIndex(where: { $0.id == trackID }) else { return }

        if isUpvote {
            if queue[idx].isUpvotedByMe {
                queue[idx].votes -= 1
                queue[idx].isUpvotedByMe = false
            } else {
                queue[idx].votes += 1
                queue[idx].isUpvotedByMe = true
                if queue[idx].isDownvotedByMe {
                    queue[idx].votes += 1
                    queue[idx].isDownvotedByMe = false
                }
            }
        } else {
            if queue[idx].isDownvotedByMe {
                queue[idx].votes += 1
                queue[idx].isDownvotedByMe = false
            } else {
                queue[idx].votes -= 1
                queue[idx].isDownvotedByMe = true
                if queue[idx].isUpvotedByMe {
                    queue[idx].votes -= 1
                    queue[idx].isUpvotedByMe = false
                }
            }
        }
        session?.queue = queue
    }

    func acceptRequest(_ track: Track) {
        session?.queue.append(track)
    }

    func demoSkipToNext() {
        guard let queue = session?.queue, !queue.isEmpty else { return }
        session?.currentTrack = queue.first
        session?.queue = Array(queue.dropFirst())
    }

    func addMember(_ member: Session.Member) {
        guard session?.members.contains(where: { $0.id == member.id }) != true else { return }
        session?.members.append(member)
    }

    func removeMember(_ userID: UserID) {
        session?.members.removeAll { $0.id == userID }
    }

    func clearCurrentTrack() {
        session?.currentTrack = nil
    }

    func endSession() {
        session = nil
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

private struct StationsResponse: Codable {
    let stations: [Station]
}

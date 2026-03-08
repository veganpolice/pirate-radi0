import Foundation
import os

private let logger = Logger(subsystem: "com.pirateradio", category: "SessionStore")

/// Single source of truth for the current session state.
/// ViewModels project slices of this store; the SyncEngine writes to it.
@Observable
@MainActor
final class SessionStore {
    // MARK: - State

    private(set) var session: Session?
    private(set) var isCreator = false
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var syncStatus: SyncEngine.SyncStatus = .synced
    private(set) var isLoading = false
    private(set) var error: PirateRadioError?

    // MARK: - Station State

    /// Whether the user needs to pick a frequency (new user, no station yet).
    private(set) var needsFrequency = false
    /// The user's own station frequency (nil if no station yet).
    private(set) var myFrequency: Int?

    // MARK: - Dial Home State

    private(set) var stations: [Station] = []
    private(set) var isAutoTuning = false
    private var tuneTask: Task<Void, Never>?
    private var tuneGeneration: UUID = UUID()

    // MARK: - Token Cache

    private var cachedToken: String?
    private var tokenExpiry: Date?

    // MARK: - Dependencies

    private var syncEngine: SyncEngine?
    private let authManager: SpotifyAuthManager
    private let baseURL: URL
    var toastManager: ToastManager?

    /// Cooldown to prevent reassertPlayback from triple-firing on reconnect.
    private var lastReassertTime: ContinuousClock.Instant = .now - .seconds(10)
    private let reassertCooldown: Duration = .seconds(2)

    // MARK: - Init

    init(authManager: SpotifyAuthManager, baseURL: URL = URL(string: "https://pirate-radio-sync.fly.dev")!) {
        self.authManager = authManager
        self.baseURL = baseURL
    }

    // MARK: - Actions

    /// Claim a frequency for the user's station. Called from FrequencyPickerView.
    func claimFrequency(_ frequency: Int) async {
        isLoading = true
        error = nil

        do {
            let token = try await getBackendToken()
            var request = URLRequest(url: baseURL.appendingPathComponent("stations/claim-frequency"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["frequency": frequency])

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 201 {
                needsFrequency = false
                myFrequency = frequency
                logger.notice("Claimed frequency \(frequency)")
            } else if status == 409 {
                let body = try? JSONDecoder().decode([String: String].self, from: data)
                error = .sessionCreationFailed(
                    underlying: NSError(domain: "PirateRadio", code: 409,
                                        userInfo: [NSLocalizedDescriptionKey: body?["error"] ?? "Frequency taken"])
                )
            } else {
                error = .sessionCreationFailed(
                    underlying: NSError(domain: "PirateRadio", code: status,
                                        userInfo: [NSLocalizedDescriptionKey: "Failed to claim frequency"])
                )
            }
        } catch {
            self.error = .sessionCreationFailed(underlying: error)
        }

        isLoading = false
    }

    /// Tune to the user's own station (replaces "Start Broadcasting").
    func tuneToMyStation() async {
        guard let userID = authManager.userID else { return }

        // If we're already on our own station, do nothing
        if session?.id == userID { return }

        if session != nil {
            await leaveSession()
        }
        await joinSessionById(userID)
        if error == nil {
            UserDefaults.standard.set(userID, forKey: "lastTunedUserId")
        }
    }

    func leaveSession() async {
        await syncEngine?.stop()
        syncEngine = nil
        session = nil
        isCreator = false
        connectionState = .disconnected
        authManager.onAppRemoteConnected = nil
        authManager.unsubscribeFromPlayerState()
    }

    // MARK: - Dial Home Actions

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

    /// Auto-tune to own station on app launch (or last-listened station).
    func autoTune() async {
        guard !isAutoTuning, session == nil else { return }
        isAutoTuning = true
        defer { isAutoTuning = false }

        await fetchStations()

        guard let userID = authManager.userID else { return }

        // Prefer own station first, then last-listened, then first live station
        let lastUserId = UserDefaults.standard.string(forKey: "lastTunedUserId")
        let target = stations.first(where: { $0.userId == userID })
            ?? stations.first(where: { $0.userId == lastUserId })
            ?? stations.first(where: { $0.isLive })

        guard let station = target else { return }

        await joinSessionById(station.userId)
        if error == nil {
            UserDefaults.standard.set(station.userId, forKey: "lastTunedUserId")
        }
    }

    /// Tune to a specific station from the dial. Cancel-and-replace for rapid switching.
    func tuneToStation(_ station: Station) {
        guard session?.id != station.userId else { return }
        tuneTask?.cancel()
        let generation = UUID()
        tuneGeneration = generation
        tuneTask = Task {
            if session != nil {
                await leaveSession()
            }
            guard !Task.isCancelled, tuneGeneration == generation else { return }
            await joinSessionById(station.userId)
            guard tuneGeneration == generation else {
                await leaveSession()
                return
            }
            if error == nil {
                UserDefaults.standard.set(station.userId, forKey: "lastTunedUserId")
            }
        }
    }

    /// Join a station by the owner's userId.
    func joinSessionById(_ stationUserId: String) async {
        isLoading = true
        error = nil

        do {
            let backendToken = try await getBackendToken()
            let sessionInfo = try await joinSessionByIdOnBackend(userId: stationUserId, token: backendToken)

            var members: [Session.Member] = []

            // Add the DJ if present
            if let djId = sessionInfo.djUserId {
                let djMember = Session.Member(
                    id: djId,
                    displayName: djId, // will be corrected by stateSync
                    isConnected: true,
                    avatarColor: .cyan
                )
                members.append(djMember)
            }

            // Add ourselves if not the DJ
            if let myID = authManager.userID, myID != sessionInfo.djUserId {
                let me = Session.Member(
                    id: myID,
                    displayName: authManager.displayName ?? myID,
                    isConnected: true,
                    avatarColor: AvatarColor.allCases.filter { $0 != .cyan }.randomElement()!
                )
                members.append(me)
            }

            self.session = Session(
                id: sessionInfo.userId,
                creatorID: sessionInfo.userId,
                djUserID: sessionInfo.djUserId,
                members: members,
                queue: [],
                currentTrack: nil,
                isPlaying: false,
                epoch: 0
            )
            self.isCreator = (authManager.userID == sessionInfo.userId)

            try await connectToSession(sessionID: sessionInfo.userId, token: backendToken)
        } catch is CancellationError {
            return
        } catch let pirateError as PirateRadioError {
            self.error = pirateError
        } catch let urlError as URLError {
            print("[SessionStore] joinSessionById network error: \(urlError)")
            self.error = .notConnected
        } catch {
            print("[SessionStore] joinSessionById unexpected error: \(error)")
            self.error = .sessionNotFound
        }

        isLoading = false
    }

    // MARK: - DJ Actions

    var isDJ: Bool {
        guard let session, let userID = authManager.userID else { return false }
        return session.djUserID == userID
    }

    func play(track: Track) async {
        print("[SessionStore] play() called — isDJ=\(isDJ), appRemoteConnected=\(authManager.isConnectedToSpotifyApp)")
        let canPlay = isDJ || (session?.members.isEmpty == true)
        guard canPlay else { return }

        session?.currentTrack = track
        session?.isPlaying = true

        if !authManager.isConnectedToSpotifyApp {
            print("[SessionStore] AppRemote not connected — waking Spotify app")
            await ensureSpotifyConnected()
            if !authManager.isConnectedToSpotifyApp {
                print("[SessionStore] Still not connected after waiting")
                self.error = .playbackFailed(underlying: NSError(domain: "PirateRadio", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not connect to Spotify app. Make sure Spotify is installed."]))
                return
            }
        }

        do {
            try await syncEngine?.djPlay(track: track)
            print("[SessionStore] djPlay sent successfully via SyncEngine")
        } catch {
            print("[SessionStore] djPlay error: \(error)")
            self.error = .playbackFailed(underlying: error)
            session?.isPlaying = false
            let desc = (error as NSError).localizedDescription.lowercased()
            if desc.contains("premium") || desc.contains("permission") || desc.contains("restricted") {
                toastManager?.show(.spotifyError, message: "Spotify Premium required for playback")
            }
        }
    }

    /// Wake Spotify app and wait for AppRemote connection.
    private func ensureSpotifyConnected() async {
        authManager.wakeSpotifyAndConnect()
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if authManager.isConnectedToSpotifyApp { break }
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

    func addToQueue(track: Track) async {
        if session?.currentTrack == nil, isDJ {
            await play(track: track)
            return
        }
        await syncEngine?.sendAddToQueue(track: track)
    }

    func batchAddToQueue(tracks: [Track]) async {
        guard !tracks.isEmpty else { return }
        await syncEngine?.sendBatchAddToQueue(tracks: tracks)
    }

    func skipToNext() async {
        guard isDJ else { return }
        guard session?.queue.isEmpty == false else { return }
        await syncEngine?.sendSkip()
    }

    // MARK: - Private

    private func connectToSession(sessionID: String, token: String) async throws {
        let transport = WebSocketTransport(baseURL: baseURL)
        let clock = KronosClock()

        #if targetEnvironment(simulator)
        let player: any MusicSource = MockMusicSource()
        #else
        let player = SpotifyPlayer(appRemote: authManager.appRemote)

        await player.setOnTrackMismatch { [weak self] in
            Task { @MainActor in
                await self?.reassertPlayback()
            }
        }
        #endif

        let engine = SyncEngine(musicSource: player, transport: transport, clock: clock)

        await engine.setOnSessionUpdate { [weak self] update in
            Task { @MainActor in
                self?.handleUpdate(update)
            }
        }

        #if !targetEnvironment(simulator)
        let bridge = PlayerStateBridge(player: player)
        authManager.onAppRemoteConnected = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.handleAppRemoteReconnected(bridge: bridge)
            }
        }
        #endif

        try await engine.start(sessionID: sessionID, token: token)
        self.syncEngine = engine

        #if !targetEnvironment(simulator)
        if authManager.isConnectedToSpotifyApp {
            await handleAppRemoteReconnected(bridge: bridge)
        }
        #endif
    }

    private func handleAppRemoteReconnected(bridge: PlayerStateBridge) async {
        logger.notice("AppRemote reconnected — re-subscribing to player state")
        authManager.subscribeToPlayerState(delegate: bridge)
        await reassertPlayback()
    }

    private func reassertPlayback() async {
        let now = ContinuousClock.now
        guard now - lastReassertTime > reassertCooldown else {
            logger.debug("Reassert skipped — cooldown active")
            return
        }
        guard let session, session.isPlaying,
              session.currentTrack != nil else { return }
        lastReassertTime = now
        logger.notice("Reasserting station playback")
        toastManager?.show(.reconnected, message: "Tuning back to station...")
        await syncEngine?.retryCatchUpPlayback()
    }

    private func handleUpdate(_ update: SyncEngine.SessionUpdate) {
        switch update {
        case .connectionStateChanged(let state):
            connectionState = state
            if case .failed(let reason) = state {
                print("[SessionStore] Connection failed: \(reason)")
                syncEngine = nil
                session = nil
                error = .sessionNotFound
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

    private func handleStateSync(_ snapshot: SessionSnapshot) {
        print("[SessionStore] Received stateSync: dj=\(snapshot.djUserID ?? "nil"), members=\(snapshot.members.count), track=\(snapshot.trackID ?? "none")")

        // Update DJ (may be nil for autonomous playback)
        session?.djUserID = snapshot.djUserID

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

        session?.isPlaying = snapshot.playbackRate > 0
        session?.epoch = snapshot.epoch

        if let track = snapshot.currentTrack {
            session?.currentTrack = track
        }

        session?.queue = snapshot.queue

        // Show toast when station ran out of music
        if isDJ, snapshot.playbackRate == 0, snapshot.queue.isEmpty, snapshot.currentTrack != nil {
            toastManager?.show(.queueEmpty, message: "Your station ran out of music")
        }

        // Wake Spotify if music is playing
        if snapshot.playbackRate > 0 && snapshot.trackID != nil {
            if !authManager.isConnectedToSpotifyApp {
                print("[SessionStore] stateSync shows active playback — waking Spotify for listener")
                Task {
                    await ensureSpotifyConnected()
                    if authManager.isConnectedToSpotifyApp {
                        print("[SessionStore] Spotify connected — retrying catch-up playback")
                        await syncEngine?.retryCatchUpPlayback()
                    }
                }
            }
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

        // Update station state from auth response
        needsFrequency = response.needsFrequency
        myFrequency = response.frequency

        return response.token
    }

    private func joinSessionByIdOnBackend(userId: String, token: String) async throws -> JoinByIdResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("sessions/join-by-id"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["userId": userId]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PirateRadioError.sessionNotFound
        }
        switch httpResponse.statusCode {
        case 200: break
        case 401: throw PirateRadioError.tokenExpired
        case 404: throw PirateRadioError.sessionNotFound
        case 409: throw PirateRadioError.sessionFull
        default:
            print("[SessionStore] join-by-id unexpected status: \(httpResponse.statusCode)")
            throw PirateRadioError.notConnected
        }

        return try JSONDecoder().decode(JoinByIdResponse.self, from: data)
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

    func demoSkipToNext() {
        guard let queue = session?.queue, !queue.isEmpty else { return }
        session?.currentTrack = queue.first
        session?.queue = Array(queue.dropFirst())
    }

    func setDJ(_ userID: UserID) {
        session?.djUserID = userID
    }

    func removeMember(_ userID: UserID) {
        session?.members.removeAll { $0.id == userID }
    }

    func demoAppendToQueue(_ track: Track) {
        session?.queue.append(track)
    }

    func addMember(_ member: Session.Member) {
        guard session?.members.contains(where: { $0.id == member.id }) != true else { return }
        session?.members.append(member)
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
    let needsFrequency: Bool
    let frequency: Int?
}

private struct JoinByIdResponse: Codable {
    let userId: String
    let djUserId: String?
    let memberCount: Int
}

private struct StationsResponse: Codable {
    let stations: [Station]
}

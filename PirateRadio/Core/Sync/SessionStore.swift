import Foundation

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

    // MARK: - Dependencies

    private var syncEngine: SyncEngine?
    private let authManager: SpotifyAuthManager
    private let baseURL: URL

    // MARK: - Init

    init(authManager: SpotifyAuthManager, baseURL: URL = URL(string: "https://pirate-radio-sync.fly.dev")!) {
        self.authManager = authManager
        self.baseURL = baseURL
    }

    // MARK: - Actions

    func createSession() async {
        guard !isLoading, session == nil else { return } // Prevent double-create
        isLoading = true
        error = nil

        do {
            print("[SessionStore] Creating session... userID=\(authManager.userID ?? "nil")")
            let backendToken = try await getBackendToken()
            print("[SessionStore] Got backend token")
            let session = try await createSessionOnBackend(token: backendToken)
            print("[SessionStore] Session created: \(session.id), code: \(session.joinCode)")
            self.session = session
            self.isCreator = true

            try await connectToSession(sessionID: session.id, token: backendToken)
            print("[SessionStore] Connected to session")
        } catch {
            print("[SessionStore] ERROR: \(error)")
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

            // Add the DJ and ourselves as members
            var members: [Session.Member] = []

            // Add the DJ/host (display name will be corrected by stateSync)
            let djMember = Session.Member(
                id: sessionInfo.djUserId,
                displayName: sessionInfo.djDisplayName ?? sessionInfo.djUserId,
                isConnected: true,
                avatarColor: .cyan
            )
            members.append(djMember)

            // Add ourselves if we're not the DJ
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
                id: sessionInfo.id,
                joinCode: sessionInfo.joinCode,
                creatorID: sessionInfo.djUserId,
                djUserID: sessionInfo.djUserId,
                members: members,
                queue: [],
                currentTrack: nil,
                isPlaying: false,
                epoch: 0,
                djMode: .solo
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
        print("[SessionStore] play() called — isDJ=\(isDJ), appRemoteConnected=\(authManager.isConnectedToSpotifyApp)")
        // Skip DJ check for solo sessions with no members
        let canPlay = isDJ || (session?.members.isEmpty == true)
        guard canPlay else { return }

        // Set currentTrack immediately so UI navigates to the player
        session?.currentTrack = track
        session?.isPlaying = true

        // Ensure Spotify app is connected before playing
        if !authManager.isConnectedToSpotifyApp {
            print("[SessionStore] AppRemote not connected — waking Spotify app")
            await ensureSpotifyConnected()
            if !authManager.isConnectedToSpotifyApp {
                print("[SessionStore] Still not connected after waiting")
                self.error = .playbackFailed(underlying: NSError(domain: "PirateRadio", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not connect to Spotify app. Make sure Spotify is installed."]))
                return
            }
        }

        // Play through SyncEngine so all listeners get playback commands
        do {
            try await syncEngine?.djPlay(track: track)
            print("[SessionStore] djPlay sent successfully via SyncEngine")
        } catch {
            print("[SessionStore] djPlay error: \(error)")
            self.error = .playbackFailed(underlying: error)
            session?.isPlaying = false
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

    // MARK: - Private

    private func connectToSession(sessionID: String, token: String) async throws {
        let transport = WebSocketTransport(baseURL: baseURL)
        let clock = KronosClock()
        let player = SpotifyPlayer(appRemote: authManager.appRemote)

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
            // Deduplicate: update existing member or append new one
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
        case .queueUpdated:
            break // Queue updates handled separately
        case .trackChanged:
            break
        case .stateSynced(let snapshot):
            handleStateSync(snapshot)
        }
    }

    private func handleStateSync(_ snapshot: SessionSnapshot) {
        print("[SessionStore] Received stateSync: dj=\(snapshot.djUserID), members=\(snapshot.members.count), track=\(snapshot.trackID ?? "none")")

        // Update DJ
        session?.djUserID = snapshot.djUserID

        // Replace member list with server-authoritative data (preserves avatar colors for known members)
        if !snapshot.members.isEmpty {
            var updatedMembers: [Session.Member] = []
            let usedColors = Set(session?.members.map { $0.avatarColor } ?? [])
            var availableColors = AvatarColor.allCases.filter { !usedColors.contains($0) }

            for sm in snapshot.members {
                if let existing = session?.members.first(where: { $0.id == sm.userId }) {
                    // Keep existing member's avatar color, update display name
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

        // Update current track from snapshot if available
        if let track = snapshot.currentTrack {
            session?.currentTrack = track
        }

        // If music is playing and we're a listener, ensure Spotify is ready
        if snapshot.playbackRate > 0 && snapshot.trackID != nil && !isDJ {
            if !authManager.isConnectedToSpotifyApp {
                print("[SessionStore] stateSync shows active playback — waking Spotify for listener")
                Task { await ensureSpotifyConnected() }
            }
        }
    }

    private func getBackendToken() async throws -> String {
        // Profile may still be loading on fresh launch — wait briefly for userID
        if authManager.userID == nil {
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(300))
                if authManager.userID != nil { break }
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
        return response.token
    }

    private func createSessionOnBackend(token: String) async throws -> Session {
        var request = URLRequest(url: baseURL.appendingPathComponent("sessions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        if let httpStatus = (httpResponse as? HTTPURLResponse)?.statusCode, httpStatus >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            print("[SessionStore] Backend error \(httpStatus): \(body)")
            throw PirateRadioError.sessionCreationFailed(
                underlying: NSError(domain: "Backend", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: body])
            )
        }
        let response = try JSONDecoder().decode(CreateSessionResponse.self, from: data)

        // Add the creator as the first member
        let djMember = Session.Member(
            id: response.djUserId,
            displayName: authManager.displayName ?? response.djUserId,
            isConnected: true,
            avatarColor: .cyan
        )

        return Session(
            id: response.id,
            joinCode: response.joinCode,
            creatorID: response.creatorId,
            djUserID: response.djUserId,
            members: [djMember],
            queue: [],
            currentTrack: nil,
            isPlaying: false,
            epoch: 0,
            djMode: .solo
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

// MARK: - Demo Mode

extension SessionStore {
    static func demo(djMode: DJMode = .solo) -> SessionStore {
        let auth = SpotifyAuthManager()
        auth.enableDemoMode()
        let store = SessionStore(authManager: auth)
        store.session = MockData.demoSession(djMode: djMode)
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

    func skipToNext() {
        guard let queue = session?.queue, !queue.isEmpty else { return }
        session?.currentTrack = queue.first
        session?.queue = Array(queue.dropFirst())
    }

    func changeDJMode(_ mode: DJMode) {
        session?.djMode = mode
    }

    func setDJ(_ userID: UserID) {
        session?.djUserID = userID
    }

    func removeMember(_ userID: UserID) {
        session?.members.removeAll { $0.id == userID }
    }

    func addMember(_ member: Session.Member) {
        guard session?.members.contains(where: { $0.id == member.id }) != true else { return }
        session?.members.append(member)
    }

    func clearCurrentTrack() {
        session?.currentTrack = nil
    }

    func endSession() {
        session = nil
    }

    func setHotSeatSongsPerDJ(_ count: Int) {
        session?.hotSeatSongsPerDJ = count
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
    let djDisplayName: String?
    let memberCount: Int
}
